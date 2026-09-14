from __future__ import annotations

from pathlib import Path

import yaml


def resolve_icon(root: Path, semantic_id: str) -> dict:
    path = root / "resources" / "registry" / "icons" / "semantic-icons.yaml"
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    entry = (data.get("icons") or {}).get(semantic_id)
    if not isinstance(entry, dict):
        raise KeyError(f"unknown semantic icon: {semantic_id}")
    preferred = entry.get("preferred") or entry.get("fallback")
    if not isinstance(preferred, dict):
        raise ValueError(f"icon mapping missing provider/name: {semantic_id}")
    return {
        "semantic_id": semantic_id,
        "provider": preferred.get("provider"),
        "name": preferred.get("name"),
        "fallback": entry.get("fallback"),
    }
