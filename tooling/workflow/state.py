"""Canonical workflow-state authority.

v2 is the canonical write format; v1 state stays readable through
deterministic normalization. All writes are atomic.
"""

from __future__ import annotations

import copy
import os
import tempfile
from collections.abc import Mapping
from datetime import date
from pathlib import Path
from typing import Any

import yaml


STAGES = [
    "client-intake",
    "resolve-intelligence",
    "resource-research",
    "generate-directions",
    "build-prototype",
    "visual-qa",
    "client-review",
    "productionize",
]

STATUSES = {"not_started", "in_progress", "blocked", "complete"}

WORKFLOW_STATUSES = set(STATUSES)

STAGE_ATTEMPT_STATUSES = {"not_started", "in_progress", "blocked", "failed", "complete"}

CURRENT_VERSION = 2

SUPPORTED_VERSIONS = {1, 2}

DEFAULT_WORKFLOW = "standard-agency"

CANONICAL_KEYS = [
    "version",
    "client_id",
    "workflow",
    "current_stage",
    "status",
    "run_id",
    "completed",
    "skipped",
    "pending",
    "blocked",
    "stage_state",
    "active_lease",
    "last_transition",
    "last_updated",
]


class WorkflowStateError(ValueError):
    """Raised when workflow state cannot be normalized to canonical v2."""


def _require_stage(value: Any, label: str) -> str:
    if not isinstance(value, str) or value not in STAGES:
        raise WorkflowStateError(f"invalid {label}: {value!r}")
    return value


def _require_stage_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise WorkflowStateError(f"{label} must be a list")
    for item in value:
        _require_stage(item, f"{label} entry")
    return copy.deepcopy(value)


def _require_skipped(value: Any) -> list[Any]:
    if not isinstance(value, list):
        raise WorkflowStateError("skipped must be a list")
    for item in value:
        if not isinstance(item, Mapping):
            raise WorkflowStateError(f"invalid skipped entry: {item!r}")
        _require_stage(item.get("stage"), "skipped stage")
        if not item.get("reason"):
            raise WorkflowStateError(f"skipped stage requires a reason: {item!r}")
    return copy.deepcopy(value)


def _normalize_stage_state(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, Mapping):
        raise WorkflowStateError("stage_state must be a mapping")
    normalized: dict[str, Any] = {}
    for stage, attempt in value.items():
        _require_stage(stage, "stage_state key")
        if not isinstance(attempt, Mapping):
            raise WorkflowStateError(f"stage_state[{stage!r}] must be a mapping")
        normalized[stage] = copy.deepcopy(attempt)
    return normalized


def _normalize_optional_mapping(value: Any, label: str) -> Any:
    if value is None:
        return None
    if not isinstance(value, Mapping):
        raise WorkflowStateError(f"{label} must be a mapping or null")
    return copy.deepcopy(value)


def normalize_state(data: Any, client_id: str | None = None) -> dict[str, Any]:
    if not isinstance(data, Mapping):
        raise WorkflowStateError("workflow state must be a mapping")

    version = data.get("version")
    if version not in SUPPORTED_VERSIONS:
        raise WorkflowStateError(f"unsupported workflow state version: {version!r}")

    state_client_id = data.get("client_id")
    if not isinstance(state_client_id, str) or not state_client_id:
        raise WorkflowStateError(f"invalid client_id: {state_client_id!r}")
    if client_id is not None and client_id != state_client_id:
        raise WorkflowStateError(
            f"client_id mismatch: expected {client_id!r}, found {state_client_id!r}"
        )

    current_stage = _require_stage(data.get("current_stage"), "current_stage")

    status = data.get("status")
    if status not in STATUSES:
        raise WorkflowStateError(f"invalid status: {status!r}")

    completed = _require_stage_list(data.get("completed", []), "completed")
    skipped = _require_skipped(data.get("skipped", []))
    blocked = _require_stage_list(data.get("blocked", []), "blocked")

    if "pending" in data:
        pending = _require_stage_list(data.get("pending"), "pending")
    else:
        settled = set(completed) | {item["stage"] for item in skipped}
        pending = [stage for stage in STAGES if stage not in settled]

    return {
        "version": CURRENT_VERSION,
        "client_id": state_client_id,
        "workflow": data.get("workflow") or DEFAULT_WORKFLOW,
        "current_stage": current_stage,
        "status": status,
        "run_id": data.get("run_id"),
        "completed": completed,
        "skipped": skipped,
        "pending": pending,
        "blocked": blocked,
        "stage_state": _normalize_stage_state(data.get("stage_state")),
        "active_lease": _normalize_optional_mapping(data.get("active_lease"), "active_lease"),
        "last_transition": _normalize_optional_mapping(
            data.get("last_transition"), "last_transition"
        ),
        "last_updated": data.get("last_updated") or date.today().isoformat(),
    }


def initial_state(client_id: str) -> dict[str, Any]:
    return {
        "version": CURRENT_VERSION,
        "client_id": client_id,
        "workflow": DEFAULT_WORKFLOW,
        "current_stage": "client-intake",
        "status": "not_started",
        "run_id": None,
        "completed": [],
        "skipped": [],
        "pending": list(STAGES),
        "blocked": [],
        "stage_state": {},
        "active_lease": None,
        "last_transition": None,
        "last_updated": date.today().isoformat(),
    }


def load_state(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return normalize_state(data)


def save_state_atomic(path: Path, state: dict[str, Any]) -> None:
    normalized = normalize_state(state)
    normalized["last_updated"] = date.today().isoformat()
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(
        dir=str(path.parent), prefix=f"{path.name}.", suffix=".tmp"
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            yaml.safe_dump(normalized, stream, sort_keys=False)
        os.replace(tmp_path, path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def save_state(path: Path, state: dict[str, Any]) -> None:
    save_state_atomic(path, state)
