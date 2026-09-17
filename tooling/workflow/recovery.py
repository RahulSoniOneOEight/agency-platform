"""Deterministic recovery inspection for interrupted workflow executions.

``inspect_recovery`` is a pure read: it never writes state, manifests, or the
lease. It answers, from repository evidence alone, what a fresh session should
do next. The ordering rule (RE5) is evidence first, canonical pointer second: a
completed manifest whose state pointer was not advanced yields
``RECONCILE_STATE``; a pointer that claims completion without evidence yields
``BLOCK``.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any

from tooling.workflow.execution import prior_manifests
from tooling.workflow.lease import is_expired, load_lease
from tooling.workflow.state import STAGES


class RecoveryAction(str, Enum):
    NONE = "none"
    RESUME = "resume"
    RETRY = "retry"
    RECONCILE_STATE = "reconcile_state"
    BLOCK = "block"


@dataclass(frozen=True)
class RecoveryDecision:
    action: RecoveryAction
    stage: str
    run_id: str | None
    attempt: int | None
    checkpoint: str | None
    reason: str


def _stage_index(stage: Any) -> int:
    return STAGES.index(stage) if stage in STAGES else -1


def _last_checkpoint(manifest: Any) -> str | None:
    return manifest.checkpoints[-1].name if manifest.checkpoints else None


def _unfinished_work(state: Mapping[str, Any]) -> bool:
    if state.get("status") == "complete":
        return False
    stage = state.get("current_stage")
    if stage in set(state.get("completed") or []):
        return False
    stage_state = state.get("stage_state") or {}
    entry = stage_state.get(stage) if isinstance(stage_state, Mapping) else None
    if isinstance(entry, Mapping) and entry.get("status") == "complete":
        return False
    return True


def inspect_recovery(
    root: Path,
    client_dir: Path,
    state: dict[str, Any],
    *,
    now: datetime,
) -> RecoveryDecision:
    """Return the next deterministic recovery action for *state*.

    First match wins. The function may propose reconciliation but never mutates
    persisted state or files.
    """
    client_dir = Path(client_dir)
    stage = state.get("current_stage")
    stage_state = state.get("stage_state") or {}

    # Row 1: a stage that claims completion without a completed manifest is a lie.
    if isinstance(stage_state, Mapping):
        for name in sorted(stage_state):
            entry = stage_state.get(name)
            if isinstance(entry, Mapping) and entry.get("status") == "complete":
                has_evidence = any(
                    manifest.status == "completed"
                    for manifest in prior_manifests(client_dir, name)
                )
                if not has_evidence:
                    return RecoveryDecision(
                        action=RecoveryAction.BLOCK,
                        stage=name,
                        run_id=None,
                        attempt=None,
                        checkpoint=None,
                        reason="state claims complete without evidence",
                    )

    current = prior_manifests(client_dir, stage) if stage else []
    completed = [manifest for manifest in current if manifest.status == "completed"]
    entry = stage_state.get(stage) if isinstance(stage_state, Mapping) else None
    entry_complete = isinstance(entry, Mapping) and entry.get("status") == "complete"

    # Row 2: completed evidence exists but the canonical pointer is behind.
    if completed and not entry_complete:
        furthest = max(completed, key=lambda manifest: _stage_index(manifest.stage))
        return RecoveryDecision(
            action=RecoveryAction.RECONCILE_STATE,
            stage=furthest.stage,
            run_id=furthest.run_id,
            attempt=furthest.attempt,
            checkpoint=_last_checkpoint(furthest),
            reason="completed evidence exists but state is not advanced",
        )

    # Row 3: an in-progress attempt with a durable checkpoint can resume.
    resumable = [
        manifest
        for manifest in current
        if manifest.status == "in_progress" and manifest.checkpoints
    ]
    if resumable:
        latest = resumable[-1]
        return RecoveryDecision(
            action=RecoveryAction.RESUME,
            stage=stage,
            run_id=latest.run_id,
            attempt=latest.attempt,
            checkpoint=_last_checkpoint(latest),
            reason="in-progress attempt with a durable checkpoint",
        )

    # Row 4: an in-progress attempt without a checkpoint must restart.
    in_progress = [
        manifest for manifest in current if manifest.status == "in_progress"
    ]
    if in_progress:
        latest = in_progress[-1]
        return RecoveryDecision(
            action=RecoveryAction.RETRY,
            stage=stage,
            run_id=latest.run_id,
            attempt=latest.attempt,
            checkpoint=None,
            reason="in-progress attempt without a durable checkpoint",
        )

    # Row 5: an expired lease must be reconciled before work continues.
    lease = load_lease(state)
    if lease is not None and is_expired(lease, now=now) and _unfinished_work(state):
        return RecoveryDecision(
            action=RecoveryAction.RETRY,
            stage=stage,
            run_id=lease.run_id,
            attempt=None,
            checkpoint=None,
            reason="expired lease with unfinished work",
        )

    # Row 6: nothing to recover.
    return RecoveryDecision(
        action=RecoveryAction.NONE,
        stage=stage,
        run_id=None,
        attempt=None,
        checkpoint=None,
        reason="no recovery action required",
    )
