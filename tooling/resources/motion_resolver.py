from __future__ import annotations

from pathlib import Path

import yaml


def resolve_motion(root: Path, semantic_id: str) -> dict:
    path = root / "resources" / "registry" / "motion" / "motion-assets.yaml"
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    entry = (data.get("motion") or {}).get(semantic_id)
    if not isinstance(entry, dict):
        raise KeyError(f"unknown semantic motion: {semantic_id}")
    result = dict(entry)
    result["semantic_id"] = semantic_id
    return result
