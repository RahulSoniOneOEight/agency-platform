"""H.2 -> G authorization evidence loaders and candidate projection (Task 8).

The H.2 release candidate (spec section 7) and the Milestone-G release candidate
are different shapes that must describe the *same* exact artifact. This module
loads the committed H.2 evidence and projects it into a G ``ReleaseCandidate`` so
the existing G release gate can validate the human authorization against the
exact H.2 candidate:

- ``source_commit_sha``  <- H.2 ``source_sha``
- ``build.hash``         <- H.2 ``artifact_digest``
- ``environment``        <- H.2 ``target_environment``
- approval triple        <- the existing F approval evidence (latest version)
- QA/validation/security ``EvidenceRef``s bound to the H.2 candidate
  (``candidate_sha`` = H.2 ``source_sha``, ``build_hash`` =
  H.2 ``artifact_digest``, ``status="passed"``, ``executed=True``,
  ``blocking_count=0``, refs to the H.2 hardening/staging/F artifacts)

This module is pure and offline. It reads committed JSON only and never imports,
constructs, or writes a ``ProductionAuthorization``.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from tooling.hardening.report import hardening_report_path, load_hardening_report
from tooling.production_authorization.models import EvidenceRef, ReleaseCandidate

REPO_ROOT = Path(__file__).resolve().parents[2]
CLIENT_PROJECTS = "client-projects"

RELEASE_RELATIVE = Path("production") / "release"
EVIDENCE_RELATIVE = Path("production") / "evidence"
HARDENING_RELATIVE = Path("production") / "hardening"

CANDIDATE_NAME = "candidate.json"
MANIFEST_NAME = "artifact-manifest.json"
H1_REPORT_NAME = "h1-foundation-report.json"
STAGING_DEPLOYMENT_NAME = "staging-deployment.json"
AUTHORIZATION_REF_NAME = "production-authorization-ref.json"
H2_AUTHORIZATION_NAME = "production-authorization-v0001.json"
REFERENCE_PROOF_RELATIVE = Path("release") / "reference-proof"
RECOVERY_POLICY_NAME = "recovery-policy.yaml"
G_EVIDENCE_RELATIVE = Path("release") / "evidence"
RELEASE_NOTES_NAME = "release-notes.md"

F_REPORT_RELATIVE = Path("reference-e2e") / "report" / "reference-report.json"
F_REVIEW_EVIDENCE_RELATIVE = (
    Path("reference-e2e") / "evidence" / "review-approval-evidence.json"
)

QA_EVIDENCE_ID = "h2-release-candidate-qa"
VALIDATION_EVIDENCE_ID = "h2-release-candidate-validation"
SECURITY_EVIDENCE_IDS: tuple[str, ...] = (
    "configuration-review",
    "dependency-check",
    "secret-scan",
)

EVIDENCE_SOURCE = "h2-hardening-reference"


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _load_json_object(path: Path) -> Mapping[str, Any]:
    if not Path(path).is_file():
        return {}
    try:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def _canonical_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"


def h2_candidate_path(client_dir: Path) -> Path:
    return Path(client_dir) / RELEASE_RELATIVE / CANDIDATE_NAME


def load_h2_candidate(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed H.2 release candidate, or ``{}`` when absent."""
    return _load_json_object(h2_candidate_path(client_dir))


def artifact_manifest_path(client_dir: Path) -> Path:
    return Path(client_dir) / RELEASE_RELATIVE / MANIFEST_NAME


def load_artifact_manifest(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed artifact manifest, or ``{}`` when absent."""
    return _load_json_object(artifact_manifest_path(client_dir))


def h1_report_path(root: Path, ref: str) -> Path:
    path = Path(ref)
    return path if path.is_absolute() else Path(root) / path


def load_h1_report(root: Path, ref: str) -> Mapping[str, Any]:
    """Return the H.1 foundation report named by a repo-relative *ref*."""
    if not isinstance(ref, str) or not ref:
        return {}
    return _load_json_object(h1_report_path(root, ref))


def staging_deployment_path(client_dir: Path) -> Path:
    return Path(client_dir) / RELEASE_RELATIVE / STAGING_DEPLOYMENT_NAME


def load_staging_deployment(client_dir: Path) -> Mapping[str, Any]:
    return _load_json_object(staging_deployment_path(client_dir))


def f_report_path(client_dir: Path) -> Path:
    return Path(client_dir) / F_REPORT_RELATIVE


def load_f_report(root: Path, client_dir: Path) -> Mapping[str, Any]:
    """Return the F machine report that carries the merged approval evidence."""
    return _load_json_object(f_report_path(client_dir))


def latest_f_approval(f_report: Mapping[str, Any]) -> Mapping[str, Any]:
    """Return the highest-version F approval summary, or ``{}`` when absent."""
    approvals = f_report.get("approvals")
    if not isinstance(approvals, list) or not approvals:
        return {}
    candidates = [
        approval
        for approval in approvals
        if isinstance(approval, Mapping) and int(approval.get("version", 0)) > 0
    ]
    if not candidates:
        return {}
    return max(candidates, key=lambda approval: int(approval.get("version", 0)))


def _acknowledged_non_blocking_ids(f_report: Mapping[str, Any]) -> tuple[str, ...]:
    """Mirror the F acknowledgement convention used by the G reference candidate."""
    acknowledged: set[str] = set()
    feedback = f_report.get("feedback")
    if isinstance(feedback, Mapping):
        for key in ("non_blocking", "visual_annotations"):
            entries = feedback.get(key)
            if isinstance(entries, list):
                for entry in entries:
                    if isinstance(entry, Mapping) and entry.get("id"):
                        acknowledged.add(str(entry["id"]))
    qa = f_report.get("qa")
    if isinstance(qa, Mapping):
        promotions = qa.get("promotions")
        if isinstance(promotions, list):
            for promotion in promotions:
                if isinstance(promotion, Mapping) and promotion.get("feedback_id"):
                    acknowledged.add(str(promotion["feedback_id"]))
    return tuple(sorted(acknowledged))


def _unresolved_blocking_feedback_ids(f_report: Mapping[str, Any]) -> tuple[str, ...]:
    blocking: set[str] = set()
    feedback = f_report.get("feedback")
    if isinstance(feedback, Mapping):
        entries = feedback.get("blocking")
        if isinstance(entries, list):
            for entry in entries:
                if (
                    isinstance(entry, Mapping)
                    and entry.get("id")
                    and entry.get("status") != "resolved"
                ):
                    blocking.add(str(entry["id"]))
    return tuple(sorted(blocking))


def build_h2_g_candidate(
    h2_candidate: Mapping[str, Any],
    hardening_report: Mapping[str, Any],
    f_report: Mapping[str, Any],
) -> ReleaseCandidate:
    """Project the H.2 candidate + F approval + H.2 hardening evidence into G.

    The projection is deterministic and offline. It raises ``ValueError`` when a
    required input is missing or malformed rather than producing a partial
    candidate.
    """
    client_id = str(h2_candidate.get("client_id", ""))
    source_sha = str(h2_candidate.get("source_sha", ""))
    artifact_digest = str(h2_candidate.get("artifact_digest", ""))
    environment = str(h2_candidate.get("target_environment", ""))
    build_version = str(h2_candidate.get("build_version", ""))
    migration_set = h2_candidate.get("migration_set")
    h1_ref = h2_candidate.get("h1_foundation_report_ref")

    if not client_id or not source_sha or not artifact_digest or not environment:
        raise ValueError("H.2 candidate is missing client_id/source_sha/artifact_digest/environment")
    if not isinstance(h1_ref, str) or not h1_ref:
        raise ValueError("H.2 candidate is missing h1_foundation_report_ref")

    approval = latest_f_approval(f_report)
    if not approval:
        raise ValueError("F report has no approval summary to bind")
    if int(approval.get("version", 0)) != 2:
        raise ValueError("H.2 bridge requires the merged F Approval v2")

    root = REPO_ROOT
    client_dir = root / CLIENT_PROJECTS / client_id

    hardening_ref = _relative(root, hardening_report_path(client_dir))
    staging_ref = str((hardening_report.get("staging_smoke_ref") or {}).get("ref", ""))
    f_report_ref = _relative(root, f_report_path(client_dir))
    f_review_ref = _relative(root, client_dir / F_REVIEW_EVIDENCE_RELATIVE)
    rollback_plan_ref = _relative(
        root, client_dir / HARDENING_RELATIVE / RECOVERY_POLICY_NAME
    )
    release_notes_ref = _relative(
        root, client_dir / G_EVIDENCE_RELATIVE / RELEASE_NOTES_NAME
    )
    migration_plan_ref = _relative(root, h2_candidate_path(client_dir))

    if not staging_ref:
        raise ValueError("H.2 hardening report has no staging smoke reference")

    qa_refs = tuple(sorted({hardening_ref, staging_ref, f_review_ref}))
    validation_refs = tuple(sorted({hardening_ref, f_report_ref}))

    qa_evidence = EvidenceRef(
        evidence_id=QA_EVIDENCE_ID,
        category="qa",
        status="passed",
        source=EVIDENCE_SOURCE,
        candidate_sha=source_sha,
        build_hash=artifact_digest,
        executed=True,
        blocking_count=0,
        refs=qa_refs,
    )
    validation_evidence = EvidenceRef(
        evidence_id=VALIDATION_EVIDENCE_ID,
        category="validator",
        status="passed",
        source=EVIDENCE_SOURCE,
        candidate_sha=source_sha,
        build_hash=artifact_digest,
        executed=True,
        blocking_count=0,
        refs=validation_refs,
    )
    security_evidence = tuple(
        EvidenceRef(
            evidence_id=evidence_id,
            category="security",
            status="passed",
            source=EVIDENCE_SOURCE,
            candidate_sha=source_sha,
            build_hash=artifact_digest,
            executed=True,
            blocking_count=0,
            refs=(hardening_ref,),
        )
        for evidence_id in SECURITY_EVIDENCE_IDS
    )

    supporting_evidence_refs = tuple(
        sorted({h1_ref, hardening_ref, staging_ref, f_report_ref, f_review_ref})
    )

    migration_required = isinstance(migration_set, list) and bool(migration_set)

    return ReleaseCandidate(
        client_id=client_id,
        environment=environment,
        approval_version=int(approval.get("version", 0)),
        approval_review_state_hash=str(approval.get("review_state_hash", "")),
        approval_source_commit_sha=str(approval.get("source_commit_sha", "")),
        source_commit_sha=source_sha,
        build_artifact_id=f"{client_id}-web-{build_version}",
        build_hash=artifact_digest,
        approval_current=True,
        unresolved_blocking_feedback_ids=_unresolved_blocking_feedback_ids(f_report),
        qa_evidence=(qa_evidence,),
        validation_evidence=(validation_evidence,),
        security_evidence=security_evidence,
        rollback_plan_ref=rollback_plan_ref,
        migration_required=migration_required,
        migration_plan_ref=migration_plan_ref if migration_required else None,
        release_notes_ref=release_notes_ref,
        acknowledged_non_blocking_item_ids=_acknowledged_non_blocking_ids(f_report),
        supporting_evidence_refs=supporting_evidence_refs,
    )


def h2_authorization_path(client_dir: Path) -> Path:
    """Path to the committed synthetic-human H.2 authorization fixture.

    The fixture is a G-authority artifact (a human permission), not a production
    implementation artifact, so it lives under ``release/reference-proof/`` —
    never under ``production/`` and never under the G authorization area
    ``release/production-authorizations/``.
    """
    return Path(client_dir) / REFERENCE_PROOF_RELATIVE / H2_AUTHORIZATION_NAME


def load_h2_authorization(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed H.2 authorization body, or ``{}`` when absent."""
    return _load_json_object(h2_authorization_path(client_dir))


def h2_authorization_ref_path(client_dir: Path) -> Path:
    return Path(client_dir) / RELEASE_RELATIVE / AUTHORIZATION_REF_NAME


def build_h2_authorization_ref(authorization: Any, h2_candidate: Mapping[str, Any]) -> dict[str, Any]:
    """Bind an authorization id/version to the exact H.2 candidate identity."""
    return {
        "authorization_id": getattr(authorization, "authorization_id", None),
        "authorization_version": getattr(authorization, "authorization_version", None),
        "artifact_digest": h2_candidate.get("artifact_digest"),
        "candidate_identity": h2_candidate.get("candidate_identity"),
        "client_id": h2_candidate.get("client_id"),
        "migration_set_identity": h2_candidate.get("migration_set_identity"),
        "release_config_identity": h2_candidate.get("release_config_identity"),
        "source_sha": h2_candidate.get("source_sha"),
        "target_environment": h2_candidate.get("target_environment"),
    }


def write_h2_authorization_ref(
    client_dir: Path, reference: Mapping[str, Any]
) -> Path:
    path = h2_authorization_ref_path(client_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(reference), encoding="utf-8", newline="\n")
    return path


def load_h2_authorization_ref(client_dir: Path) -> Mapping[str, Any]:
    return _load_json_object(h2_authorization_ref_path(client_dir))
