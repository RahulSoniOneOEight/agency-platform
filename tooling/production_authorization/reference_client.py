from __future__ import annotations
import json
from dataclasses import replace
from pathlib import Path
from .errors import InvalidReleaseCandidate
from .models import EvidenceRef, ReleaseCandidate, canonical_json

REFERENCE_CLIENT="reference-commerce"
REPORT_REL="client-projects/reference-commerce/reference-e2e/report/reference-report.json"
REVIEW_EVIDENCE_REL="client-projects/reference-commerce/reference-e2e/evidence/review-approval-evidence.json"
CHANGE_EVIDENCE_REL="client-projects/reference-commerce/reference-e2e/evidence/change-scenarios-evidence.json"
RESUME_EVIDENCE_REL="client-projects/reference-commerce/reference-e2e/evidence/resume-evidence.json"

def _read_json(path: Path) -> dict:
    try:
        value=json.loads(path.read_text(encoding="utf-8"))
    except (OSError,UnicodeError,json.JSONDecodeError) as exc:
        raise InvalidReleaseCandidate(f"cannot read reference release evidence {path}: {exc}") from exc
    if not isinstance(value,dict):
        raise InvalidReleaseCandidate(f"reference release evidence must be an object: {path}")
    return value

def _evidence_list(path: Path) -> tuple[EvidenceRef,...]:
    payload=_read_json(path); raw=payload.get("evidence")
    if not isinstance(raw,list) or not raw or any(not isinstance(item,dict) for item in raw):
        raise InvalidReleaseCandidate(f"evidence list of objects is required: {path}")
    return tuple(EvidenceRef.from_dict(item) for item in raw)

def build_reference_candidate(root: Path) -> ReleaseCandidate:
    root=Path(root); client=root/"client-projects"/REFERENCE_CLIENT
    report=_read_json(root/REPORT_REL)
    approvals=report.get("approvals")
    if not isinstance(approvals,list) or not approvals:
        raise InvalidReleaseCandidate("F machine report has no approval summaries")
    approval=max(approvals,key=lambda item:int(item.get("version",0)))
    if int(approval.get("version",0))!=2:
        raise InvalidReleaseCandidate("reference G fixture requires merged F Approval v2")
    if report.get("assertions",{}).get("failed")!=0:
        raise InvalidReleaseCandidate("F machine report contains failing assertions")
    build=_read_json(client/"release"/"build.json")
    source_sha=str(build.get("source_commit_sha","")); build_hash=str(build.get("hash",""))
    if source_sha!=approval.get("source_commit_sha"):
        raise InvalidReleaseCandidate("release build source SHA must match F Approval v2 source SHA")
    blocking=tuple(str(item["id"]) for item in report.get("feedback",{}).get("blocking",[]) if item.get("status")!="resolved")
    acknowledged={str(item["id"]) for item in report.get("feedback",{}).get("non_blocking",[])}
    acknowledged.update(str(item["id"]) for item in report.get("feedback",{}).get("visual_annotations",[]))
    acknowledged.update(str(item["feedback_id"]) for item in report.get("qa",{}).get("promotions",[]) if item.get("feedback_id"))
    migration=_read_json(client/"release"/"evidence"/"migration.json")
    return ReleaseCandidate(
        client_id=REFERENCE_CLIENT,environment="production",approval_version=int(approval["version"]),
        approval_review_state_hash=str(approval["review_state_hash"]),approval_source_commit_sha=str(approval["source_commit_sha"]),
        source_commit_sha=source_sha,build_artifact_id=str(build.get("artifact_id","")),build_hash=build_hash,approval_current=True,
        unresolved_blocking_feedback_ids=blocking,qa_evidence=_evidence_list(client/"release"/"evidence"/"qa.json"),
        validation_evidence=_evidence_list(client/"release"/"evidence"/"validation.json"),
        security_evidence=_evidence_list(client/"release"/"evidence"/"security.json"),
        rollback_plan_ref="client-projects/reference-commerce/release/evidence/rollback.md",
        migration_required=bool(migration.get("required",False)),
        migration_plan_ref=str(migration.get("plan_ref")) if migration.get("plan_ref") else None,
        release_notes_ref="client-projects/reference-commerce/release/evidence/release-notes.md",
        acknowledged_non_blocking_item_ids=tuple(sorted(acknowledged)),
        supporting_evidence_refs=(CHANGE_EVIDENCE_REL,RESUME_EVIDENCE_REL,REVIEW_EVIDENCE_REL,REPORT_REL),
    )

def implementation_only_candidate(candidate: ReleaseCandidate,*,source_commit_sha:str,build_artifact_id:str,build_hash:str)->ReleaseCandidate:
    def rebound(items: tuple[EvidenceRef,...])->tuple[EvidenceRef,...]:
        return tuple(replace(item,candidate_sha=source_commit_sha,build_hash=build_hash) for item in items)
    return replace(candidate,source_commit_sha=source_commit_sha,build_artifact_id=build_artifact_id,build_hash=build_hash,
                   qa_evidence=rebound(candidate.qa_evidence),validation_evidence=rebound(candidate.validation_evidence),
                   security_evidence=rebound(candidate.security_evidence))

def candidate_freshness_errors(root: Path)->list[str]:
    root=Path(root); path=root/"client-projects"/REFERENCE_CLIENT/"release"/"candidate.json"
    fresh=canonical_json(build_reference_candidate(root))
    try: committed=path.read_text(encoding="utf-8")
    except OSError as exc: return [f"release candidate missing/unreadable: {exc}"]
    return [] if committed==fresh else ["release candidate is stale against merged F + release evidence"]
