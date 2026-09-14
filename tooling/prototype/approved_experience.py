from __future__ import annotations

from pathlib import Path

import yaml


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def validate_approved_experience(root: Path, client_dir: Path) -> list[str]:
    del root
    errors: list[str] = []
    path = client_dir / "approved-experience.yaml"
    if not path.exists():
        return ["approved-experience.yaml missing"]
    data = _load_yaml(path)
    if data.get("version") != 1:
        errors.append("approved experience version must be 1")
    if data.get("client_id") != client_dir.name:
        errors.append("approved experience client_id must match client directory")

    selection = data.get("selection")
    if not isinstance(selection, dict):
        return errors + ["approved experience selection must be an object"]
    mode = selection.get("mode")
    if mode not in {"direction", "mixed"}:
        errors.append("selection mode must be direction or mixed")
    base = selection.get("base_direction") or selection.get("direction")
    if base not in {"a", "b", "c"}:
        errors.append("selection must reference direction a, b, or c")

    for direction_id in {base} | {
        item.get("source_direction")
        for item in (data.get("sections") or {}).values()
        if isinstance(item, dict)
    }:
        if direction_id in {"a", "b", "c"}:
            direction_path = client_dir / "directions" / f"direction-{direction_id}.yaml"
            if not direction_path.exists():
                errors.append(f"referenced direction missing: {direction_id}")

    if mode == "mixed":
        sections = data.get("sections")
        if not isinstance(sections, dict) or not sections:
            errors.append("mixed approval requires sections")
        elif any(
            not isinstance(value, dict) or value.get("source_direction") not in {"a", "b", "c"}
            for value in sections.values()
        ):
            errors.append("every mixed section requires source_direction a, b, or c")
    return errors
