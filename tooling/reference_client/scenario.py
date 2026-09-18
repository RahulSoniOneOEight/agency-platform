"""Deterministic machine-readable scenario contract for the reference client.

The scenario declares the fixed runtime direction ids, the named experience
identities (RF1), and the ordered cycle scenarios. It is evidence only: it never
becomes a review, approval, QA, refinement, or workflow authority.
"""

from __future__ import annotations

import json
import shutil
from collections.abc import Mapping
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

from tooling.workflow.audit import load_audit_records
from tooling.workflow.execution import iso_timestamp, prior_manifests
from tooling.workflow.manifests import (
    ValidatorEvidence,
    load_manifest,
    manifest_path,
)
from tooling.workflow.runner import (
    RecoveryRequired,
    checkpoint_stage,
    complete_stage,
    inspect_client,
    resume_stage,
    start_stage,
)
from tooling.workflow.state import load_state

SUPPORTED_SCENARIO_VERSIONS = frozenset({1})
REQUIRED_FIXTURE_VERSION = 1

SCENARIO_RELATIVE = Path("reference-e2e") / "scenario.yaml"
SCHEMA_RELATIVE = (
    Path("client-projects") / "schema" / "reference-client-scenario.schema.json"
)

REQUIRED_SCENARIO_IDS: tuple[str, ...] = (
    "normal-happy-path",
    "contract-change-reapproval",
    "implementation-only-change",
    "resume-after-interruption",
)

REQUIRED_DIRECTION_IDENTITIES: dict[str, str] = {
    "a": "efficient-commerce",
    "b": "premium-discovery",
    "c": "trade-first",
}


def load_scenario(path: Path) -> dict[str, Any]:
    """Load and shape-check a scenario document.

    Raises ``ValueError`` when the document is not a mapping or does not declare
    ``client_id`` / ``version``.
    """
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"scenario must be a mapping: {path}")
    if not isinstance(data.get("client_id"), str) or not data["client_id"]:
        raise ValueError(f"scenario requires a non-empty client_id: {path}")
    if "version" not in data:
        raise ValueError(f"scenario requires version: {path}")
    return data


def scenario_ids(scenario: dict[str, Any]) -> list[str]:
    """Return the ordered scenario ids declared by *scenario*."""
    scenarios = scenario.get("scenarios")
    if not isinstance(scenarios, list):
        return []
    return [
        entry["id"]
        for entry in scenarios
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    ]


def _schema_errors(root: Path, scenario: dict[str, Any]) -> list[str]:
    schema_path = root / SCHEMA_RELATIVE
    if not schema_path.exists():
        return [f"{schema_path}: missing scenario schema"]
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(scenario), key=lambda error: list(error.path))
    return [
        f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
        for error in errors
    ]


def validate_scenario(root: Path, client_dir: Path) -> list[str]:
    """Return deterministic, stable-sorted scenario errors (``[]`` == valid)."""
    path = client_dir / SCENARIO_RELATIVE
    if not path.exists():
        return [f"{path}: missing scenario"]
    try:
        scenario = load_scenario(path)
    except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
        return [f"{path}: {exc}"]

    errors: list[str] = []

    version = scenario.get("version")
    if version not in SUPPORTED_SCENARIO_VERSIONS:
        errors.append(f"{path}: unsupported scenario version {version!r}")

    client_id = scenario.get("client_id")
    if client_id != client_dir.name:
        errors.append(
            f"{path}: client_id {client_id!r} does not match client directory "
            f"{client_dir.name!r}"
        )

    fixture_version = scenario.get("fixture_version")
    if fixture_version != REQUIRED_FIXTURE_VERSION:
        errors.append(
            f"{path}: fixture_version must be {REQUIRED_FIXTURE_VERSION}, "
            f"got {fixture_version!r}"
        )

    identities = scenario.get("direction_identities")
    if identities != REQUIRED_DIRECTION_IDENTITIES:
        errors.append(
            f"{path}: direction_identities must be "
            f"{REQUIRED_DIRECTION_IDENTITIES!r}, got {identities!r}"
        )

    ids = scenario_ids(scenario)
    if ids != list(REQUIRED_SCENARIO_IDS):
        errors.append(
            f"{path}: scenario ids must be {list(REQUIRED_SCENARIO_IDS)!r}, got {ids!r}"
        )

    errors.extend(f"{path}: {error}" for error in _schema_errors(root, scenario))

    return sorted(set(errors))


# --- resume-after-interruption scenario -------------------------------------
#
# This scenario drives the *existing* Milestone E workflow runtime only. It adds
# no workflow-state authority, no lease/checkpoint/manifest mechanism, and never
# writes to the committed reference client: ``build_reference_client_workspace``
# copies the committed client into a caller-supplied temp root (RF4/RF9).
#
# Runtime note (important): the Milestone E runner refuses a *foreign* actor
# resuming an in-progress attempt with ``RecoveryRequired`` even when the lease
# has expired (``runner._resume_existing``); the audited reclaim path resumes the
# attempt for its *owner* reconnecting after expiry, which is exactly the
# "fresh process, same workflow session" interruption this scenario proves. A
# different owner taking over an in-progress attempt is deliberately not a
# resume in the E runtime, so the scenario asserts that refusal as a boundary.

_REPO_ROOT = Path(__file__).resolve().parents[2]
_REFERENCE_CLIENT_RELATIVE = Path("client-projects") / "reference-commerce"

RESUME_SCENARIO_ID = "resume-after-interruption"
RESUME_STAGE = "visual-qa"
RESUME_CHECKPOINT = "capture-complete"
RESUME_VALIDATOR = "visual-qa-contract"
RESUME_SOURCE_COMMIT_SHA = "89abcdef0123456789abcdef0123456789abcdef"
RESUME_ACTOR = "opencode:reference-session-a"
RESUME_FOREIGN_ACTOR = "opencode:reference-session-b"
RESUME_BASE_TIME = datetime(2026, 9, 18, 12, 0, tzinfo=timezone.utc)
RESUME_LEASE_TTL_SECONDS = 1800
RESUME_INTERRUPTION_TIME = RESUME_BASE_TIME + timedelta(minutes=31)

RESUME_EVIDENCE_REQUIRED_KEYS: tuple[str, ...] = (
    "client_id",
    "fixture_version",
    "scenario_id",
    "source_commit_sha",
    "stage",
    "attempt_ids",
    "checkpoints",
    "interruption",
    "resume",
    "completion",
    "retry",
    "no_chat_memory_required",
    "assertions",
)

_FORBIDDEN_SCORE_KEYS: frozenset[str] = frozenset(
    {"overall_score", "score", "quality_score"}
)

_STATE_FILENAME = "workflow-state.yaml"


class _AssertionRecorder:
    """Collect deterministic ``{id, passed}`` outcomes in insertion order."""

    def __init__(self) -> None:
        self._results: list[dict[str, Any]] = []

    def check(self, assertion_id: str, condition: Any) -> None:
        self._results.append(
            {"id": assertion_id, "passed": bool(condition)}
        )

    def results(self) -> list[dict[str, Any]]:
        return [dict(entry) for entry in self._results]


def canonical_resume_evidence(evidence: Mapping[str, Any]) -> str:
    """Return the canonical byte form of a resume-evidence document."""
    return json.dumps(evidence, indent=2, sort_keys=True, allow_nan=False) + "\n"


def build_reference_client_workspace(root: Path) -> Path:
    """Copy the committed reference client + contracts into *root* (a temp root).

    Deterministic and side-effect free with respect to the repository: the only
    writes are inside *root*. Returns the temp client directory. The caller owns
    cleanup of *root*.
    """
    root = Path(root)
    (root / "client-projects").mkdir(parents=True, exist_ok=True)
    shutil.copytree(
        _REPO_ROOT / "workflows" / "contracts", root / "workflows" / "contracts"
    )
    shutil.copytree(
        _REPO_ROOT / "client-projects" / "schema" / "input",
        root / "client-projects" / "schema" / "input",
    )
    client_dir = root / _REFERENCE_CLIENT_RELATIVE
    shutil.copytree(_REPO_ROOT / _REFERENCE_CLIENT_RELATIVE, client_dir)
    return client_dir


def _recovery_records(client_dir: Path) -> list[Any]:
    records = load_audit_records(Path(client_dir) / "workflow" / "audit.jsonl")
    return [record for record in records if record.kind == "recovery"]


def run_resume_scenario(root: Path) -> dict[str, Any]:
    """Drive the controlled interruption/resume on a temp workspace.

    *root* must be a fresh, caller-owned temp directory. Returns the
    resume-evidence document. The scenario exercises only
    ``tooling.workflow.runner`` plus the Milestone E domain, uses injected
    clocks, and never touches the committed reference client.
    """
    root = Path(root)
    client_dir = build_reference_client_workspace(root)
    checks = _AssertionRecorder()

    initial = inspect_client(root, client_dir, now=RESUME_BASE_TIME)
    checks.check("inspect.current_stage_visual_qa", initial.current_stage == RESUME_STAGE)
    checks.check("inspect.recovery_none", initial.recovery_action == "none")
    checks.check(
        "inspect.next_stage_ready",
        initial.next_stage == RESUME_STAGE and initial.next_status == "ready",
    )

    started = start_stage(
        root,
        client_dir,
        actor=RESUME_ACTOR,
        source_commit_sha=RESUME_SOURCE_COMMIT_SHA,
        now=RESUME_BASE_TIME,
        ttl_seconds=RESUME_LEASE_TTL_SECONDS,
    )
    primary_run_id = started.manifest.run_id
    primary_manifest = manifest_path(
        client_dir, primary_run_id, started.manifest.attempt
    )
    checks.check(
        "start.attempt_is_one",
        started.status.attempt == 1 and started.manifest.attempt == 1,
    )
    checks.check("start.manifest_created", primary_manifest.is_file())
    checks.check("start.lease_held", started.status.lease_owner == RESUME_ACTOR)
    checks.check("start.stage_unchanged", started.status.current_stage == RESUME_STAGE)
    checks.check("start.lease_not_expired", started.status.lease_expired is False)

    checkpointed = checkpoint_stage(
        root,
        client_dir,
        run_id=primary_run_id,
        checkpoint=RESUME_CHECKPOINT,
        actor=RESUME_ACTOR,
        at=RESUME_BASE_TIME,
    )
    checks.check(
        "checkpoint.last_checkpoint_set",
        checkpointed.status.last_checkpoint == RESUME_CHECKPOINT,
    )
    checks.check(
        "checkpoint.recorded_in_manifest",
        [record.name for record in checkpointed.manifest.checkpoints]
        == [RESUME_CHECKPOINT],
    )
    checks.check(
        "checkpoint.stage_unchanged",
        checkpointed.status.current_stage == RESUME_STAGE,
    )
    primary_bytes = primary_manifest.read_bytes()

    # Controlled interruption: discard every in-memory object and re-read the
    # canonical state from disk; the lease lapses when the clock advances.
    del started, checkpointed
    reloaded = load_state(client_dir / _STATE_FILENAME)
    checks.check("interruption.state_from_disk", reloaded["current_stage"] == RESUME_STAGE)
    checks.check(
        "interruption.lease_present_on_disk", reloaded["active_lease"] is not None
    )

    fresh = inspect_client(root, client_dir, now=RESUME_INTERRUPTION_TIME)
    checks.check("interruption.lease_expired", fresh.lease_expired is True)
    checks.check("interruption.recovery_resume", fresh.recovery_action == "resume")
    checks.check("interruption.attempt_preserved", fresh.attempt == 1)
    checks.check(
        "interruption.checkpoint_survives", fresh.last_checkpoint == RESUME_CHECKPOINT
    )
    checks.check(
        "interruption.stage_not_advanced", fresh.current_stage == RESUME_STAGE
    )

    audit_before = _recovery_records(client_dir)

    # Boundary: a *foreign* actor may not take over an in-progress attempt; the
    # E runtime refuses it deterministically (and mutates nothing).
    foreign_refused = False
    try:
        resume_stage(
            root,
            client_dir,
            actor=RESUME_FOREIGN_ACTOR,
            source_commit_sha=RESUME_SOURCE_COMMIT_SHA,
            now=RESUME_INTERRUPTION_TIME,
        )
    except RecoveryRequired:
        foreign_refused = True
    checks.check("interruption.foreign_actor_refused", foreign_refused)

    resumed = resume_stage(
        root,
        client_dir,
        actor=RESUME_ACTOR,
        source_commit_sha=RESUME_SOURCE_COMMIT_SHA,
        now=RESUME_INTERRUPTION_TIME,
        ttl_seconds=RESUME_LEASE_TTL_SECONDS,
    )
    audit_after = _recovery_records(client_dir)
    same_attempt = (
        resumed.manifest.run_id == primary_run_id and resumed.manifest.attempt == 1
    )
    lease_reclaimed = len(audit_after) == len(audit_before) + 1
    manifest_count = len(prior_manifests(client_dir, RESUME_STAGE))
    checks.check("resume.same_attempt", same_attempt)
    checks.check("resume.stage_unchanged", resumed.status.current_stage == RESUME_STAGE)
    checks.check("resume.lease_reclaimed_audited", lease_reclaimed)
    checks.check("resume.no_duplicate_manifest", manifest_count == 1)
    checks.check(
        "resume.manifest_not_rewritten",
        primary_manifest.read_bytes() == primary_bytes,
    )
    checks.check("resume.lease_owner", resumed.status.lease_owner == RESUME_ACTOR)

    completed = complete_stage(
        root,
        client_dir,
        run_id=primary_run_id,
        actor=RESUME_ACTOR,
        validator_results=(
            ValidatorEvidence(
                name=RESUME_VALIDATOR,
                status="passed",
                at=iso_timestamp(RESUME_INTERRUPTION_TIME),
            ),
        ),
        at=RESUME_INTERRUPTION_TIME,
    )
    final_state = load_state(client_dir / _STATE_FILENAME)
    completed_manifests = [
        manifest
        for manifest in prior_manifests(client_dir, RESUME_STAGE)
        if manifest.status == "completed"
    ]
    checks.check(
        "completion.advanced_to_client_review",
        completed.status.current_stage == "client-review",
    )
    checks.check(
        "completion.visual_qa_completed",
        "visual-qa" in completed.status.completed,
    )
    checks.check(
        "completion.last_transition_from_visual_qa",
        (final_state.get("last_transition") or {}).get("from") == RESUME_STAGE,
    )
    checks.check(
        "completion.manifest_frozen", completed.manifest.status == "completed"
    )
    checks.check("completion.lease_released", completed.status.lease_owner is None)
    checks.check("final.exactly_one_completed_manifest", len(completed_manifests) == 1)
    checks.check(
        "final.no_duplicate_manifest",
        len(prior_manifests(client_dir, RESUME_STAGE)) == 1,
    )
    disk_state = load_state(client_dir / _STATE_FILENAME)
    checks.check(
        "final.state_rederived_from_disk",
        disk_state["current_stage"] == "client-review"
        and "visual-qa" in disk_state["completed"],
    )

    # Retry path: a second temp workspace interrupted *before* any checkpoint.
    retry_root = root / "retry-workspace"
    retry_client = build_reference_client_workspace(retry_root)
    retry_started = start_stage(
        retry_root,
        retry_client,
        actor=RESUME_ACTOR,
        source_commit_sha=RESUME_SOURCE_COMMIT_SHA,
        now=RESUME_BASE_TIME,
        ttl_seconds=RESUME_LEASE_TTL_SECONDS,
    )
    retry_manifest = manifest_path(
        retry_client, retry_started.manifest.run_id, retry_started.manifest.attempt
    )
    retry_bytes = retry_manifest.read_bytes()
    retry_inspect = inspect_client(retry_root, retry_client, now=RESUME_INTERRUPTION_TIME)
    checks.check("retry.recovery_action", retry_inspect.recovery_action == "retry")
    retry_resumed = resume_stage(
        retry_root,
        retry_client,
        actor=RESUME_ACTOR,
        source_commit_sha=RESUME_SOURCE_COMMIT_SHA,
        now=RESUME_INTERRUPTION_TIME,
        ttl_seconds=RESUME_LEASE_TTL_SECONDS,
    )
    retry_unchanged = retry_manifest.read_bytes() == retry_bytes
    checks.check("retry.new_attempt", retry_resumed.manifest.attempt == 2)
    checks.check(
        "retry.new_run",
        retry_resumed.manifest.run_id != retry_started.manifest.run_id,
    )
    checks.check("retry.prior_manifest_unchanged", retry_unchanged)
    checks.check(
        "retry.prior_manifest_in_progress",
        load_manifest(retry_manifest).status == "in_progress",
    )

    return {
        "client_id": client_dir.name,
        "fixture_version": REQUIRED_FIXTURE_VERSION,
        "scenario_id": RESUME_SCENARIO_ID,
        "source_commit_sha": RESUME_SOURCE_COMMIT_SHA,
        "stage": RESUME_STAGE,
        "attempt_ids": [
            {"stage": RESUME_STAGE, "run_id": primary_run_id, "attempt": 1},
            {
                "stage": RESUME_STAGE,
                "run_id": retry_resumed.manifest.run_id,
                "attempt": retry_resumed.manifest.attempt,
            },
        ],
        "checkpoints": [
            {"name": RESUME_CHECKPOINT, "at": iso_timestamp(RESUME_BASE_TIME)}
        ],
        "interruption": {
            "lease_expired": fresh.lease_expired,
            "recovery_action": fresh.recovery_action,
        },
        "resume": {
            "recovery_action": fresh.recovery_action,
            "same_attempt": same_attempt,
            "lease_reclaimed": lease_reclaimed,
            "audit_records": len(audit_after),
            "manifest_count_for_stage": manifest_count,
        },
        "completion": {
            "advanced_to": completed.status.current_stage,
            "completed_stages": list(completed.status.completed),
            "last_transition_from": (final_state.get("last_transition") or {}).get(
                "from"
            ),
            "lease_released": completed.status.lease_owner is None,
        },
        "retry": {
            "recovery_action": retry_inspect.recovery_action,
            "attempt": retry_resumed.manifest.attempt,
            "prior_manifest_unchanged": retry_unchanged,
        },
        "no_chat_memory_required": True,
        "assertions": checks.results(),
    }


def write_resume_evidence(
    root: Path, client_dir: Path, path: Path
) -> dict[str, Any]:
    """Run the resume scenario in *root* and write canonical evidence to *path*.

    *root* must be a fresh temp directory (the scenario is not idempotent against
    an already-mutated workspace). *client_dir* is validated to be the workspace
    client path; the evidence is derived solely by ``run_resume_scenario``.
    """
    root = Path(root)
    evidence = run_resume_scenario(root)
    built = (root / _REFERENCE_CLIENT_RELATIVE).resolve()
    if Path(client_dir).resolve() != built:
        raise ValueError(
            f"client_dir {client_dir} does not match the built workspace client "
            f"{built}"
        )
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Force LF so the committed bytes are identical on every platform.
    destination.write_text(
        canonical_resume_evidence(evidence), encoding="utf-8", newline="\n"
    )
    return evidence


def _forbidden_key_paths(
    value: Any, forbidden: frozenset[str], prefix: str = ""
) -> list[str]:
    """Return dotted/indexed paths of every forbidden key anywhere in *value*."""
    paths: list[str] = []
    if isinstance(value, Mapping):
        for key, item in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            if key in forbidden:
                paths.append(path)
            paths.extend(_forbidden_key_paths(item, forbidden, path))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            paths.extend(
                _forbidden_key_paths(item, forbidden, f"{prefix}[{index}]")
            )
    return paths


def validate_resume_evidence(evidence: Any) -> list[str]:
    """Return deterministic, stable-sorted resume-evidence errors (``[]`` == valid).

    Evidence only (RF6): it proves the interruption/resume invariants and must
    never collapse the scenario into a subjective score.
    """
    if not isinstance(evidence, Mapping):
        return ["resume evidence must be a mapping"]

    errors: list[str] = []

    for key in RESUME_EVIDENCE_REQUIRED_KEYS:
        if key not in evidence:
            errors.append(f"missing required key: {key}")

    if evidence.get("scenario_id") != RESUME_SCENARIO_ID:
        errors.append(
            f"scenario_id must be {RESUME_SCENARIO_ID!r}, "
            f"got {evidence.get('scenario_id')!r}"
        )
    if evidence.get("stage") != RESUME_STAGE:
        errors.append(
            f"stage must be {RESUME_STAGE!r}, got {evidence.get('stage')!r}"
        )

    assertions = evidence.get("assertions")
    if not isinstance(assertions, list) or not assertions:
        errors.append("assertions must be a non-empty list")
    else:
        for index, entry in enumerate(assertions):
            if not isinstance(entry, Mapping) or entry.get("passed") is not True:
                errors.append(
                    f"assertions[{index}]: every assertion must record passed true"
                )

    if evidence.get("no_chat_memory_required") is not True:
        errors.append("no_chat_memory_required must be true")

    resume = evidence.get("resume")
    if not isinstance(resume, Mapping):
        errors.append("resume must be a mapping")
    elif resume.get("same_attempt") is not True:
        errors.append("resume.same_attempt must be true")

    completion = evidence.get("completion")
    if not isinstance(completion, Mapping):
        errors.append("completion must be a mapping")
    elif completion.get("advanced_to") != "client-review":
        errors.append("completion.advanced_to must be 'client-review'")

    retry = evidence.get("retry")
    if not isinstance(retry, Mapping):
        errors.append("retry must be a mapping")
    else:
        if retry.get("attempt") != 2:
            errors.append("retry.attempt must be 2")
        if retry.get("prior_manifest_unchanged") is not True:
            errors.append("retry.prior_manifest_unchanged must be true")

    for path in _forbidden_key_paths(evidence, _FORBIDDEN_SCORE_KEYS):
        errors.append(
            f"resume evidence must not contain a subjective score key: {path}"
        )

    return sorted(set(errors))
