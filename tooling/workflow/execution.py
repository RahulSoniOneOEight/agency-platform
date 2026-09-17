"""Validator-gated stage transitions over the fixed eight-stage workflow.

The runtime is a deterministic, artifact-aware state machine. A stage attempt
starts only after its contract prerequisites hold, records checkpoints declared
by the contract, and completes only when the contract's produced artifacts
exist and its required validators passed. Evidence (the frozen manifest) is
written to disk before the caller persists the advanced state.
"""

from __future__ import annotations

import copy
import hashlib
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path

from tooling.workflow.audit import append_audit_record, make_recovery_record
from tooling.workflow.contracts import StageContract, load_stage_contract
from tooling.workflow.lease import (
    WorkflowLease,
    WorkflowLeaseOwnershipError,
    acquire_lease,
    is_expired,
    load_lease,
    reconcile_expired_lease,
    release_lease,
)
from tooling.workflow.manifests import (
    EXECUTIONS_DIR_NAME,
    ArtifactRef,
    ExecutionManifest,
    ManifestError,
    StageCompletionGateFailed,
    ValidatorEvidence,
    artifacts_for_paths,
    input_identity,
    load_manifest,
    manifest_path,
    manifest_relpath,
    write_manifest_create_only,
)


class StagePrerequisiteFailed(RuntimeError):
    """Raised when a stage's declared prerequisites are not satisfied."""


class StageValidationFailed(RuntimeError):
    """Raised when a stage's produced artifacts are missing at completion."""


class IllegalStageTransition(RuntimeError):
    """Raised when a checkpoint is not declared by the stage contract."""


def _iso(now: datetime) -> str:
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _default_run_id(client_id: str, stage: str, attempt: int, now: datetime) -> str:
    seed = f"{client_id}:{stage}:{attempt}"
    digest = hashlib.sha1(seed.encode("utf-8")).hexdigest()[:8]
    return f"wf-{client_id}-{now:%Y%m%dT%H%M%SZ}-{digest}"


def _existing_attempts(client_dir: Path, run_id: str, stage: str) -> list[int]:
    """Deprecated: attempt numbers now come from :func:`decide_idempotency`.

    Retained as a thin reader for callers that only need the attempt numbers of
    one run directory; the idempotency path no longer depends on it.
    """
    run_dir = Path(client_dir) / "workflow" / "executions" / run_id
    attempts: list[int] = []
    if not run_dir.is_dir():
        return attempts
    for path in sorted(run_dir.glob("attempt-*.yaml")):
        try:
            manifest = load_manifest(path)
        except ManifestError:
            continue
        if manifest.stage == stage:
            attempts.append(manifest.attempt)
    return attempts


class IdempotencyAction(str, Enum):
    """Content-based decision for a stage that is about to start (RE7)."""

    REUSE = "reuse"
    RESUME = "resume"
    NEW_ATTEMPT = "new_attempt"


@dataclass(frozen=True)
class IdempotencyDecision:
    action: IdempotencyAction
    run_id: str
    attempt: int
    reason: str


def _manifest_sort_key(manifest: ExecutionManifest) -> tuple[str, str, int]:
    return (manifest.started_at, manifest.run_id, manifest.attempt)


def prior_manifests(client_dir: Path, stage: str) -> list[ExecutionManifest]:
    """Return every loadable manifest for *stage*, oldest first.

    Ordering is deterministic (``started_at``, ``run_id``, ``attempt``) and never
    depends on wall-clock time or filesystem enumeration order.
    """
    executions = Path(client_dir) / "workflow" / EXECUTIONS_DIR_NAME
    manifests: list[ExecutionManifest] = []
    if executions.is_dir():
        for run_dir in sorted(executions.iterdir()):
            if not run_dir.is_dir():
                continue
            for path in sorted(run_dir.glob("attempt-*.yaml")):
                try:
                    manifest = load_manifest(path)
                except ManifestError:
                    continue
                if manifest.stage == stage:
                    manifests.append(manifest)
    manifests.sort(key=_manifest_sort_key)
    return manifests


def decide_idempotency(
    contract: StageContract,
    prior: Sequence[ExecutionManifest],
    current_inputs: Sequence[ArtifactRef],
    *,
    run_id: str | None = None,
) -> IdempotencyDecision:
    """Decide REUSE / RESUME / NEW_ATTEMPT from content identity alone (RE7).

    Pure: no I/O, no clock. ``RESUME`` outranks ``REUSE``; only manifests for
    ``contract.stage`` are considered. A prior ``failed`` attempt (or changed
    input bytes) yields ``NEW_ATTEMPT`` with the next attempt number.
    """
    stage_prior = sorted(
        (manifest for manifest in prior if manifest.stage == contract.stage),
        key=_manifest_sort_key,
    )
    current_identity = input_identity(current_inputs)

    if not stage_prior:
        return IdempotencyDecision(
            action=IdempotencyAction.NEW_ATTEMPT,
            run_id=run_id or "",
            attempt=1,
            reason="no prior attempts for stage",
        )

    latest = stage_prior[-1]
    if (
        latest.status == "in_progress"
        and latest.checkpoints
        and (run_id is None or latest.run_id == run_id)
    ):
        return IdempotencyDecision(
            action=IdempotencyAction.RESUME,
            run_id=latest.run_id,
            attempt=latest.attempt,
            reason="most recent attempt is in progress with a durable checkpoint",
        )

    completed = [manifest for manifest in stage_prior if manifest.status == "completed"]
    if completed:
        candidate = completed[-1]
        if input_identity(candidate.inputs) == current_identity:
            return IdempotencyDecision(
                action=IdempotencyAction.REUSE,
                run_id=candidate.run_id,
                attempt=candidate.attempt,
                reason="completed attempt matches the current inputs",
            )

    return IdempotencyDecision(
        action=IdempotencyAction.NEW_ATTEMPT,
        run_id=run_id or "",
        attempt=1 + max(manifest.attempt for manifest in stage_prior),
        reason="no reusable completed attempt for the current inputs",
    )


def _contract_input_refs(
    client_dir: Path, contract: StageContract
) -> tuple[ArtifactRef, ...]:
    """Return the existing contract-relevant refs (``requires`` + ``produces``).

    Missing files are omitted rather than recorded with an empty digest: an
    in-progress manifest must stay schema-valid, and the not-yet-produced
    outputs are merged in when the attempt completes. Identity comparison is
    order-independent, so this stays deterministic across the attempt lifecycle.
    """
    relevant = tuple(contract.requires_artifacts) + tuple(contract.produces)
    return tuple(ref for ref in artifacts_for_paths(client_dir, relevant) if ref.sha256)


def _with_input_refs(
    manifest: ExecutionManifest, refs: Sequence[ArtifactRef]
) -> ExecutionManifest:
    """Return *manifest* with *refs* merged into its inputs by path."""
    by_path = {ref.path: ref for ref in manifest.inputs}
    order = [ref.path for ref in manifest.inputs]
    for ref in refs:
        if not ref.sha256:
            continue
        if ref.path not in by_path:
            order.append(ref.path)
        by_path[ref.path] = ref
    return replace(manifest, inputs=tuple(by_path[path] for path in order))


def _require_prerequisites(
    client_dir: Path, state: dict, contract: StageContract
) -> None:
    completed = set(state.get("completed", []))
    missing_stages = [stage for stage in contract.requires_stages if stage not in completed]
    if missing_stages:
        raise StagePrerequisiteFailed(
            f"{contract.stage}: unmet prerequisite stages: {', '.join(missing_stages)}"
        )
    missing_artifacts = [
        path for path in contract.requires_artifacts if not (client_dir / path).exists()
    ]
    if missing_artifacts:
        raise StagePrerequisiteFailed(
            f"{contract.stage}: missing prerequisite artifacts: {', '.join(missing_artifacts)}"
        )


def _audit_path(client_dir: Path) -> Path:
    return Path(client_dir) / "workflow" / "audit.jsonl"


def _require_active_lease(state: dict, *, actor: str) -> WorkflowLease:
    """A state-mutating execution must hold the client lease (spec §6)."""
    lease = load_lease(state)
    if lease is None:
        raise WorkflowLeaseOwnershipError(
            "state-mutating execution requires an active client workflow lease"
        )
    if lease.owner != actor:
        raise WorkflowLeaseOwnershipError(
            f"lease {lease.lease_id} is owned by {lease.owner!r}, not {actor!r}"
        )
    return lease


def _acquire_execution_lease(
    client_dir: Path,
    state: dict,
    *,
    actor: str,
    run_id: str,
    now: datetime,
    ttl_seconds: int,
) -> tuple[dict, WorkflowLease]:
    """Acquire the lease, deterministically recovering an expired one first.

    Reclaiming an expired lease is the only takeover path, and it records a
    durable recovery audit event so the reclaim is never silent.
    """
    existing = load_lease(state)
    if existing is not None and is_expired(existing, now=now):
        recovered_state, expired = reconcile_expired_lease(state, now=now)
        if expired is not None:
            append_audit_record(
                _audit_path(client_dir),
                make_recovery_record(
                    actor=actor,
                    at=_iso(now),
                    summary=f"reclaimed expired lease {expired.lease_id}",
                    reason="lease expired before completion",
                    stage=state.get("current_stage"),
                    run_id=expired.run_id,
                    previous_state={"lease_id": expired.lease_id, "owner": expired.owner},
                    requested_state={"owner": actor, "run_id": run_id},
                ),
            )
        state = recovered_state
    return acquire_lease(
        state, owner=actor, run_id=run_id, now=now, ttl_seconds=ttl_seconds
    )


def start_attempt(
    root: Path,
    client_dir: Path,
    state: dict,
    *,
    actor: str,
    source_commit_sha: str,
    stage: str | None = None,
    run_id: str | None = None,
    now: datetime | None = None,
    inputs: Sequence[ArtifactRef] | None = None,
    lease_ttl_seconds: int = 1800,
) -> tuple[dict, ExecutionManifest]:
    stage = stage or state["current_stage"]
    contract = load_stage_contract(root, stage)
    _require_prerequisites(client_dir, state, contract)

    now = now or datetime.now(timezone.utc)
    client_id = state.get("client_id") or Path(client_dir).name

    if inputs is None:
        current_inputs = _contract_input_refs(client_dir, contract)
    else:
        current_inputs = tuple(inputs)

    prior = prior_manifests(client_dir, stage)
    decision = decide_idempotency(contract, prior, current_inputs, run_id=run_id)

    if decision.action is IdempotencyAction.REUSE:
        existing = load_manifest(
            manifest_path(client_dir, decision.run_id, decision.attempt)
        )
        return copy.deepcopy(state), existing
    if decision.action is IdempotencyAction.RESUME:
        existing = load_manifest(
            manifest_path(client_dir, decision.run_id, decision.attempt)
        )
        return copy.deepcopy(state), existing

    attempt = decision.attempt
    if run_id is None:
        resolved_run_id = _default_run_id(client_id, stage, attempt, now)
    else:
        resolved_run_id = run_id

    # The lease is acquired only for a genuinely new attempt, and always before
    # any evidence is written: a second owner is rejected here with no mutation.
    leased_state, _ = _acquire_execution_lease(
        client_dir,
        state,
        actor=actor,
        run_id=resolved_run_id,
        now=now,
        ttl_seconds=lease_ttl_seconds,
    )

    started_at = _iso(now)
    manifest = ExecutionManifest.start(
        run_id=resolved_run_id,
        client_id=client_id,
        stage=stage,
        attempt=attempt,
        source_commit_sha=source_commit_sha,
        started_at=started_at,
        inputs=current_inputs,
    )
    write_manifest_create_only(manifest_path(client_dir, resolved_run_id, attempt), manifest)

    new_state = leased_state
    new_state["run_id"] = resolved_run_id
    new_state["status"] = "in_progress"
    stage_state = dict(new_state.get("stage_state") or {})
    stage_state[stage] = {
        "attempt": attempt,
        "status": "in_progress",
        "started_at": started_at,
        "last_checkpoint": None,
        "artifact_manifest_ref": manifest_relpath(resolved_run_id, attempt),
    }
    new_state["stage_state"] = stage_state
    return new_state, manifest


def record_checkpoint(
    manifest: ExecutionManifest, name: str, *, at: str, contract: StageContract
) -> ExecutionManifest:
    if name not in contract.checkpoints:
        raise IllegalStageTransition(
            f"checkpoint {name!r} is not declared for stage {contract.stage!r}"
        )
    return manifest.with_checkpoint(name, at=at)


def fail_attempt(
    client_dir: Path, state: dict, manifest: ExecutionManifest, *, reason: str, at: str
) -> tuple[dict, ExecutionManifest]:
    _require_attempt_matches_state(client_dir, state, manifest)
    if load_lease(state) is None:
        raise WorkflowLeaseOwnershipError(
            "state-mutating execution requires an active client workflow lease"
        )
    failed = manifest.fail(reason=reason, at=at)
    write_manifest_create_only(
        manifest_path(client_dir, failed.run_id, failed.attempt), failed
    )
    new_state = copy.deepcopy(state)
    stage_state = dict(new_state.get("stage_state") or {})
    entry = dict(stage_state.get(manifest.stage) or {})
    entry["status"] = "failed"
    entry["failed_at"] = at
    stage_state[manifest.stage] = entry
    new_state["stage_state"] = stage_state
    # Failure evidence is durable before ownership is released.
    new_state["active_lease"] = None
    return new_state, failed


def release_after_completion(state: dict, lease: WorkflowLease) -> dict:
    """Release the lease once the canonical state transition is persisted.

    Ordering contract (RE5): evidence -> state pointer -> lease release. This
    thin wrapper exists so that the release step is expressible as a single call
    and always routes through :func:`lease.release_lease`, which enforces the
    lease id + owner match before clearing ``active_lease``.
    """
    return release_lease(state, lease)


def _require_attempt_matches_state(
    client_dir: Path, state: dict, manifest: ExecutionManifest
) -> None:
    """Reject a manifest that does not belong to the state it claims to advance.

    The canonical stage pointer may only advance for the stage the state is
    currently on, for the state's active run, for this client. Without this
    guard a directly supplied manifest could skip stages or cross clients.
    """
    if manifest.stage != state.get("current_stage"):
        raise IllegalStageTransition(
            f"manifest stage {manifest.stage!r} is not the current stage "
            f"{state.get('current_stage')!r}"
        )
    if manifest.run_id != state.get("run_id"):
        raise IllegalStageTransition(
            f"manifest run {manifest.run_id!r} is not the active run "
            f"{state.get('run_id')!r}"
        )
    expected_client = state.get("client_id") or Path(client_dir).name
    if manifest.client_id != expected_client:
        raise IllegalStageTransition(
            f"manifest client {manifest.client_id!r} does not match {expected_client!r}"
        )


def complete_attempt(
    root: Path,
    client_dir: Path,
    state: dict,
    manifest: ExecutionManifest,
    *,
    validator_results: Sequence[ValidatorEvidence],
    at: str,
    actor: str,
) -> tuple[dict, ExecutionManifest]:
    _require_attempt_matches_state(client_dir, state, manifest)
    _require_active_lease(state, actor=actor)
    contract = load_stage_contract(root, manifest.stage)

    missing_artifacts = [
        path for path in contract.produces if not (client_dir / path).exists()
    ]
    if missing_artifacts:
        raise StageValidationFailed(
            f"{manifest.stage}: missing produced artifacts: {', '.join(missing_artifacts)}"
        )

    passed = {evidence.name for evidence in validator_results if evidence.status == "passed"}
    missing_validators = [name for name in contract.validators if name not in passed]
    if missing_validators:
        raise StageCompletionGateFailed(
            f"{manifest.stage}: required validators not passed: {', '.join(missing_validators)}"
        )

    produced_refs = artifacts_for_paths(client_dir, contract.produces)
    frozen = _with_input_refs(manifest, produced_refs).with_validators(
        validator_results
    ).complete(at=at, required_validators=contract.validators)
    write_manifest_create_only(
        manifest_path(client_dir, frozen.run_id, frozen.attempt), frozen
    )

    new_state = copy.deepcopy(state)
    completed = list(new_state.get("completed", []))
    if manifest.stage not in completed:
        completed.append(manifest.stage)
    new_state["completed"] = completed
    pending = list(new_state.get("pending", []))
    new_state["pending"] = [stage for stage in pending if stage != manifest.stage]

    stage_state = dict(new_state.get("stage_state") or {})
    entry = dict(stage_state.get(manifest.stage) or {})
    entry["attempt"] = frozen.attempt
    entry["status"] = "complete"
    entry["completed_at"] = at
    entry["last_checkpoint"] = frozen.checkpoints[-1].name if frozen.checkpoints else None
    entry["artifact_manifest_ref"] = manifest_relpath(frozen.run_id, frozen.attempt)
    stage_state[manifest.stage] = entry
    new_state["stage_state"] = stage_state

    from_stage = state["current_stage"]
    if contract.next_stages:
        to_stage = contract.next_stages[0]
        new_state["current_stage"] = to_stage
        new_state["status"] = "in_progress"
    else:
        to_stage = manifest.stage
        new_state["status"] = "complete"
    new_state["last_transition"] = {
        "from": from_stage,
        "to": to_stage,
        "at": at,
        "actor": actor,
    }
    # Ownership is released only after the evidence is durable and the canonical
    # transition is computed (RE5 ordering: evidence -> state pointer -> release).
    new_state["active_lease"] = None
    return new_state, frozen
