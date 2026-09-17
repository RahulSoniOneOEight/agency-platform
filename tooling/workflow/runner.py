"""Canonical OpenCode-facing workflow runtime entry point.

The runner is a thin orchestration fa\u00e7ade over the hardened workflow domain:
``state`` (the canonical pointer), ``contracts`` (stage metadata), ``execution``
(attempt lifecycle), ``lease`` (single-owner coordination), ``manifests``
(frozen evidence), ``recovery`` (deterministic resume/reconcile inspection), and
``router`` (the legal next stage). It owns exactly one privileged
responsibility - persisting ``workflow-state.yaml`` - and reuses the existing
domain validators unchanged.

Design rulings honoured here:

* RE9 - the runner is orchestration only. It carries no client-specific
  business logic and never approves review/QA/production decisions.
* RE5 - evidence (manifest/audit) is persisted before the canonical state
  pointer, and the runner is the only runtime module that writes
  ``workflow-state.yaml`` (the one-time initializer writes it at creation).
* RE11 - no queue, daemon, or distributed machinery: every operation is a
  synchronous, deterministic function of repository state plus an injected
  clock.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from tooling.workflow.contracts import load_stage_contract
from tooling.workflow.execution import (
    acquire_execution_lease,
    complete_attempt,
    completion_state_transition,
    fail_attempt,
    iso_timestamp,
    prior_manifests,
    reclaim_expired_lease,
    record_checkpoint,
    start_attempt,
)
from tooling.workflow.lease import (
    WorkflowLease,
    WorkflowLeaseOwnershipError,
    acquire_lease,
    is_expired,
    load_lease,
    renew_lease,
)
from tooling.workflow.manifests import (
    ExecutionManifest,
    ValidatorEvidence,
    load_manifest,
    manifest_path,
    validate_manifest,
    write_manifest_create_only,
)
from tooling.workflow.recovery import RecoveryAction, RecoveryDecision, inspect_recovery
from tooling.workflow.router import next_stage
from tooling.workflow.state import load_state, save_state_atomic


STATE_FILENAME = "workflow-state.yaml"


class WorkflowRunnerError(RuntimeError):
    """Raised when the runner cannot safely perform the requested operation."""


class RecoveryRequired(WorkflowRunnerError):
    """Raised when resume is not safe; the caller must reconcile or block."""


class WorkflowBlocked(WorkflowRunnerError):
    """Raised on a BLOCK decision (pointer ahead of evidence / false completion)."""


@dataclass(frozen=True)
class WorkflowRunStatus:
    """A read-only snapshot of the client's workflow reality."""

    client_id: str
    current_stage: str
    status: str
    completed: tuple[str, ...]
    skipped: tuple[str, ...]
    pending: tuple[str, ...]
    active_run_id: str | None
    attempt: int | None
    stage_status: str | None
    last_checkpoint: str | None
    lease_owner: str | None
    lease_expires_at: str | None
    lease_expired: bool
    recovery_action: str
    recovery_reason: str
    next_stage: str | None
    next_status: str
    next_reason: str | None
    manifest_ref: str | None


@dataclass(frozen=True)
class StageRun:
    """The outcome of one runner operation: post-write status + evidence."""

    status: WorkflowRunStatus
    manifest: ExecutionManifest | None
    lease: WorkflowLease | None


def _state_path(client_dir: Path) -> Path:
    return Path(client_dir) / STATE_FILENAME


def _resolve_now(now: datetime | None) -> datetime:
    if now is None:
        return datetime.now(timezone.utc)
    if now.tzinfo is None:
        return now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc)


def _entry_for(state: Mapping, stage: str) -> dict:
    stage_state = state.get("stage_state") or {}
    entry = stage_state.get(stage) if isinstance(stage_state, Mapping) else None
    return dict(entry) if isinstance(entry, Mapping) else {}


def _build_status(
    root: Path, client_dir: Path, state: dict, *, now: datetime
) -> WorkflowRunStatus:
    """Compose the read-only status from state, lease, recovery, and router."""
    lease = load_lease(state)
    recovery = inspect_recovery(root, client_dir, state, now=now)
    routed = next_stage(root, client_dir, state)
    stage = state["current_stage"]
    entry = _entry_for(state, stage)
    return WorkflowRunStatus(
        client_id=state["client_id"],
        current_stage=stage,
        status=state["status"],
        completed=tuple(state.get("completed") or ()),
        skipped=tuple(
            item["stage"] for item in (state.get("skipped") or ())
        ),
        pending=tuple(state.get("pending") or ()),
        active_run_id=state.get("run_id"),
        attempt=entry.get("attempt"),
        stage_status=entry.get("status"),
        last_checkpoint=entry.get("last_checkpoint"),
        lease_owner=lease.owner if lease is not None else None,
        lease_expires_at=lease.expires_at if lease is not None else None,
        lease_expired=bool(lease is not None and is_expired(lease, now=now)),
        recovery_action=recovery.action.value,
        recovery_reason=recovery.reason,
        next_stage=routed.get("stage"),
        next_status=routed.get("status"),
        next_reason=routed.get("reason"),
        manifest_ref=entry.get("artifact_manifest_ref"),
    )


def _stage_run(
    root: Path,
    client_dir: Path,
    *,
    now: datetime,
    manifest: ExecutionManifest | None = None,
) -> StageRun:
    """Re-read persisted reality so every caller sees post-write state."""
    return StageRun(
        status=inspect_client(root, client_dir, now=now),
        manifest=manifest,
        lease=load_lease(load_state(_state_path(client_dir))),
    )


def _find_manifest(
    client_dir: Path, *, run_id: str, stage: str, status: str | None = None
) -> ExecutionManifest:
    """Return the manifest for *run_id*/*stage* (optionally of *status*)."""
    candidates = [
        manifest
        for manifest in prior_manifests(client_dir, stage)
        if manifest.run_id == run_id
    ]
    if status is not None:
        candidates = [item for item in candidates if item.status == status]
    if not candidates:
        label = f"{status} " if status else ""
        raise WorkflowRunnerError(
            f"no {label}manifest for run {run_id!r} at stage {stage!r}"
        )
    return candidates[-1]


def _require_lease_owner(state: Mapping, *, actor: str) -> WorkflowLease:
    """Checkpointing mutates evidence, so it must be lease-owned (spec \u00a76)."""
    lease = load_lease(state)
    if lease is None:
        raise WorkflowLeaseOwnershipError(
            "checkpointing requires an active client workflow lease"
        )
    if lease.owner != actor:
        raise WorkflowLeaseOwnershipError(
            f"lease {lease.lease_id} is owned by {lease.owner!r}, not {actor!r}"
        )
    return lease


def inspect_client(
    root: Path, client_dir: Path, *, now: datetime | None = None
) -> WorkflowRunStatus:
    """Return the client's workflow reality without writing anything.

    Loads and normalizes state, reads the lease, computes the deterministic
    recovery decision, and routes the next legal stage. No file is written.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(now)
    state = load_state(_state_path(client_dir))
    return _build_status(root, client_dir, state, now=moment)


def start_stage(
    root: Path,
    client_dir: Path,
    *,
    actor: str,
    source_commit_sha: str,
    now: datetime | None = None,
    ttl_seconds: int = 1800,
) -> StageRun:
    """Start (or idempotently reuse/resume) the current stage attempt."""
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(now)
    path = _state_path(client_dir)
    state = load_state(path)

    new_state, manifest = start_attempt(
        root,
        client_dir,
        state,
        actor=actor,
        source_commit_sha=source_commit_sha,
        now=moment,
        lease_ttl_seconds=ttl_seconds,
    )
    # A REUSE/RESUME decision returns the state unchanged: never re-persist it as
    # a fresh attempt. Only a genuine new attempt changes the canonical pointer.
    if new_state != state:
        save_state_atomic(path, new_state)
    return _stage_run(root, client_dir, now=moment, manifest=manifest)


def checkpoint_stage(
    root: Path,
    client_dir: Path,
    *,
    run_id: str,
    checkpoint: str,
    actor: str,
    at: datetime | None = None,
) -> StageRun:
    """Record a contract-declared checkpoint on the active attempt."""
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(at)
    path = _state_path(client_dir)
    state = load_state(path)
    stage = state["current_stage"]

    manifest = _find_manifest(
        client_dir, run_id=run_id, stage=stage, status="in_progress"
    )
    _require_lease_owner(state, actor=actor)
    contract = load_stage_contract(root, stage)
    updated = record_checkpoint(manifest, checkpoint, at=iso_timestamp(moment), contract=contract)

    # Evidence first: the checkpointed manifest is durable before the pointer.
    write_manifest_create_only(
        manifest_path(client_dir, updated.run_id, updated.attempt), updated
    )
    stage_state = dict(state.get("stage_state") or {})
    entry = dict(stage_state.get(stage) or {})
    entry["attempt"] = updated.attempt
    entry["status"] = "in_progress"
    entry["last_checkpoint"] = checkpoint
    stage_state[stage] = entry
    state["stage_state"] = stage_state
    save_state_atomic(path, state)
    return _stage_run(root, client_dir, now=moment, manifest=updated)


def fail_stage(
    root: Path,
    client_dir: Path,
    *,
    run_id: str,
    reason: str,
    actor: str,
    at: datetime | None = None,
) -> StageRun:
    """Record durable failure evidence without advancing the stage pointer."""
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(at)
    path = _state_path(client_dir)
    state = load_state(path)
    stage = state["current_stage"]

    manifest = _find_manifest(
        client_dir, run_id=run_id, stage=stage, status="in_progress"
    )
    new_state, failed = fail_attempt(
        client_dir, state, manifest, reason=reason, at=iso_timestamp(moment), actor=actor
    )
    save_state_atomic(path, new_state)
    return _stage_run(root, client_dir, now=moment, manifest=failed)


def complete_stage(
    root: Path,
    client_dir: Path,
    *,
    run_id: str,
    actor: str,
    validator_results: Sequence[ValidatorEvidence],
    at: datetime | None = None,
) -> StageRun:
    """Freeze completion evidence, then advance the canonical pointer."""
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(at)
    path = _state_path(client_dir)
    state = load_state(path)
    stage = state["current_stage"]

    manifest = _find_manifest(
        client_dir, run_id=run_id, stage=stage, status="in_progress"
    )
    new_state, frozen = complete_attempt(
        root,
        client_dir,
        state,
        manifest,
        validator_results=validator_results,
        at=iso_timestamp(moment),
        actor=actor,
    )
    save_state_atomic(path, new_state)
    return _stage_run(root, client_dir, now=moment, manifest=frozen)


def _reclaim_expired_lease(
    client_dir: Path,
    state: dict,
    *,
    actor: str,
    run_id: str,
    now: datetime,
    ttl_seconds: int,
) -> tuple[dict, WorkflowLease]:
    """Reclaim an expired lease through the shared, audited execution helper."""
    return acquire_execution_lease(
        client_dir,
        state,
        actor=actor,
        run_id=run_id,
        now=now,
        ttl_seconds=ttl_seconds,
    )


def _resume_existing(
    root: Path,
    client_dir: Path,
    state: dict,
    decision: RecoveryDecision,
    *,
    actor: str,
    now: datetime,
    ttl_seconds: int,
) -> StageRun:
    """Return the existing in-progress attempt, ensuring the actor owns it."""
    path = _state_path(client_dir)
    manifest = load_manifest(
        manifest_path(client_dir, decision.run_id, decision.attempt)
    )
    lease = load_lease(state)

    if lease is None:
        new_state, _ = acquire_lease(
            state,
            owner=actor,
            run_id=decision.run_id,
            now=now,
            ttl_seconds=ttl_seconds,
        )
        save_state_atomic(path, new_state)
    elif lease.owner != actor:
        raise RecoveryRequired(
            f"lease {lease.lease_id} is held by {lease.owner!r}, not {actor!r}"
        )
    elif is_expired(lease, now=now):
        new_state, _ = _reclaim_expired_lease(
            client_dir,
            state,
            actor=actor,
            run_id=decision.run_id,
            now=now,
            ttl_seconds=ttl_seconds,
        )
        save_state_atomic(path, new_state)
    else:
        new_state, _ = renew_lease(state, lease, now=now, ttl_seconds=ttl_seconds)
        save_state_atomic(path, new_state)
    return _stage_run(root, client_dir, now=now, manifest=manifest)


def resume_stage(
    root: Path,
    client_dir: Path,
    *,
    actor: str,
    source_commit_sha: str,
    now: datetime | None = None,
    ttl_seconds: int = 1800,
) -> StageRun:
    """Resume, reconcile, retry, or refuse, based on deterministic recovery."""
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(now)
    state = load_state(_state_path(client_dir))
    decision = inspect_recovery(root, client_dir, state, now=moment)

    if decision.action is RecoveryAction.BLOCK:
        raise WorkflowBlocked(f"cannot resume: {decision.reason}")
    if decision.action is RecoveryAction.RECONCILE_STATE:
        return reconcile_state(root, client_dir, actor=actor, now=moment)
    if decision.action is RecoveryAction.RESUME:
        return _resume_existing(
            root,
            client_dir,
            state,
            decision,
            actor=actor,
            now=moment,
            ttl_seconds=ttl_seconds,
        )
    return start_stage(
        root,
        client_dir,
        actor=actor,
        source_commit_sha=source_commit_sha,
        now=moment,
        ttl_seconds=ttl_seconds,
    )


def reconcile_state(
    root: Path,
    client_dir: Path,
    *,
    actor: str,
    now: datetime | None = None,
) -> StageRun:
    """Advance a stale pointer for durable completed evidence, exactly once.

    Reconciliation is a state-mutating operation, so it obeys the same lease
    policy as every other mutation: a live lease owned by someone else blocks,
    an expired lease is reclaimed through the audited recovery path, and the
    reconciler never clears an ownership it does not hold.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    moment = _resolve_now(now)
    path = _state_path(client_dir)
    state = load_state(path)

    decision = inspect_recovery(root, client_dir, state, now=moment)
    if decision.action is not RecoveryAction.RECONCILE_STATE:
        # Nothing to reconcile: idempotent, and never a write.
        return _stage_run(root, client_dir, now=moment, manifest=None)

    manifest = load_manifest(
        manifest_path(client_dir, decision.run_id, decision.attempt)
    )
    errors = validate_manifest(manifest.to_dict())
    if errors:
        raise WorkflowRunnerError(
            "cannot reconcile an invalid manifest: " + "; ".join(errors)
        )
    if manifest.status != "completed":
        raise WorkflowRunnerError(
            f"cannot reconcile a {manifest.status!r} manifest; completion evidence "
            "is required"
        )

    lease = load_lease(state)
    if lease is not None and lease.owner != actor and not is_expired(lease, now=moment):
        raise RecoveryRequired(
            f"lease {lease.lease_id} is held by {lease.owner!r}, not {actor!r}"
        )
    # An expired foreign lease is reclaimed through the shared audited path; a
    # live lease owned by the actor (or no lease at all) passes through.
    state, _ = reclaim_expired_lease(
        client_dir, state, actor=actor, run_id=decision.run_id, now=moment
    )

    at = manifest.completed_at or iso_timestamp(moment)
    new_state = completion_state_transition(
        root, state, manifest, at=at, actor=actor, clear_lease=True
    )
    save_state_atomic(path, new_state)
    return _stage_run(root, client_dir, now=moment, manifest=manifest)
