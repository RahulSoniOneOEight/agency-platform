"""Repository-native client workflow lease.

Only one state-mutating workflow execution may own a client project at a time.
The lease lives inside ``workflow-state.yaml`` as the nullable ``active_lease``
mapping, so coordination needs no external service (RE6). A lease is
coordination only: it is never completion proof and never changes
``current_stage``, ``completed``, or ``pending``.
"""

from __future__ import annotations

import copy
import hashlib
import json
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any


LEASE_STATUSES = ("active", "expired")

LEASE_KEYS = ("lease_id", "owner", "run_id", "acquired_at", "expires_at")

_TS_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class WorkflowLeaseError(RuntimeError):
    """Raised when a lease mapping is malformed or cannot be operated on."""


class WorkflowLeaseConflict(WorkflowLeaseError):
    """Raised when an active lease is held by a different owner or run."""


class WorkflowLeaseExpired(WorkflowLeaseError):
    """Raised when an expired lease is used without a reconcile first."""


class WorkflowLeaseOwnershipError(WorkflowLeaseError):
    """Raised when a lease operation does not match the held lease id and owner."""


@dataclass(frozen=True)
class WorkflowLease:
    lease_id: str
    owner: str
    run_id: str | None
    acquired_at: str
    expires_at: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "lease_id": self.lease_id,
            "owner": self.owner,
            "run_id": self.run_id,
            "acquired_at": self.acquired_at,
            "expires_at": self.expires_at,
        }


def _to_utc(now: datetime) -> datetime:
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _iso(now: datetime) -> str:
    return _to_utc(now).strftime(_TS_FORMAT)


def _parse_iso(value: str) -> datetime:
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _lease_id(owner: str, run_id: str | None, acquired_at: str, expires_at: str) -> str:
    seed = json.dumps(
        [owner, run_id, acquired_at, expires_at], separators=(",", ":")
    )
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()
    return f"lease-{digest[:12]}"


def _require_owner(owner: Any) -> str:
    if not isinstance(owner, str) or not owner.strip():
        raise WorkflowLeaseError(f"invalid lease owner: {owner!r}")
    return owner


def load_lease(state: Mapping[str, Any]) -> WorkflowLease | None:
    """Return the parsed lease held by *state*, or ``None`` when none is held."""
    raw = state.get("active_lease")
    if raw is None:
        return None
    if not isinstance(raw, Mapping):
        raise WorkflowLeaseError(f"active_lease must be a mapping or null: {raw!r}")
    values: dict[str, Any] = {}
    for key in LEASE_KEYS:
        value = raw.get(key)
        if key == "run_id":
            if value is not None and (not isinstance(value, str) or not value.strip()):
                raise WorkflowLeaseError(f"invalid active_lease.run_id: {value!r}")
        elif not isinstance(value, str) or not value.strip():
            raise WorkflowLeaseError(f"invalid active_lease.{key}: {value!r}")
        values[key] = value
    return WorkflowLease(
        lease_id=values["lease_id"],
        owner=values["owner"],
        run_id=values["run_id"],
        acquired_at=values["acquired_at"],
        expires_at=values["expires_at"],
    )


def is_expired(lease: WorkflowLease, *, now: datetime) -> bool:
    """Expiry is inclusive: a lease is expired once ``now >= expires_at``."""
    return _parse_iso(lease.expires_at) <= _to_utc(now)


def acquire_lease(
    state: Mapping[str, Any],
    *,
    owner: str,
    run_id: str | None = None,
    now: datetime,
    ttl_seconds: int = 1800,
) -> tuple[dict[str, Any], WorkflowLease]:
    """Acquire the client lease, or idempotently re-acquire the same one.

    A different owner or run against a live lease raises
    :class:`WorkflowLeaseConflict`. An expired lease raises
    :class:`WorkflowLeaseExpired` and must be reclaimed through
    :func:`reconcile_expired_lease` first.
    """
    _require_owner(owner)
    existing = load_lease(state)
    if existing is not None:
        if is_expired(existing, now=now):
            raise WorkflowLeaseExpired(
                f"lease {existing.lease_id} owned by {existing.owner!r} is expired; "
                "reconcile it before acquiring"
            )
        if existing.owner == owner and existing.run_id == run_id:
            return copy.deepcopy(dict(state)), existing
        raise WorkflowLeaseConflict(
            f"client already leased by {existing.owner!r} for run {existing.run_id!r}"
        )

    acquired_at = _iso(now)
    expires_at = _iso(_to_utc(now) + timedelta(seconds=ttl_seconds))
    lease = WorkflowLease(
        lease_id=_lease_id(owner, run_id, acquired_at, expires_at),
        owner=owner,
        run_id=run_id,
        acquired_at=acquired_at,
        expires_at=expires_at,
    )
    new_state = copy.deepcopy(dict(state))
    new_state["active_lease"] = lease.to_dict()
    return new_state, lease


def renew_lease(
    state: Mapping[str, Any],
    lease: WorkflowLease,
    *,
    now: datetime,
    ttl_seconds: int = 1800,
) -> tuple[dict[str, Any], WorkflowLease]:
    """Extend a held lease's expiry; the lease id and owner must match."""
    existing = load_lease(state)
    if (
        existing is None
        or existing.lease_id != lease.lease_id
        or existing.owner != lease.owner
    ):
        raise WorkflowLeaseOwnershipError(
            f"cannot renew lease {lease.lease_id} owned by {lease.owner!r}"
        )
    if is_expired(existing, now=now):
        raise WorkflowLeaseExpired(
            f"lease {existing.lease_id} is expired and cannot be renewed; reconcile first"
        )
    renewed = WorkflowLease(
        lease_id=existing.lease_id,
        owner=existing.owner,
        run_id=existing.run_id,
        acquired_at=existing.acquired_at,
        expires_at=_iso(_to_utc(now) + timedelta(seconds=ttl_seconds)),
    )
    new_state = copy.deepcopy(dict(state))
    new_state["active_lease"] = renewed.to_dict()
    return new_state, renewed


def release_lease(state: Mapping[str, Any], lease: WorkflowLease) -> dict[str, Any]:
    """Release the held lease; both lease id and owner must match."""
    existing = load_lease(state)
    if (
        existing is None
        or existing.lease_id != lease.lease_id
        or existing.owner != lease.owner
    ):
        raise WorkflowLeaseOwnershipError(
            f"cannot release lease {lease.lease_id} owned by {lease.owner!r}"
        )
    new_state = copy.deepcopy(dict(state))
    new_state["active_lease"] = None
    return new_state


def reconcile_expired_lease(
    state: Mapping[str, Any], *, now: datetime
) -> tuple[dict[str, Any], WorkflowLease | None]:
    """Clear an expired lease, returning it so the caller can audit recovery.

    This is the only path that removes a lease it does not own. A live or
    absent lease is returned unchanged.
    """
    existing = load_lease(state)
    if existing is None or not is_expired(existing, now=now):
        return copy.deepcopy(dict(state)), existing
    new_state = copy.deepcopy(dict(state))
    new_state["active_lease"] = None
    return new_state, existing
