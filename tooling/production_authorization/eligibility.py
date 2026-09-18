from __future__ import annotations

from dataclasses import dataclass

from .models import EvidenceRef, ReleaseCandidate


@dataclass(frozen=True, order=True, slots=True)
class EligibilityReason:
    code: str
    message: str
    evidence_refs: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class ProductionEligibility:
    eligible: bool
    reasons: tuple[EligibilityReason, ...]


def _bound(evidence: EvidenceRef, candidate: ReleaseCandidate) -> bool:
    if evidence.candidate_sha != candidate.source_commit_sha:
        return False
    if evidence.build_hash != candidate.build_hash:
        return False
    return True


def evaluate_eligibility(candidate: ReleaseCandidate) -> ProductionEligibility:
    reasons: list[EligibilityReason] = []

    def add(code: str, message: str, *refs: str) -> None:
        reasons.append(EligibilityReason(code, message, tuple(sorted(refs))))

    if not candidate.approval_current:
        add("approval_not_current", "current required ApprovalSnapshot identity is not confirmed")
    if candidate.unresolved_blocking_feedback_ids:
        add(
            "blocking_review_feedback",
            "unresolved blocking review feedback remains",
            *candidate.unresolved_blocking_feedback_ids,
        )

    if not candidate.qa_evidence:
        add("qa_evidence_missing", "required QA evidence is missing")
    for item in candidate.qa_evidence:
        if item.status != "passed" or not item.executed:
            add("qa_evidence_failed", f"QA evidence {item.evidence_id} did not pass", item.evidence_id)
        if item.blocking_count:
            add("blocking_qa_findings", f"QA evidence {item.evidence_id} has blocking findings", item.evidence_id)
        if not _bound(item, candidate):
            add("qa_evidence_stale", f"QA evidence {item.evidence_id} does not match candidate", item.evidence_id)

    if not candidate.validation_evidence:
        add("validation_evidence_missing", "required validator evidence is missing")
    for item in candidate.validation_evidence:
        if item.status != "passed" or not item.executed:
            add("validator_failed", f"validator evidence {item.evidence_id} did not pass", item.evidence_id)
        if not _bound(item, candidate):
            add("validator_evidence_stale", f"validator evidence {item.evidence_id} does not match candidate", item.evidence_id)

    required_security = {"dependency-check", "secret-scan", "configuration-review"}
    present_security = {item.evidence_id for item in candidate.security_evidence}
    for missing in sorted(required_security - present_security):
        add("security_evidence_missing", f"required security evidence is missing: {missing}", missing)
    for item in candidate.security_evidence:
        if item.status != "passed" or not item.executed:
            add("security_evidence_failed", f"security evidence {item.evidence_id} did not pass", item.evidence_id)
        if not _bound(item, candidate):
            add("security_evidence_stale", f"security evidence {item.evidence_id} does not match candidate", item.evidence_id)

    if not candidate.rollback_plan_ref:
        add("rollback_plan_missing", "rollback/recovery plan is required")
    if candidate.migration_required and not candidate.migration_plan_ref:
        add("migration_plan_missing", "migration plan is required for this candidate")
    if not candidate.release_notes_ref:
        add("release_notes_missing", "release notes are required")

    reasons.sort()
    return ProductionEligibility(eligible=not reasons, reasons=tuple(reasons))
