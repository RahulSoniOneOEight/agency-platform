from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator


_SCHEMA_NAMES = {
    "requirements": "resource-requirements.schema.json",
    "candidates": "resource-candidates.schema.json",
    "selection": "resource-selection.schema.json",
    "provenance": "resource-provenance.schema.json",
}


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def validate_resource_artifacts(root: Path, client_dir: Path) -> list[str]:
    errors: list[str] = []
    paths = {
        "requirements": client_dir / "derived" / "resource-requirements.yaml",
        "candidates": client_dir / "resources" / "candidates.yaml",
        "selection": client_dir / "resources" / "selection.yaml",
        "provenance": client_dir / "resources" / "provenance.yaml",
    }
    data: dict[str, dict] = {}
    for key, path in paths.items():
        if not path.exists():
            return [f"{path}: missing"]
        loaded = _load_yaml(path)
        data[key] = loaded
        schema_path = root / "resources" / "registry" / "schema" / _SCHEMA_NAMES[key]
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        for error in Draft202012Validator(schema).iter_errors(loaded):
            errors.append(f"{path}: {error.message}")

    requirements = {item.get("id"): item for item in data["requirements"].get("resources") or []}
    candidate_ids = {
        candidate.get("id"): candidate
        for group in (data["candidates"].get("candidates") or {}).values()
        for candidate in group or []
        if isinstance(candidate, dict)
    }
    provenance = data["provenance"].get("resources") or {}
    selections = data["selection"].get("selections") or {}

    for requirement_id, requirement in requirements.items():
        selection = selections.get(requirement_id)
        if requirement.get("impact") == "critical" and not selection:
            errors.append(f"critical resource {requirement_id!r} has no selection")
            continue
        if not selection:
            continue
        candidate = candidate_ids.get(selection.get("primary"))
        if candidate is None:
            errors.append(f"selection {requirement_id!r} references unknown candidate {selection.get('primary')!r}")
            continue
        mode = (requirement.get("sourcing") or {}).get("mode")
        if mode == "authoritative" and candidate.get("source") not in {"client", "official", "agency"}:
            errors.append(f"authoritative resource {requirement_id!r} uses unauthorized source {candidate.get('source')!r}")
        if candidate.get("source") not in {"client", "agency"} and candidate.get("id") not in provenance:
            errors.append(f"external resource {candidate.get('id')!r} missing provenance")
    return errors
