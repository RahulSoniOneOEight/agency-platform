"""Deterministic machine/human reference-client reports (Milestone F.3, Task 10).

The machine report is the single aggregated, self-verifying evidence artifact for
the reference-commerce client. It is built **only** from canonical client
artifacts plus the committed machine evidence (RF6): it records ids, versions,
counts, statuses, and references, and never copies a review/approval/QA authority
body. It never collapses the programme into a subjective score (RF5).

Determinism
-----------
Every value is derived deterministically. ``report_identity`` is
``"sha256:" + sha256`` over the canonical (sorted, compact) JSON of the report
*excluding* ``report_identity`` itself, so the report is self-verifying and a
fresh build is byte-identical on every platform (LF newlines).

Approval references
-------------------
The report records one entry per approval version with ``version``,
``review_round``, ``review_state_hash``, and ``source_commit_sha`` (ids/hashes
only). The Dart review authority's internal review-state hash is never copied
into ``reference-e2e/``; the report instead records a deterministic
``sha256:`` **reference identity** computed over the approval's recorded
evidence slice. This keeps each approval addressable and tamper-evident without
duplicating authority (RF6).

This module is Flutter-free (RF17).
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Mapping

import yaml

from tooling.reference_client.assertions import evaluate_assertions
from tooling.reference_client.evidence import load_evidence
from tooling.reference_client.fixture import (
    FIXTURE_RELATIVE,
    fixture_identity,
    load_fixture,
)
from tooling.reference_client.scenario import (
    SCENARIO_RELATIVE,
    load_scenario,
    scenario_ids,
)
from tooling.workflow.contracts import load_all_stage_contracts

REPORT_VERSION = 1

EVIDENCE_DIR_RELATIVE = Path("reference-e2e") / "evidence"
REPORT_DIR_RELATIVE = Path("reference-e2e") / "report"
ASSERTIONS_RELATIVE = Path("reference-e2e") / "assertions.yaml"
WORKFLOW_STATE_RELATIVE = Path("workflow-state.yaml")
CLIENT_PROFILE_RELATIVE = Path("derived") / "client-profile.yaml"
CLIENT_INPUT_RELATIVE = Path("input") / "client-input.yaml"

REVIEW_EVIDENCE_NAME = "review-approval-evidence.json"
CHANGE_EVIDENCE_NAME = "change-scenarios-evidence.json"
RESUME_EVIDENCE_NAME = "resume-evidence.json"

MACHINE_REPORT_NAME = "reference-report.json"
HUMAN_REPORT_NAME = "reference-report.md"

DIRECTION_IDS: tuple[str, ...] = ("a", "b", "c")

KNOWN_LIMITATIONS: tuple[str, ...] = (
    "Checkout is a platform gap (RF13): the merged platform has no governed "
    "checkout pattern, so the reference journey represents order conversion as "
    "the terminal `order` journey step plus the governed cart calls to action; "
    "a governed checkout pattern is deferred to a later milestone.",
    "Two fixtures have distinct roles (RF14): `prototype/fixtures/demo.yaml` is "
    "the runtime fixture pack and `reference-e2e/fixture.yaml` is the richer "
    "scenario/E2E fixture; unifying them is deliberately out of scope.",
    "Determinism of the Dart review/approval/QA journey is asserted "
    "behaviourally (RF5) because the Dart domain has no injectable clock; the "
    "committed machine evidence is the authoritative record of those outcomes.",
    "This report is explanatory evidence; it never replaces the machine "
    "assertions and never grants an approval or a production authorization.",
)


def _canonical_json(value: Any) -> str:
    """Return the canonical compact JSON form used for every report identity."""
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    )


def _reference_hash(value: Any) -> str:
    return "sha256:" + hashlib.sha256(
        _canonical_json(value).encode("utf-8")
    ).hexdigest()


def machine_report_identity(report: Mapping[str, Any]) -> str:
    """Return the self-verifying ``sha256:`` identity of a machine report."""
    body = {key: value for key, value in report.items() if key != "report_identity"}
    return _reference_hash(body)


def canonical_report(report: Mapping[str, Any]) -> str:
    """Return the canonical pretty JSON byte form of a machine report."""
    return json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"


def _relative_to(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def _load_yaml(path: Path) -> Any:
    if not path.exists():
        return None
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _load_client_profile(client_dir: Path) -> dict[str, Any]:
    profile = _load_yaml(client_dir / CLIENT_PROFILE_RELATIVE)
    profile = profile if isinstance(profile, dict) else {}
    client_input = _load_yaml(client_dir / CLIENT_INPUT_RELATIVE)
    display_name = client_dir.name
    if isinstance(client_input, dict):
        client = client_input.get("client")
        if isinstance(client, dict) and isinstance(client.get("display_name"), str):
            display_name = client["display_name"]
    return {
        "id": profile.get("id") or client_dir.name,
        "display_name": display_name,
        "business_model": profile.get("business_model") or "",
        "industry": profile.get("industry") or "",
        "use_cases": list(profile.get("use_cases") or []),
        "objectives": list(profile.get("objectives") or []),
        "personas": list(profile.get("personas") or []),
        "jobs": list(profile.get("jobs") or []),
        "platforms": list(profile.get("platforms") or []),
    }


def _load_directions(client_dir: Path) -> list[dict[str, Any]]:
    directions: list[dict[str, Any]] = []
    for direction_id in DIRECTION_IDS:
        path = client_dir / "directions" / f"direction-{direction_id}.yaml"
        document = _load_yaml(path)
        document = document if isinstance(document, dict) else {}
        primary = document.get("primary_journey")
        primary = primary if isinstance(primary, dict) else {}
        directions.append(
            {
                "id": direction_id,
                "name": document.get("name") or direction_id,
                "archetype": document.get("archetype") or "",
                "thesis": document.get("thesis") or "",
                "primary_journey": {
                    "id": primary.get("id") or "",
                    "steps": list(primary.get("steps") or []),
                },
                "density": document.get("density") or "",
                "patterns": list(document.get("patterns") or []),
                "components": list(document.get("components") or []),
            }
        )
    return directions


def _assertion_counts(entries: Any) -> dict[str, int]:
    if not isinstance(entries, list):
        return {"total": 0, "passed": 0}
    total = len(entries)
    passed = sum(
        1
        for entry in entries
        if isinstance(entry, Mapping) and entry.get("passed") is True
    )
    return {"total": total, "passed": passed}


def _approval_reference_hash(payload: Mapping[str, Any]) -> str:
    return _reference_hash(dict(payload))


def _build_approvals(
    review_evidence: Mapping[str, Any],
    change_evidence: Mapping[str, Any],
    review_ref: str,
    change_ref: str,
) -> list[dict[str, Any]]:
    contract = change_evidence.get("contract_change")
    contract = contract if isinstance(contract, Mapping) else {}
    versions = contract.get("approval_versions")
    versions = versions if isinstance(versions, list) and versions else [1]
    v2_version = contract.get("v2_version")

    approvals: list[dict[str, Any]] = []
    for version in versions:
        if version == 1:
            review_round = review_evidence.get("review_rounds")
            source_commit_sha = review_evidence.get("source_commit_sha")
            evidence_ref = review_ref
            slice_payload = {
                "evidence": review_ref,
                "version": 1,
                "review_round": review_round,
                "source_commit_sha": source_commit_sha,
                "approval_versions": list(
                    review_evidence.get("approval_versions") or []
                ),
            }
        else:
            review_round = contract.get("v2_review_round")
            source_commit_sha = change_evidence.get("source_commit_sha")
            evidence_ref = change_ref
            slice_payload = {
                "evidence": change_ref,
                "version": version,
                "review_round": review_round,
                "source_commit_sha": source_commit_sha,
                "v2_version": v2_version,
                "v2_supersedes": contract.get("v2_supersedes"),
            }
        approvals.append(
            {
                "version": version,
                "review_round": review_round,
                "review_state_hash": _approval_reference_hash(slice_payload),
                "source_commit_sha": source_commit_sha,
            }
        )
    return approvals


def _build_qa(review_evidence: Mapping[str, Any]) -> dict[str, Any]:
    qa = review_evidence.get("qa")
    qa = qa if isinstance(qa, Mapping) else {}
    findings = qa.get("findings") if isinstance(qa.get("findings"), list) else []
    promotions = qa.get("promotions") if isinstance(qa.get("promotions"), list) else []

    promotions_by_finding: dict[Any, Mapping[str, Any]] = {}
    for promotion in promotions:
        if isinstance(promotion, Mapping):
            promotions_by_finding[promotion.get("finding_id")] = promotion

    outcomes: list[dict[str, Any]] = []
    for finding in findings:
        if not isinstance(finding, Mapping):
            continue
        promotion = promotions_by_finding.get(finding.get("id"))
        outcomes.append(
            {
                "finding_id": finding.get("id"),
                "status": finding.get("status"),
                "promoted_feedback_id": (
                    promotion.get("feedback_id") if promotion else None
                ),
                "blocking": promotion.get("blocking") if promotion else None,
            }
        )
    outcomes.sort(key=lambda entry: str(entry["finding_id"]))
    return {
        "findings": list(findings),
        "promotions": list(promotions),
        "outcomes": outcomes,
    }


def _build_assertions(
    root: Path,
    client_dir: Path,
    review_ref: str,
    change_ref: str,
    resume_ref: str,
    review_evidence: Mapping[str, Any],
    change_evidence: Mapping[str, Any],
    resume_evidence: Mapping[str, Any],
) -> dict[str, Any]:
    assertions_ref = _relative_to(root, client_dir / ASSERTIONS_RELATIVE)
    evaluated = evaluate_assertions(root, client_dir)
    evaluated_counts = {
        "total": len(evaluated),
        "passed": sum(1 for result in evaluated if result.passed),
    }
    by_source = {
        review_ref: _assertion_counts(review_evidence.get("assertions")),
        change_ref: _assertion_counts(change_evidence.get("assertions")),
        resume_ref: _assertion_counts(resume_evidence.get("assertions")),
        assertions_ref: evaluated_counts,
    }
    total = sum(entry["total"] for entry in by_source.values())
    passed = sum(entry["passed"] for entry in by_source.values())
    return {
        "total": total,
        "passed": passed,
        "failed": total - passed,
        "by_source": dict(sorted(by_source.items())),
    }


def build_machine_report(root: Path, client_dir: Path) -> dict[str, Any]:
    """Aggregate the deterministic machine report for *client_dir*.

    Raises ``ValueError``/``OSError`` when a canonical artifact or committed
    evidence file is missing or malformed; the validator reports that as an
    error rather than masking it.
    """
    root = Path(root)
    client_dir = Path(client_dir)

    fixture = load_fixture(client_dir / FIXTURE_RELATIVE)
    scenario = load_scenario(client_dir / SCENARIO_RELATIVE)

    review_ref = _relative_to(
        root, client_dir / EVIDENCE_DIR_RELATIVE / REVIEW_EVIDENCE_NAME
    )
    change_ref = _relative_to(
        root, client_dir / EVIDENCE_DIR_RELATIVE / CHANGE_EVIDENCE_NAME
    )
    resume_ref = _relative_to(
        root, client_dir / EVIDENCE_DIR_RELATIVE / RESUME_EVIDENCE_NAME
    )
    review_evidence = load_evidence(client_dir / EVIDENCE_DIR_RELATIVE / REVIEW_EVIDENCE_NAME)
    change_evidence = load_evidence(client_dir / EVIDENCE_DIR_RELATIVE / CHANGE_EVIDENCE_NAME)
    resume_evidence = load_evidence(client_dir / EVIDENCE_DIR_RELATIVE / RESUME_EVIDENCE_NAME)

    state = _load_yaml(client_dir / WORKFLOW_STATE_RELATIVE)
    state = state if isinstance(state, dict) else {}
    skipped = [
        entry.get("stage")
        for entry in state.get("skipped") or []
        if isinstance(entry, Mapping)
    ]

    contracts = load_all_stage_contracts(root)
    validators = {contract.stage: list(contract.validators) for contract in contracts}

    contract_change = change_evidence.get("contract_change")
    contract_change = contract_change if isinstance(contract_change, Mapping) else {}

    # Executed validator outcomes. The Milestone E runtime only advances a stage
    # after its declared validators pass, so a stage that the resume evidence
    # records as completed carries an executed, passing outcome; stages that have
    # not run yet are declared-only.
    completed_by_resume = set(
        (resume_evidence.get("completion") or {}).get("completed_stages") or []
    )
    validator_outcomes = [
        {
            "stage": contract.stage,
            "validators": list(contract.validators),
            "executed": contract.stage in completed_by_resume,
            "status": "passed" if contract.stage in completed_by_resume else "declared_only",
            "source": (
                "resume-evidence" if contract.stage in completed_by_resume else "stage-contract"
            ),
        }
        for contract in contracts
    ]

    workflow = {
        "attempt_ids": list(resume_evidence.get("attempt_ids") or []),
        "current_stage": state.get("current_stage"),
        "completed": list(state.get("completed") or []),
        "skipped": skipped,
        "validators": validators,
        "validator_outcomes": validator_outcomes,
    }

    review = {
        "rounds": contract_change.get("review_rounds"),
        "approval_versions": list(contract_change.get("approval_versions") or []),
    }

    report: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "client_id": fixture.get("client_id"),
        "client_name": _load_client_profile(client_dir)["display_name"],
        "fixture_version": fixture.get("fixture_version"),
        "fixture_identity": fixture_identity(fixture),
        "scenario_ids": scenario_ids(scenario),
        "source_commit_sha": review_evidence.get("source_commit_sha"),
        "client_profile": _load_client_profile(client_dir),
        "directions": _load_directions(client_dir),
        "selected_experience": {
            "selected_direction": review_evidence.get("selected_direction"),
            "screen_overrides": dict(review_evidence.get("screen_overrides") or {}),
            "section_overrides": dict(review_evidence.get("section_overrides") or {}),
            "direction_identities": dict(scenario.get("direction_identities") or {}),
        },
        "workflow": workflow,
        "evidence_refs": sorted([review_ref, change_ref, resume_ref]),
        "review": review,
        "approvals": _build_approvals(
            review_evidence, change_evidence, review_ref, change_ref
        ),
        "feedback": {
            "blocking": list(
                (review_evidence.get("feedback") or {}).get("blocking") or []
            ),
            "non_blocking": list(
                (review_evidence.get("feedback") or {}).get("non_blocking") or []
            ),
            "visual_annotations": list(
                (review_evidence.get("feedback") or {}).get("visual_annotations") or []
            ),
        },
        "refinement_batches": list(review_evidence.get("refinement_batches") or []),
        "qa": _build_qa(review_evidence),
        "change_boundaries": {
            "contract_impacting": dict(contract_change),
            "implementation_only": dict(
                change_evidence.get("implementation_only") or {}
            ),
        },
        "resume": {
            "stage": resume_evidence.get("stage"),
            "attempt_ids": list(resume_evidence.get("attempt_ids") or []),
            "checkpoints": list(resume_evidence.get("checkpoints") or []),
            "interruption": dict(resume_evidence.get("interruption") or {}),
            "completion": dict(resume_evidence.get("completion") or {}),
            "retry": dict(resume_evidence.get("retry") or {}),
            "no_chat_memory_required": resume_evidence.get(
                "no_chat_memory_required"
            ),
        },
        "assertions": _build_assertions(
            root,
            client_dir,
            review_ref,
            change_ref,
            resume_ref,
            review_evidence,
            change_evidence,
            resume_evidence,
        ),
        "known_limitations": list(KNOWN_LIMITATIONS),
    }
    report["report_identity"] = machine_report_identity(report)
    return report


def _bullets(lines: list[str], items: Any, empty: str = "- none") -> None:
    if not items:
        lines.append(empty)
        return
    for item in items:
        lines.append(f"- {item}")


def render_human_report(machine_report: Mapping[str, Any]) -> str:
    """Render the explanatory Markdown report from a machine report."""
    report = machine_report
    profile = report.get("client_profile") or {}
    lines: list[str] = []

    title = report.get("client_name") or report.get("client_id") or "Reference client"
    lines.append(f"# {title} — Milestone F end-to-end reference report")
    lines.append("")
    lines.append(
        "This document is explanatory evidence. It does not replace the machine "
        "assertions in `reference-report.json`; those assertions are "
        "authoritative. It contains no subjective aggregate rating."
    )
    lines.append("")

    lines.append("## Synthetic client profile")
    lines.append("")
    lines.append(f"- Client id: `{report.get('client_id')}`")
    lines.append(f"- Display name: {title}")
    lines.append(f"- Business model: `{profile.get('business_model')}`")
    lines.append(f"- Industry: `{profile.get('industry')}`")
    lines.append(f"- Use cases: {', '.join(profile.get('use_cases') or []) or 'none'}")
    lines.append(f"- Objectives: {', '.join(profile.get('objectives') or []) or 'none'}")
    lines.append(f"- Personas: {', '.join(profile.get('personas') or []) or 'none'}")
    lines.append(f"- Jobs: {', '.join(profile.get('jobs') or []) or 'none'}")
    lines.append(f"- Platforms: {', '.join(profile.get('platforms') or []) or 'none'}")
    lines.append(f"- Fixture version: {report.get('fixture_version')}")
    lines.append(f"- Fixture identity: `{report.get('fixture_identity')}`")
    lines.append(
        "- Provenance: fully synthetic reference data; no client data and no PII."
    )
    lines.append("")

    lines.append("## B2C scope")
    lines.append("")
    lines.append(
        "Consumer shoppers discover, compare, and buy direct. The reference "
        "journey exercises a search-led path (`search -> plp -> pdp -> cart -> "
        "order`) and the governed cart calls to action that represent order "
        "conversion."
    )
    lines.append("")

    lines.append("## B2B scope")
    lines.append("")
    lines.append(
        "Trade buyers and procurement managers order on account. The reference "
        "journey exercises a dashboard-led path (`trade-dashboard -> reorder / "
        "rfq -> cart -> order`) with credit visibility and quoting."
    )
    lines.append("")

    lines.append("## Three directions")
    lines.append("")
    for direction in report.get("directions") or []:
        journey = direction.get("primary_journey") or {}
        steps = " -> ".join(journey.get("steps") or []) or "none"
        lines.append(
            f"### {direction.get('id')} — {direction.get('name')} "
            f"(`{direction.get('archetype')}`)"
        )
        lines.append("")
        lines.append(f"- Thesis: {direction.get('thesis')}")
        lines.append(f"- Primary journey: `{journey.get('id')}` ({steps})")
        lines.append(f"- Density: `{direction.get('density')}`")
        lines.append(
            f"- Patterns: {', '.join(direction.get('patterns') or []) or 'none'}"
        )
        lines.append(
            f"- Components: {', '.join(direction.get('components') or []) or 'none'}"
        )
        lines.append("")

    selected = report.get("selected_experience") or {}
    identities = selected.get("direction_identities") or {}
    lines.append("## Selected and mixed experience")
    lines.append("")
    selected_id = selected.get("selected_direction")
    selected_name = identities.get(selected_id, selected_id)
    lines.append(f"- Selected direction: `{selected_id}` ({selected_name})")
    screen_overrides = selected.get("screen_overrides") or {}
    if screen_overrides:
        for screen, direction in sorted(screen_overrides.items()):
            lines.append(f"- Screen override: `{screen}` -> `{direction}`")
    else:
        lines.append("- Screen override: none")
    section_overrides = selected.get("section_overrides") or {}
    if section_overrides:
        for screen, sections in sorted(section_overrides.items()):
            for section, direction in sorted((sections or {}).items()):
                lines.append(
                    f"- Section override: `{screen}` / `{section}` -> `{direction}`"
                )
    else:
        lines.append("- Section override: none")
    lines.append("")

    feedback = report.get("feedback") or {}
    lines.append("## Blocking and non-blocking feedback")
    lines.append("")
    lines.append("Blocking feedback:")
    for record in feedback.get("blocking") or []:
        lines.append(
            f"- `{record.get('id')}` ({record.get('scope')}) status="
            f"`{record.get('status')}`, blocking={record.get('blocking')}"
        )
    lines.append("")
    lines.append("Non-blocking feedback:")
    for record in feedback.get("non_blocking") or []:
        lines.append(
            f"- `{record.get('id')}` ({record.get('scope')}) status="
            f"`{record.get('status')}`, blocking={record.get('blocking')}"
        )
    lines.append("")

    lines.append("## Visual annotation")
    lines.append("")
    for record in feedback.get("visual_annotations") or []:
        lines.append(
            f"- `{record.get('id')}` on `{record.get('screen')}` / "
            f"`{record.get('section')}` (direction `{record.get('effective_direction')}`), "
            f"screenshot `{record.get('screenshot_ref')}`"
        )
    lines.append("")

    lines.append("## Refinement batch")
    lines.append("")
    for batch in report.get("refinement_batches") or []:
        lines.append(
            f"- `{batch.get('id')}` status=`{batch.get('status')}` "
            f"classification=`{batch.get('classification')}` "
            f"feedback={', '.join(batch.get('feedback_ids') or []) or 'none'}"
        )
    lines.append("")

    approvals = report.get("approvals") or []
    approval_v1 = next(
        (entry for entry in approvals if entry.get("version") == 1), {}
    )
    lines.append("## Approval v1")
    lines.append("")
    lines.append(f"- Version: {approval_v1.get('version')}")
    lines.append(f"- Review round: {approval_v1.get('review_round')}")
    lines.append(f"- Source commit: `{approval_v1.get('source_commit_sha')}`")
    lines.append(
        f"- Review-state reference identity: `{approval_v1.get('review_state_hash')}`"
    )
    lines.append("")

    qa = report.get("qa") or {}
    lines.append("## QA / QAFinding journey")
    lines.append("")
    lines.append(f"- Findings: {len(qa.get('findings') or [])}")
    lines.append(f"- Promotions: {len(qa.get('promotions') or [])}")
    for outcome in qa.get("outcomes") or []:
        lines.append(
            f"- `{outcome.get('finding_id')}` status=`{outcome.get('status')}` "
            f"promoted_feedback=`{outcome.get('promoted_feedback_id')}` "
            f"blocking={outcome.get('blocking')}"
        )
    lines.append("")

    change = report.get("change_boundaries") or {}
    contract_change = change.get("contract_impacting") or {}
    lines.append("## Contract-impacting change")
    lines.append("")
    lines.append(f"- Review rounds: {contract_change.get('review_rounds')}")
    lines.append(
        f"- Approval versions: {contract_change.get('approval_versions')}"
    )
    lines.append(f"- v1 immutable: {contract_change.get('v1_immutable')}")
    lines.append(f"- v2 hash differs: {contract_change.get('v2_hash_differs')}")
    lines.append(
        f"- Third approval refused: {contract_change.get('third_approval_refused')}"
    )
    lines.append("")

    approval_v2 = next(
        (entry for entry in approvals if entry.get("version") == 2), {}
    )
    lines.append("## Approval v2")
    lines.append("")
    lines.append(f"- Version: {approval_v2.get('version')}")
    lines.append(f"- Review round: {approval_v2.get('review_round')}")
    lines.append(f"- Source commit: `{approval_v2.get('source_commit_sha')}`")
    lines.append(
        f"- Review-state reference identity: `{approval_v2.get('review_state_hash')}`"
    )
    lines.append(
        f"- Supersedes: {contract_change.get('v2_supersedes')} "
        "(v1 remains immutable and historically valid)"
    )
    lines.append("")

    implementation = change.get("implementation_only") or {}
    lines.append("## Implementation-only change (no reapproval proof)")
    lines.append("")
    lines.append(
        f"- Classification: `{implementation.get('classification')}`"
    )
    lines.append(f"- Review round: {implementation.get('review_round')}")
    lines.append(
        f"- Approval versions: {implementation.get('approval_versions')} "
        "(no new version was created)"
    )
    lines.append(
        f"- Approved hash unchanged: {implementation.get('approved_hash_unchanged')}"
    )
    lines.append(
        f"- Still eligible for approval: {implementation.get('still_eligible')}"
    )
    lines.append(
        f"- Uncertain changes default to: "
        f"`{implementation.get('default_classification')}`"
    )
    lines.append("")

    resume = report.get("resume") or {}
    workflow = report.get("workflow") or {}
    lines.append("## Interruption and resume proof")
    lines.append("")
    lines.append(f"- Stage: `{resume.get('stage')}`")
    lines.append(f"- Attempt ids: {resume.get('attempt_ids')}")
    lines.append(f"- Interruption: {resume.get('interruption')}")
    lines.append(f"- Resume: same attempt, lease reclaimed and audited")
    lines.append(f"- Completion advanced to: `{(resume.get('completion') or {}).get('advanced_to')}`")
    lines.append(f"- Retry recovery action: `{(resume.get('retry') or {}).get('recovery_action')}`")
    lines.append(
        f"- No chat/session memory required: {resume.get('no_chat_memory_required')}"
    )
    lines.append(f"- Live workflow stage: `{workflow.get('current_stage')}`")
    lines.append(
        f"- Completed stages: {', '.join(workflow.get('completed') or []) or 'none'}"
    )
    lines.append("")

    lines.append("## Known limitations")
    lines.append("")
    for limitation in report.get("known_limitations") or []:
        lines.append(f"- {limitation}")
    lines.append("")

    lines.append("## Evidence references")
    lines.append("")
    for ref in report.get("evidence_refs") or []:
        lines.append(f"- `{ref}`")
    lines.append("")
    assertions = report.get("assertions") or {}
    lines.append(
        f"Assertions: {assertions.get('passed')}/{assertions.get('total')} passed "
        f"({assertions.get('failed')} failed)."
    )
    lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":  # pragma: no cover - manual generation helper
    import argparse

    parser = argparse.ArgumentParser(prog="tooling.reference_client.report")
    parser.add_argument(
        "client_dir", nargs="?", default="client-projects/reference-commerce"
    )
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    target = Path(args.client_dir)
    if not target.is_absolute():
        target = repo_root / target
    machine = build_machine_report(repo_root, target)
    out_dir = target / REPORT_DIR_RELATIVE
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / MACHINE_REPORT_NAME).write_text(
        canonical_report(machine), encoding="utf-8", newline="\n"
    )
    (out_dir / HUMAN_REPORT_NAME).write_text(
        render_human_report(machine), encoding="utf-8", newline="\n"
    )
