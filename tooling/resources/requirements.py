from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator


def load_requirements(root: Path, client_dir: Path) -> dict:
    path = client_dir / "derived" / "resource-requirements.yaml"
    if not path.exists():
        raise ValueError("derived/resource-requirements.yaml missing")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("resource requirements must be a mapping")
    schema_path = root / "resources" / "registry" / "schema" / "resource-requirements.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema).iter_errors(data), key=lambda error: list(error.path))
    if errors:
        joined = "; ".join(error.message for error in errors)
        raise ValueError(f"invalid resource requirements: {joined}")
    return data
