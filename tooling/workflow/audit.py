"""Append-only workflow audit records.

Rulings, deviations, manual overrides, and recovery events are durable,
append-only evidence. Records are never edited in place. An override requires a
human actor: an ``opencode:`` actor is rejected (RE8). No record carries or
mutates C/D domain state.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any


AUDIT_KINDS = ("ruling", "deviation", "override", "recovery")

_REQUIRED_KEYS = (
    "id",
    "kind",
    "actor",
    "at",
    "stage",
    "run_id",
    "summary",
    "reason",
    "details",
)

_AGENT_ACTOR_PREFIX = "opencode:"


def _require_human_override(kind: Any, actor: Any) -> None:
    """A manual override is a human action; an agent may never author one."""
    if kind == "override" and _is_agent_actor(actor):
        raise ValueError(
            "manual override requires a human actor, not an opencode agent"
        )


def _is_agent_actor(actor: Any) -> bool:
    """Whether *actor* identifies an agent rather than a human.

    Compared case-insensitively and ignoring surrounding whitespace so a
    cosmetic variant cannot slip past the human-only override rule.
    """
    return isinstance(actor, str) and actor.strip().lower().startswith(
        _AGENT_ACTOR_PREFIX
    )


@dataclass(frozen=True)
class AuditRecord:
    id: str
    kind: str
    actor: str
    at: str
    stage: str | None
    run_id: str | None
    summary: str
    reason: str
    details: Mapping[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "actor": self.actor,
            "at": self.at,
            "stage": self.stage,
            "run_id": self.run_id,
            "summary": self.summary,
            "reason": self.reason,
            "details": dict(self.details),
        }

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "AuditRecord":
        missing = [key for key in _REQUIRED_KEYS if key not in data]
        if missing:
            raise ValueError(f"audit record missing key {missing[0]!r}")
        details = data["details"]
        if not isinstance(details, Mapping):
            raise ValueError("audit record details must be a mapping")
        record = cls(
            id=data["id"],
            kind=data["kind"],
            actor=data["actor"],
            at=data["at"],
            stage=data["stage"],
            run_id=data["run_id"],
            summary=data["summary"],
            reason=data["reason"],
            details=dict(details),
        )
        _require_human_override(record.kind, record.actor)
        return record


def _require_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"audit record requires a non-blank {label}")
    return value


def _record_id(kind: str, payload: Mapping[str, Any]) -> str:
    canonical = json.dumps(dict(payload), sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return f"{kind}-{digest[:12]}"


def _make_record(
    kind: str,
    *,
    actor: Any,
    at: Any,
    summary: Any,
    reason: Any,
    stage: str | None,
    run_id: str | None,
    details: Mapping[str, Any],
) -> AuditRecord:
    if kind not in AUDIT_KINDS:
        raise ValueError(f"unknown audit record kind: {kind!r}")
    actor = _require_text(actor, "actor")
    at = _require_text(at, "timestamp")
    summary = _require_text(summary, "summary")
    reason = _require_text(reason, "reason")
    if not isinstance(details, Mapping):
        raise ValueError("audit record details must be a mapping")
    payload = {
        "kind": kind,
        "actor": actor,
        "at": at,
        "stage": stage,
        "run_id": run_id,
        "summary": summary,
        "reason": reason,
        "details": dict(details),
    }
    return AuditRecord(
        id=_record_id(kind, payload),
        kind=kind,
        actor=actor,
        at=at,
        stage=stage,
        run_id=run_id,
        summary=summary,
        reason=reason,
        details=dict(details),
    )


def make_ruling(
    *,
    actor: str,
    at: str,
    summary: str,
    reason: str,
    stage: str | None = None,
    run_id: str | None = None,
    decision: Any,
    cost_if_wrong: Any = None,
) -> AuditRecord:
    details: dict[str, Any] = {"decision": decision}
    if cost_if_wrong is not None:
        details["cost_if_wrong"] = cost_if_wrong
    return _make_record(
        "ruling",
        actor=actor,
        at=at,
        summary=summary,
        reason=reason,
        stage=stage,
        run_id=run_id,
        details=details,
    )


def make_deviation(
    *,
    actor: str,
    at: str,
    summary: str,
    reason: str,
    stage: str | None = None,
    run_id: str | None = None,
    expected: Any = None,
    actual: Any = None,
    impact: Any = None,
    requested_model: Any = None,
    actual_model: Any = None,
    requested_tool: Any = None,
    actual_tool: Any = None,
) -> AuditRecord:
    candidates = {
        "expected": expected,
        "actual": actual,
        "impact": impact,
        "requested_model": requested_model,
        "actual_model": actual_model,
        "requested_tool": requested_tool,
        "actual_tool": actual_tool,
    }
    details = {key: value for key, value in candidates.items() if value is not None}
    return _make_record(
        "deviation",
        actor=actor,
        at=at,
        summary=summary,
        reason=reason,
        stage=stage,
        run_id=run_id,
        details=details,
    )


def make_override(
    *,
    actor: str,
    at: str,
    summary: str,
    reason: str,
    affected_gate: str,
    stage: str | None = None,
    run_id: str | None = None,
    previous_state: Any = None,
    requested_state: Any = None,
    evidence: Any = None,
) -> AuditRecord:
    if _is_agent_actor(actor):
        raise ValueError("manual override requires a human actor, not an opencode agent")
    _require_text(affected_gate, "affected_gate")
    details: dict[str, Any] = {"affected_gate": affected_gate}
    if previous_state is not None:
        details["previous_state"] = previous_state
    if requested_state is not None:
        details["requested_state"] = requested_state
    if evidence is not None:
        details["evidence"] = evidence
    return _make_record(
        "override",
        actor=actor,
        at=at,
        summary=summary,
        reason=reason,
        stage=stage,
        run_id=run_id,
        details=details,
    )


def make_recovery_record(
    *,
    actor: str,
    at: str,
    summary: str,
    reason: str,
    stage: str | None = None,
    run_id: str | None = None,
    previous_state: Any = None,
    requested_state: Any = None,
) -> AuditRecord:
    details: dict[str, Any] = {}
    if previous_state is not None:
        details["previous_state"] = previous_state
    if requested_state is not None:
        details["requested_state"] = requested_state
    return _make_record(
        "recovery",
        actor=actor,
        at=at,
        summary=summary,
        reason=reason,
        stage=stage,
        run_id=run_id,
        details=details,
    )


def append_audit_record(path: Path, record: AuditRecord) -> None:
    """Append one compact JSON line; existing lines are never rewritten.

    The record is validated before it is persisted, so a hand-built override
    that bypassed the factories is still rejected here.
    """
    _require_human_override(record.kind, record.actor)
    errors = validate_audit_record(record.to_dict())
    if errors:
        raise ValueError("invalid audit record: " + "; ".join(errors))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(record.to_dict(), sort_keys=True, separators=(",", ":")) + "\n"
    with path.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(line)


def load_audit_records(path: Path) -> list[AuditRecord]:
    """Return every record in *path*; a missing file yields an empty list."""
    path = Path(path)
    if not path.exists():
        return []
    records: list[AuditRecord] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path}: malformed audit record on line {number}: {exc}") from exc
        if not isinstance(data, Mapping):
            raise ValueError(f"{path}: audit record on line {number} must be an object")
        try:
            records.append(AuditRecord.from_dict(data))
        except (KeyError, ValueError) as exc:
            raise ValueError(f"{path}: invalid audit record on line {number}: {exc}") from exc
    return records


def validate_audit_record(data: Mapping[str, Any]) -> list[str]:
    """Return deterministic schema-shape errors for *data* (empty == valid)."""
    if not isinstance(data, Mapping):
        return ["audit record must be a mapping"]
    errors: list[str] = []
    unknown = sorted(set(data) - set(_REQUIRED_KEYS))
    if unknown:
        errors.append(f"unknown key: {unknown[0]}")
    missing = [key for key in _REQUIRED_KEYS if key not in data]
    if missing:
        errors.append(f"missing key: {missing[0]}")

    kind = data.get("kind")
    if kind not in AUDIT_KINDS:
        errors.append(f"invalid kind: {kind!r}")

    for key in ("id", "actor", "at", "summary", "reason"):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{key} must be a non-blank string")

    for key in ("stage", "run_id"):
        value = data.get(key)
        if value is not None and not isinstance(value, str):
            errors.append(f"{key} must be a string or null")

    details = data.get("details")
    if not isinstance(details, Mapping):
        errors.append("details must be an object")
    elif kind == "override":
        gate = details.get("affected_gate")
        if not isinstance(gate, str) or not gate.strip():
            errors.append("override details require a non-blank affected_gate")
        if _is_agent_actor(data.get("actor")):
            errors.append("manual override requires a human actor")
    return sorted(errors)
