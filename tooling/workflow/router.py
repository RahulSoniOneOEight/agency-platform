from __future__ import annotations

from pathlib import Path
from typing import Any

from tooling.workflow.state import STAGES


def _is_skipped(state: dict[str, Any], stage: str) -> bool:
    return any(item.get("stage") == stage and item.get("reason") for item in state.get("skipped", []))


def _directions_ready(client_dir: Path) -> bool:
    directions = client_dir / "directions"
    required = ["direction-a.yaml", "direction-b.yaml", "direction-c.yaml", "comparison.yaml"]
    return all((directions / name).exists() for name in required)


def _prototype_platform_installed(root: Path) -> bool:
    return (root / "packages" / "agency_flutter_ui" / "lib").exists() and (root / "starters").exists()


def next_stage(root: Path, client_dir: Path, state: dict[str, Any]) -> dict[str, Any]:
    completed = set(state.get("completed", []))

    if "client-intake" not in completed:
        return {"stage": "client-intake", "status": "ready"}

    if not (client_dir / "client-profile.yaml").exists():
        return {"stage": "client-intake", "status": "blocked", "reason": "client-profile-missing"}

    if "resolve-intelligence" not in completed:
        return {"stage": "resolve-intelligence", "status": "ready"}

    if not (client_dir / "resolved-intelligence.yaml").exists():
        return {"stage": "resolve-intelligence", "status": "blocked", "reason": "resolved-intelligence-missing"}

    if "resource-research" not in completed and not _is_skipped(state, "resource-research"):
        return {"stage": "resource-research", "status": "ready"}

    if "generate-directions" not in completed:
        return {"stage": "generate-directions", "status": "ready"}

    if not _directions_ready(client_dir):
        return {"stage": "generate-directions", "status": "blocked", "reason": "direction-artifacts-missing"}

    if "build-prototype" not in completed:
        if not _prototype_platform_installed(root):
            return {"stage": "build-prototype", "status": "blocked", "reason": "prototype-platform-not-installed"}
        return {"stage": "build-prototype", "status": "ready"}

    if "visual-qa" not in completed:
        return {"stage": "visual-qa", "status": "ready"}

    if "client-review" not in completed:
        return {"stage": "client-review", "status": "ready"}

    approved = client_dir / "approved-experience.yaml"
    if not approved.exists():
        return {"stage": "client-review", "status": "blocked", "reason": "approved-experience-missing"}

    if "productionize" not in completed:
        return {"stage": "productionize", "status": "ready"}

    return {"stage": None, "status": "complete"}
