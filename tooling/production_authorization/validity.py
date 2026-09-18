from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any, Iterable, Mapping

from .eligibility import evaluate_eligibility
from .errors import InvalidProductionAuthorization
from .models import ProductionAuthorization, ReleaseActor, ReleaseCandidate


@dataclass(frozen=True, slots=True)
class AuthorizationEvent:
    event_id: str
    authorization_id: str
    event_type: str
    reason: str
    actor: ReleaseActor
    occurred_at: datetime

    def __post_init__(self) -> None:
        if not self.event_id.strip() or not self.authorization_id.strip():
            raise InvalidProductionAuthorization("authorization event identity is required")
        if self.event_type not in {"invalidated", "revoked"}:
            raise InvalidProductionAuthorization(
                "authorization event_type must be invalidated or revoked"
            )
        if not self.reason.strip():
            raise InvalidProductionAuthorization("authorization event reason is required")
        if self.occurred_at.tzinfo is None:
            raise InvalidProductionAuthorization("authorization event time must be timezone-aware")

    def to_dict(self) -> dict[str, Any]:
        return {
            "actor": self.actor.to_dict(),
            "authorization_id": self.authorization_id,
            "event_id": self.event_id,
            "event_type": self.event_type,
            "occurred_at": self.occurred_at.astimezone(timezone.utc)
                .isoformat()
                .replace("+00:00", "Z"),
            "reason": self.reason,
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "AuthorizationEvent":
        actor = value.get("actor")
        if not isinstance(actor, Mapping):
            raise InvalidProductionAuthorization("event actor is required")
        raw_time = value.get("occurred_at")
        if not isinstance(raw_time, str):
            raise InvalidProductionAuthorization("event occurred_at is required")
        return cls(
            event_id=str(value.get("event_id", "")),
            authorization_id=str(value.get("authorization_id", "")),
            event_type=str(value.get("event_type", "")),
            reason=str(value.get("reason", "")),
            actor=ReleaseActor.from_dict(actor),
            occurred_at=datetime.fromisoformat(raw_time.replace("Z", "+00:00")),
        )


@dataclass(frozen=True, slots=True)
class AuthorizationValidity:
    valid: bool
    reasons: tuple[str, ...]


def evaluate_authorization(
    authorization: ProductionAuthorization,
    candidate: ReleaseCandidate,
    invalidation_events: Iterable[AuthorizationEvent] = (),
) -> AuthorizationValidity:
    reasons: list[str] = []
    if authorization.client_id != candidate.client_id:
        reasons.append("client_mismatch")
    if authorization.environment != candidate.environment:
        reasons.append("environment_mismatch")
    if authorization.source_commit_sha != candidate.source_commit_sha:
        reasons.append("source_commit_mismatch")
    if authorization.build_artifact_id != candidate.build_artifact_id:
        reasons.append("build_artifact_mismatch")
    if authorization.build_hash != candidate.build_hash:
        reasons.append("build_hash_mismatch")
    if authorization.approval_version != candidate.approval_version:
        reasons.append("approval_version_mismatch")
    if authorization.approval_review_state_hash != candidate.approval_review_state_hash:
        reasons.append("approval_review_state_hash_mismatch")
    if authorization.approval_source_commit_sha != candidate.approval_source_commit_sha:
        reasons.append("approval_source_commit_mismatch")

    candidate_qa_ids = tuple(sorted(item.evidence_id for item in candidate.qa_evidence))
    candidate_validation_ids = tuple(
        sorted(item.evidence_id for item in candidate.validation_evidence)
    )
    candidate_security_ids = tuple(
        sorted(item.evidence_id for item in candidate.security_evidence)
    )
    if authorization.qa_evidence_ids != candidate_qa_ids:
        reasons.append("qa_evidence_identity_mismatch")
    if authorization.validation_evidence_ids != candidate_validation_ids:
        reasons.append("validation_evidence_identity_mismatch")
    if authorization.security_evidence_ids != candidate_security_ids:
        reasons.append("security_evidence_identity_mismatch")
    if authorization.rollback_plan_ref != candidate.rollback_plan_ref:
        reasons.append("rollback_plan_mismatch")
    if authorization.migration_plan_ref != candidate.migration_plan_ref:
        reasons.append("migration_plan_mismatch")
    if authorization.release_notes_ref != candidate.release_notes_ref:
        reasons.append("release_notes_mismatch")
    if (
        authorization.acknowledged_non_blocking_item_ids
        != candidate.acknowledged_non_blocking_item_ids
    ):
        reasons.append("non_blocking_acknowledgement_mismatch")
    if authorization.supporting_evidence_refs != candidate.supporting_evidence_refs:
        reasons.append("supporting_evidence_identity_mismatch")

    eligibility = evaluate_eligibility(candidate)
    reasons.extend(f"eligibility:{item.code}" for item in eligibility.reasons)

    for event in invalidation_events:
        if event.authorization_id == authorization.authorization_id:
            reasons.append(f"authorization_{event.event_type}")

    return AuthorizationValidity(valid=not reasons, reasons=tuple(sorted(set(reasons))))


class FileAuthorizationEventRepository:
    """Append-only event repository; authorization bodies remain untouched."""

    def __init__(self, client_dir: Path):
        self.client_dir = Path(client_dir)

    def _directory(self, environment: str) -> Path:
        return self.client_dir / "release" / "production-authorization-events" / environment

    def append(self, environment: str, event: AuthorizationEvent) -> Path:
        directory = self._directory(environment)
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / f"{event.event_id}.json"
        payload = json.dumps(event.to_dict(), indent=2, sort_keys=True) + "\n"
        try:
            with path.open("x", encoding="utf-8", newline="\n") as handle:
                handle.write(payload)
        except FileExistsError as exc:
            raise InvalidProductionAuthorization(
                f"authorization event already exists: {event.event_id}"
            ) from exc
        return path

    def list(self, environment: str) -> list[AuthorizationEvent]:
        directory = self._directory(environment)
        if not directory.exists():
            return []
        events = []
        for path in sorted(directory.glob("*.json")):
            events.append(
                AuthorizationEvent.from_dict(
                    json.loads(path.read_text(encoding="utf-8"))
                )
            )
        return events
