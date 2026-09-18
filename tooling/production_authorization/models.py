from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
import json
import re
from typing import Any, Iterable, Mapping

from .errors import InvalidProductionAuthorization, InvalidReleaseCandidate


_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def _required(value: str, label: str, error_type=InvalidReleaseCandidate) -> str:
    if not isinstance(value, str) or not value.strip():
        raise error_type(f"{label} is required")
    return value.strip()


def _sha(value: str, label: str, error_type=InvalidReleaseCandidate) -> str:
    value = _required(value, label, error_type)
    if not _SHA_RE.fullmatch(value):
        raise error_type(f"{label} must be a lowercase 40-character git SHA")
    return value


def _hash(value: str, label: str, error_type=InvalidReleaseCandidate) -> str:
    value = _required(value, label, error_type)
    if not _HASH_RE.fullmatch(value):
        raise error_type(f"{label} must be sha256:<64 lowercase hex>")
    return value


def _sorted_unique(values: Iterable[str], label: str, error_type) -> tuple[str, ...]:
    normalized = []
    seen: set[str] = set()
    for raw in values:
        value = _required(raw, label, error_type)
        if value in seen:
            raise error_type(f"duplicate {label}: {value}")
        seen.add(value)
        normalized.append(value)
    return tuple(sorted(normalized))


@dataclass(frozen=True, slots=True)
class ReleaseActor:
    actor_id: str
    name: str
    kind: str
    role: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "actor_id", _required(self.actor_id, "actor id", InvalidProductionAuthorization))
        object.__setattr__(self, "name", _required(self.name, "actor name", InvalidProductionAuthorization))
        if self.kind not in {"human", "agent", "ci"}:
            raise InvalidProductionAuthorization("actor kind must be human, agent, or ci")
        object.__setattr__(self, "role", _required(self.role, "actor role", InvalidProductionAuthorization))

    @property
    def is_human_release_owner(self) -> bool:
        return self.kind == "human" and self.role == "release_owner"

    def to_dict(self) -> dict[str, Any]:
        return {
            "actor_id": self.actor_id,
            "kind": self.kind,
            "name": self.name,
            "role": self.role,
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ReleaseActor":
        return cls(
            actor_id=str(value.get("actor_id", "")),
            name=str(value.get("name", "")),
            kind=str(value.get("kind", "")),
            role=str(value.get("role", "")),
        )


@dataclass(frozen=True, slots=True)
class EvidenceRef:
    evidence_id: str
    category: str
    status: str
    source: str
    candidate_sha: str | None = None
    build_hash: str | None = None
    executed: bool = True
    blocking_count: int = 0
    refs: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        object.__setattr__(self, "evidence_id", _required(self.evidence_id, "evidence id"))
        object.__setattr__(self, "category", _required(self.category, "evidence category"))
        if self.status not in {"passed", "failed", "missing", "stale", "declared_only"}:
            raise InvalidReleaseCandidate(f"unsupported evidence status: {self.status}")
        object.__setattr__(self, "source", _required(self.source, "evidence source"))
        if self.candidate_sha is not None:
            object.__setattr__(self, "candidate_sha", _sha(self.candidate_sha, "evidence candidate SHA"))
        if self.build_hash is not None:
            object.__setattr__(self, "build_hash", _hash(self.build_hash, "evidence build hash"))
        if self.blocking_count < 0:
            raise InvalidReleaseCandidate("evidence blocking_count cannot be negative")
        object.__setattr__(self, "refs", _sorted_unique(self.refs, "evidence ref", InvalidReleaseCandidate))

    def to_dict(self) -> dict[str, Any]:
        return {
            "blocking_count": self.blocking_count,
            "build_hash": self.build_hash,
            "candidate_sha": self.candidate_sha,
            "category": self.category,
            "evidence_id": self.evidence_id,
            "executed": self.executed,
            "refs": list(self.refs),
            "source": self.source,
            "status": self.status,
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "EvidenceRef":
        refs = value.get("refs", [])
        if not isinstance(refs, list):
            raise InvalidReleaseCandidate("evidence refs must be a list")
        return cls(
            evidence_id=str(value.get("evidence_id", "")),
            category=str(value.get("category", "")),
            status=str(value.get("status", "")),
            source=str(value.get("source", "")),
            candidate_sha=value.get("candidate_sha"),
            build_hash=value.get("build_hash"),
            executed=bool(value.get("executed", True)),
            blocking_count=int(value.get("blocking_count", 0)),
            refs=tuple(str(item) for item in refs),
        )


@dataclass(frozen=True, slots=True)
class ReleaseCandidate:
    client_id: str
    environment: str
    approval_version: int
    approval_review_state_hash: str
    approval_source_commit_sha: str
    source_commit_sha: str
    build_artifact_id: str
    build_hash: str
    approval_current: bool
    unresolved_blocking_feedback_ids: tuple[str, ...]
    qa_evidence: tuple[EvidenceRef, ...]
    validation_evidence: tuple[EvidenceRef, ...]
    security_evidence: tuple[EvidenceRef, ...]
    rollback_plan_ref: str
    migration_required: bool
    migration_plan_ref: str | None
    release_notes_ref: str
    acknowledged_non_blocking_item_ids: tuple[str, ...] = ()
    supporting_evidence_refs: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        object.__setattr__(self, "client_id", _required(self.client_id, "client id"))
        object.__setattr__(self, "environment", _required(self.environment, "environment"))
        if self.approval_version < 1:
            raise InvalidReleaseCandidate("approval version must be positive")
        object.__setattr__(self, "approval_review_state_hash", _hash(self.approval_review_state_hash, "approval review-state hash"))
        object.__setattr__(self, "approval_source_commit_sha", _sha(self.approval_source_commit_sha, "approval source commit SHA"))
        object.__setattr__(self, "source_commit_sha", _sha(self.source_commit_sha, "candidate source commit SHA"))
        object.__setattr__(self, "build_artifact_id", _required(self.build_artifact_id, "build artifact id"))
        object.__setattr__(self, "build_hash", _hash(self.build_hash, "build hash"))
        object.__setattr__(
            self,
            "unresolved_blocking_feedback_ids",
            _sorted_unique(self.unresolved_blocking_feedback_ids, "blocking feedback id", InvalidReleaseCandidate),
        )
        object.__setattr__(self, "rollback_plan_ref", _required(self.rollback_plan_ref, "rollback plan ref"))
        if self.migration_required and not (self.migration_plan_ref and self.migration_plan_ref.strip()):
            raise InvalidReleaseCandidate("migration plan ref is required when migration_required is true")
        if self.migration_plan_ref is not None and not self.migration_plan_ref.strip():
            raise InvalidReleaseCandidate("migration plan ref must not be blank")
        object.__setattr__(self, "release_notes_ref", _required(self.release_notes_ref, "release notes ref"))
        object.__setattr__(
            self,
            "acknowledged_non_blocking_item_ids",
            _sorted_unique(self.acknowledged_non_blocking_item_ids, "acknowledged non-blocking item id", InvalidReleaseCandidate),
        )
        object.__setattr__(
            self,
            "supporting_evidence_refs",
            _sorted_unique(self.supporting_evidence_refs, "supporting evidence ref", InvalidReleaseCandidate),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "acknowledged_non_blocking_item_ids": list(self.acknowledged_non_blocking_item_ids),
            "approval": {
                "current": self.approval_current,
                "review_state_hash": self.approval_review_state_hash,
                "source_commit_sha": self.approval_source_commit_sha,
                "version": self.approval_version,
            },
            "build": {
                "artifact_id": self.build_artifact_id,
                "hash": self.build_hash,
            },
            "client_id": self.client_id,
            "environment": self.environment,
            "migration": {
                "plan_ref": self.migration_plan_ref,
                "required": self.migration_required,
            },
            "qa_evidence": [item.to_dict() for item in self.qa_evidence],
            "release_notes_ref": self.release_notes_ref,
            "rollback_plan_ref": self.rollback_plan_ref,
            "security_evidence": [item.to_dict() for item in self.security_evidence],
            "source_commit_sha": self.source_commit_sha,
            "supporting_evidence_refs": list(self.supporting_evidence_refs),
            "unresolved_blocking_feedback_ids": list(self.unresolved_blocking_feedback_ids),
            "validation_evidence": [item.to_dict() for item in self.validation_evidence],
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ReleaseCandidate":
        approval = value.get("approval")
        build = value.get("build")
        migration = value.get("migration")
        if not isinstance(approval, Mapping) or not isinstance(build, Mapping) or not isinstance(migration, Mapping):
            raise InvalidReleaseCandidate("candidate approval/build/migration objects are required")

        def evidence_list(key: str) -> tuple[EvidenceRef, ...]:
            raw = value.get(key)
            if not isinstance(raw, list):
                raise InvalidReleaseCandidate(f"{key} must be a list")
            return tuple(EvidenceRef.from_dict(item) for item in raw if isinstance(item, Mapping))

        return cls(
            client_id=str(value.get("client_id", "")),
            environment=str(value.get("environment", "")),
            approval_version=int(approval.get("version", 0)),
            approval_review_state_hash=str(approval.get("review_state_hash", "")),
            approval_source_commit_sha=str(approval.get("source_commit_sha", "")),
            source_commit_sha=str(value.get("source_commit_sha", "")),
            build_artifact_id=str(build.get("artifact_id", "")),
            build_hash=str(build.get("hash", "")),
            approval_current=bool(approval.get("current", False)),
            unresolved_blocking_feedback_ids=tuple(str(item) for item in value.get("unresolved_blocking_feedback_ids", [])),
            qa_evidence=evidence_list("qa_evidence"),
            validation_evidence=evidence_list("validation_evidence"),
            security_evidence=evidence_list("security_evidence"),
            rollback_plan_ref=str(value.get("rollback_plan_ref", "")),
            migration_required=bool(migration.get("required", False)),
            migration_plan_ref=migration.get("plan_ref"),
            release_notes_ref=str(value.get("release_notes_ref", "")),
            acknowledged_non_blocking_item_ids=tuple(str(item) for item in value.get("acknowledged_non_blocking_item_ids", [])),
            supporting_evidence_refs=tuple(str(item) for item in value.get("supporting_evidence_refs", [])),
        )


class AuthorizationStatus(str, Enum):
    active = "active"


@dataclass(frozen=True, slots=True)
class ProductionAuthorization:
    authorization_id: str
    authorization_version: int
    client_id: str
    environment: str
    approval_version: int
    approval_review_state_hash: str
    approval_source_commit_sha: str
    source_commit_sha: str
    build_artifact_id: str
    build_hash: str
    qa_evidence_ids: tuple[str, ...]
    validation_evidence_ids: tuple[str, ...]
    security_evidence_ids: tuple[str, ...]
    rollback_plan_ref: str
    migration_plan_ref: str | None
    release_notes_ref: str
    acknowledged_non_blocking_item_ids: tuple[str, ...]
    supporting_evidence_refs: tuple[str, ...]
    authorized_by: ReleaseActor
    authorized_at: datetime
    supersedes: int | None = None
    status: AuthorizationStatus = AuthorizationStatus.active

    def __post_init__(self) -> None:
        object.__setattr__(self, "authorization_id", _required(self.authorization_id, "authorization id", InvalidProductionAuthorization))
        if self.authorization_version < 1:
            raise InvalidProductionAuthorization("authorization version must be positive")
        object.__setattr__(self, "client_id", _required(self.client_id, "client id", InvalidProductionAuthorization))
        object.__setattr__(self, "environment", _required(self.environment, "environment", InvalidProductionAuthorization))
        if self.approval_version < 1:
            raise InvalidProductionAuthorization("approval version must be positive")
        object.__setattr__(self, "approval_review_state_hash", _hash(self.approval_review_state_hash, "approval review-state hash", InvalidProductionAuthorization))
        object.__setattr__(self, "approval_source_commit_sha", _sha(self.approval_source_commit_sha, "approval source commit SHA", InvalidProductionAuthorization))
        object.__setattr__(self, "source_commit_sha", _sha(self.source_commit_sha, "candidate source commit SHA", InvalidProductionAuthorization))
        object.__setattr__(self, "build_artifact_id", _required(self.build_artifact_id, "build artifact id", InvalidProductionAuthorization))
        object.__setattr__(self, "build_hash", _hash(self.build_hash, "build hash", InvalidProductionAuthorization))
        for name in ("qa_evidence_ids", "validation_evidence_ids", "security_evidence_ids",
                     "acknowledged_non_blocking_item_ids", "supporting_evidence_refs"):
            object.__setattr__(self, name, _sorted_unique(getattr(self, name), name, InvalidProductionAuthorization))
        object.__setattr__(self, "rollback_plan_ref", _required(self.rollback_plan_ref, "rollback plan ref", InvalidProductionAuthorization))
        object.__setattr__(self, "release_notes_ref", _required(self.release_notes_ref, "release notes ref", InvalidProductionAuthorization))
        if self.migration_plan_ref is not None and not self.migration_plan_ref.strip():
            raise InvalidProductionAuthorization("migration plan ref must not be blank")
        if not self.authorized_by.is_human_release_owner:
            raise InvalidProductionAuthorization("authorized_by must be a human release_owner")
        if self.authorized_at.tzinfo is None:
            raise InvalidProductionAuthorization("authorized_at must be timezone-aware")
        if self.supersedes is not None and (self.supersedes < 1 or self.supersedes >= self.authorization_version):
            raise InvalidProductionAuthorization("supersedes must reference an earlier authorization version")

    def to_dict(self) -> dict[str, Any]:
        return {
            "acknowledged_non_blocking_item_ids": list(self.acknowledged_non_blocking_item_ids),
            "approval": {
                "review_state_hash": self.approval_review_state_hash,
                "source_commit_sha": self.approval_source_commit_sha,
                "version": self.approval_version,
            },
            "authorization_id": self.authorization_id,
            "authorization_version": self.authorization_version,
            "authorized_at": self.authorized_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
            "authorized_by": self.authorized_by.to_dict(),
            "build": {"artifact_id": self.build_artifact_id, "hash": self.build_hash},
            "client_id": self.client_id,
            "environment": self.environment,
            "migration_plan_ref": self.migration_plan_ref,
            "qa_evidence_ids": list(self.qa_evidence_ids),
            "release_notes_ref": self.release_notes_ref,
            "rollback_plan_ref": self.rollback_plan_ref,
            "security_evidence_ids": list(self.security_evidence_ids),
            "source_commit_sha": self.source_commit_sha,
            "status": self.status.value,
            "supersedes": self.supersedes,
            "supporting_evidence_refs": list(self.supporting_evidence_refs),
            "validation_evidence_ids": list(self.validation_evidence_ids),
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "ProductionAuthorization":
        approval = value.get("approval")
        build = value.get("build")
        actor = value.get("authorized_by")
        if not isinstance(approval, Mapping) or not isinstance(build, Mapping) or not isinstance(actor, Mapping):
            raise InvalidProductionAuthorization("authorization approval/build/authorized_by objects are required")
        at = value.get("authorized_at")
        if not isinstance(at, str):
            raise InvalidProductionAuthorization("authorized_at is required")
        try:
            parsed_at = datetime.fromisoformat(at.replace("Z", "+00:00"))
        except ValueError as exc:
            raise InvalidProductionAuthorization("authorized_at must be ISO-8601") from exc
        return cls(
            authorization_id=str(value.get("authorization_id", "")),
            authorization_version=int(value.get("authorization_version", 0)),
            client_id=str(value.get("client_id", "")),
            environment=str(value.get("environment", "")),
            approval_version=int(approval.get("version", 0)),
            approval_review_state_hash=str(approval.get("review_state_hash", "")),
            approval_source_commit_sha=str(approval.get("source_commit_sha", "")),
            source_commit_sha=str(value.get("source_commit_sha", "")),
            build_artifact_id=str(build.get("artifact_id", "")),
            build_hash=str(build.get("hash", "")),
            qa_evidence_ids=tuple(str(x) for x in value.get("qa_evidence_ids", [])),
            validation_evidence_ids=tuple(str(x) for x in value.get("validation_evidence_ids", [])),
            security_evidence_ids=tuple(str(x) for x in value.get("security_evidence_ids", [])),
            rollback_plan_ref=str(value.get("rollback_plan_ref", "")),
            migration_plan_ref=value.get("migration_plan_ref"),
            release_notes_ref=str(value.get("release_notes_ref", "")),
            acknowledged_non_blocking_item_ids=tuple(str(x) for x in value.get("acknowledged_non_blocking_item_ids", [])),
            supporting_evidence_refs=tuple(str(x) for x in value.get("supporting_evidence_refs", [])),
            authorized_by=ReleaseActor.from_dict(actor),
            authorized_at=parsed_at,
            supersedes=value.get("supersedes"),
            status=AuthorizationStatus(str(value.get("status", "active"))),
        )


def canonical_json(value: ReleaseCandidate | ProductionAuthorization) -> str:
    return json.dumps(value.to_dict(), indent=2, sort_keys=True) + "\n"
