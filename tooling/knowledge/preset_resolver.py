from __future__ import annotations

from pathlib import Path
from typing import Any

from tooling.knowledge.io import load_yaml


def _load_preset(root: Path, preset_type: str, preset_id: str) -> dict[str, Any]:
    path = root / "presets" / preset_type / f"{preset_id}.yaml"
    if not path.exists():
        raise ValueError(f"Unknown {preset_type} preset: {preset_id}")
    data = load_yaml(path)
    if not isinstance(data, dict):
        raise ValueError(f"Preset must be a mapping: {path}")
    return data


def resolve_presets(
    root: Path,
    *,
    business_model: str,
    industry: str,
    use_cases: list[str] | None = None,
) -> dict[str, Any]:
    requested = [
        ("business-model", business_model),
        ("industry", industry),
        *[("use-case", item) for item in (use_cases or [])],
    ]
    presets = [_load_preset(root, kind, preset_id) for kind, preset_id in requested]

    candidates: list[str] = []
    important_jobs: list[str] = []
    preferences: dict[str, Any] = {}
    conflicts: list[dict[str, Any]] = []

    for preset in presets:
        for candidate in preset.get("candidate_archetypes", []):
            if candidate not in candidates:
                candidates.append(candidate)
        for job in preset.get("important_jobs", []):
            if job not in important_jobs:
                important_jobs.append(job)
        for key, value in preset.get("preferences", {}).items():
            if key in preferences and preferences[key] != value:
                conflicts.append({"key": key, "previous": preferences[key], "incoming": value, "source": preset["id"]})
            preferences[key] = value

    return {
        "active_presets": [preset_id for _, preset_id in requested],
        "candidate_archetypes": candidates,
        "important_jobs": important_jobs,
        "preferences": preferences,
        "conflicts": conflicts,
    }
