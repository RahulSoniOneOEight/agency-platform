"""Deterministic machine-readable scenario contract for the reference client.

The scenario declares the fixed runtime direction ids, the named experience
identities (RF1), and the ordered cycle scenarios. It is evidence only: it never
becomes a review, approval, QA, refinement, or workflow authority.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

SUPPORTED_SCENARIO_VERSIONS = frozenset({1})
REQUIRED_FIXTURE_VERSION = 1

SCENARIO_RELATIVE = Path("reference-e2e") / "scenario.yaml"
SCHEMA_RELATIVE = (
    Path("client-projects") / "schema" / "reference-client-scenario.schema.json"
)

REQUIRED_SCENARIO_IDS: tuple[str, ...] = (
    "normal-happy-path",
    "contract-change-reapproval",
    "implementation-only-change",
    "resume-after-interruption",
)

REQUIRED_DIRECTION_IDENTITIES: dict[str, str] = {
    "a": "efficient-commerce",
    "b": "premium-discovery",
    "c": "trade-first",
}


def load_scenario(path: Path) -> dict[str, Any]:
    """Load and shape-check a scenario document.

    Raises ``ValueError`` when the document is not a mapping or does not declare
    ``client_id`` / ``version``.
    """
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"scenario must be a mapping: {path}")
    if not isinstance(data.get("client_id"), str) or not data["client_id"]:
        raise ValueError(f"scenario requires a non-empty client_id: {path}")
    if "version" not in data:
        raise ValueError(f"scenario requires version: {path}")
    return data


def scenario_ids(scenario: dict[str, Any]) -> list[str]:
    """Return the ordered scenario ids declared by *scenario*."""
    scenarios = scenario.get("scenarios")
    if not isinstance(scenarios, list):
        return []
    return [
        entry["id"]
        for entry in scenarios
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    ]


def _schema_errors(root: Path, scenario: dict[str, Any]) -> list[str]:
    schema_path = root / SCHEMA_RELATIVE
    if not schema_path.exists():
        return [f"{schema_path}: missing scenario schema"]
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(scenario), key=lambda error: list(error.path))
    return [
        f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
        for error in errors
    ]


def validate_scenario(root: Path, client_dir: Path) -> list[str]:
    """Return deterministic, stable-sorted scenario errors (``[]`` == valid)."""
    path = client_dir / SCENARIO_RELATIVE
    if not path.exists():
        return [f"{path}: missing scenario"]
    try:
        scenario = load_scenario(path)
    except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
        return [f"{path}: {exc}"]

    errors: list[str] = []

    version = scenario.get("version")
    if version not in SUPPORTED_SCENARIO_VERSIONS:
        errors.append(f"{path}: unsupported scenario version {version!r}")

    client_id = scenario.get("client_id")
    if client_id != client_dir.name:
        errors.append(
            f"{path}: client_id {client_id!r} does not match client directory "
            f"{client_dir.name!r}"
        )

    fixture_version = scenario.get("fixture_version")
    if fixture_version != REQUIRED_FIXTURE_VERSION:
        errors.append(
            f"{path}: fixture_version must be {REQUIRED_FIXTURE_VERSION}, "
            f"got {fixture_version!r}"
        )

    identities = scenario.get("direction_identities")
    if identities != REQUIRED_DIRECTION_IDENTITIES:
        errors.append(
            f"{path}: direction_identities must be "
            f"{REQUIRED_DIRECTION_IDENTITIES!r}, got {identities!r}"
        )

    ids = scenario_ids(scenario)
    if ids != list(REQUIRED_SCENARIO_IDS):
        errors.append(
            f"{path}: scenario ids must be {list(REQUIRED_SCENARIO_IDS)!r}, got {ids!r}"
        )

    errors.extend(f"{path}: {error}" for error in _schema_errors(root, scenario))

    return sorted(set(errors))
