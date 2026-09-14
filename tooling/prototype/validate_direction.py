from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

_SCHEMA_PATH = Path(__file__).resolve().parents[1] / "knowledge" / "direction.schema.json"


def _load_schema() -> dict:
    return json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))


def validate_direction(direction: dict) -> list[str]:
    validator = Draft202012Validator(_load_schema())
    errors = sorted(validator.iter_errors(direction), key=lambda error: list(error.path))
    return [f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}" for error in errors]
