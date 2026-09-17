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
from datetime import datetime, timezone
from pathlib import Path

from tooling.workflow.contracts import StageContract, load_stage_contract
from tooling.workflow.manifests import (
    ArtifactRef,
    ExecutionManifest,
    ManifestError,
    StageCompletionGateFailed,
    ValidatorEvidence,
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
    inputs: Sequence[ArtifactRef] = (),
) -> tuple[dict, ExecutionManifest]:
    stage = stage or state["current_stage"]
    contract = load_stage_contract(root, stage)
    _require_prerequisites(client_dir, state, contract)

    now = now or datetime.now(timezone.utc)
    client_id = state.get("client_id") or Path(client_dir).name
    if run_id is None:
        attempt = 1
        resolved_run_id = _default_run_id(client_id, stage, attempt, now)
    else:
        resolved_run_id = run_id
        attempt = 1 + max(_existing_attempts(client_dir, resolved_run_id, stage), default=0)

    started_at = _iso(now)
    manifest = ExecutionManifest.start(
        run_id=resolved_run_id,
        client_id=client_id,
        stage=stage,
        attempt=attempt,
        source_commit_sha=source_commit_sha,
        started_at=started_at,
        inputs=inputs,
    )
    write_manifest_create_only(manifest_path(client_dir, resolved_run_id, attempt), manifest)

    new_state = copy.deepcopy(state)
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
    state: dict, manifest: ExecutionManifest, *, reason: str, at: str
) -> tuple[dict, ExecutionManifest]:
    new_state = copy.deepcopy(state)
    stage_state = dict(new_state.get("stage_state") or {})
    entry = dict(stage_state.get(manifest.stage) or {})
    entry["status"] = "failed"
    entry["failed_at"] = at
    stage_state[manifest.stage] = entry
    new_state["stage_state"] = stage_state
    return new_state, manifest.fail(reason=reason, at=at)


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

    frozen = manifest.with_validators(validator_results).complete(
        at=at, required_validators=contract.validators
    )
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
    return new_state, frozen
