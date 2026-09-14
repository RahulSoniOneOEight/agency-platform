from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

from .validate_direction import validate_direction

_SCHEMA_PATH = Path(__file__).resolve().parent / "runtime_direction.schema.json"


def _load_schema() -> dict:
    return json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))


def validate_runtime_direction(direction: dict) -> list[str]:
    validator = Draft202012Validator(_load_schema())
    errors = sorted(validator.iter_errors(direction), key=lambda error: list(error.path))
    return [f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}" for error in errors]


def project_direction(direction: dict) -> dict:
    strategic_errors = validate_direction(direction)
    if strategic_errors:
        raise ValueError("invalid strategic direction: " + "; ".join(strategic_errors))

    runtime = {
        "id": direction["id"],
        "name": direction["name"],
        "strategic_goal": direction["strategic_goal"],
        "navigation_model": direction["navigation"]["model"],
        "primary_journey": direction["primary_journey"]["id"],
        "discovery_model": direction["discovery_model"],
        "merchandising_model": direction["merchandising"]["emphasis"],
        "density": direction["density"],
        "transaction_model": direction["transaction_model"],
        "patterns": list(direction["patterns"]),
        "components": list(direction["components"]),
        "component_variants": list(direction["component_variants"]),
        "required_resources": list(direction["required_resources"]),
    }

    runtime_errors = validate_runtime_direction(runtime)
    if runtime_errors:
        raise ValueError("invalid runtime direction: " + "; ".join(runtime_errors))
    return runtime
