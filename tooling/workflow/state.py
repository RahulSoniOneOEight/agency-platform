from __future__ import annotations

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


def initial_state(client_id: str) -> dict[str, Any]:
    return {
        "version": 1,
        "client_id": client_id,
        "current_stage": "client-intake",
        "status": "not_started",
        "completed": [],
        "skipped": [],
        "pending": list(STAGES),
        "blocked": [],
        "last_updated": date.today().isoformat(),
    }


def load_state(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError(f"workflow state must be a mapping: {path}")
    return data


def save_state(path: Path, state: dict[str, Any]) -> None:
    state = dict(state)
    state["last_updated"] = date.today().isoformat()
    path.write_text(yaml.safe_dump(state, sort_keys=False), encoding="utf-8")
