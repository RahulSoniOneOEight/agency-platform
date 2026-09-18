"""Deterministic validator for the reference-client machine evidence report.

The report is *evidence only* (RF6): it records ids, counts, statuses, and
references for the reference-commerce end-to-end journey. It must never copy
review/approval/QA authority state into ``reference-e2e/`` and must never
collapse the programme into a subjective overall score. This module is
Flutter-free: it validates an already-emitted report against the JSON schema and
the canonical client fixture/scenario contracts.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

from tooling.reference_client.fixture import FIXTURE_RELATIVE, load_fixture
from tooling.reference_client.scenario import (
    SCENARIO_RELATIVE,
    load_scenario,
    scenario_ids,
)

SCHEMA_RELATIVE = (
    Path("client-projects") / "schema" / "reference-client-report.schema.json"
)

# Subjective aggregate-quality keys are forbidden anywhere in the evidence.
FORBIDDEN_SCORE_KEYS: frozenset[str] = frozenset(
    {"overall_score", "score", "quality_score"}
)

# Canonical authority-state keys that must never be copied into evidence. The
# report may reference records by id, but it may not embed their full state.
FORBIDDEN_AUTHORITY_KEYS: frozenset[str] = frozenset(
    {
        "review_state_hash",
        "screen_selections",
        "unresolved_non_blocking",
        "reviewed_by",
        "approved_by",
        "approved_at",
        "dedupe_key",
        "history",
        "visual_attachment",
    }
)


def load_evidence(path: Path) -> dict[str, Any]:
    """Load an evidence document as a mapping.

    Raises ``ValueError`` when the document is not a mapping.
    """
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"evidence must be a mapping: {path}")
    return data


def _schema_errors(root: Path, evidence: dict[str, Any]) -> list[str]:
    schema_path = root / SCHEMA_RELATIVE
    if not schema_path.exists():
        return [f"{schema_path}: missing evidence schema"]
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    errors = sorted(
        validator.iter_errors(evidence), key=lambda error: list(error.path)
    )
    return [
        f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
        for error in errors
    ]


def _forbidden_key_paths(
    value: Any, forbidden: frozenset[str], prefix: str = ""
) -> list[str]:
    """Return dotted/indexed paths of every forbidden key anywhere in *value*."""
    paths: list[str] = []
    if isinstance(value, dict):
        for key, item in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            if key in forbidden:
                paths.append(path)
            paths.extend(_forbidden_key_paths(item, forbidden, path))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            paths.extend(
                _forbidden_key_paths(item, forbidden, f"{prefix}[{index}]")
            )
    return paths


def _approval_version_errors(versions: Any) -> list[str]:
    if not isinstance(versions, list) or not versions:
        return ["approval_versions must be a non-empty list"]
    errors: list[str] = []
    for index, value in enumerate(versions):
        if isinstance(value, bool) or not isinstance(value, int):
            errors.append(f"approval_versions[{index}] must be an integer")
    if errors:
        return errors
    if versions[0] != 1:
        errors.append("approval_versions must start at 1")
    for index in range(1, len(versions)):
        if versions[index] <= versions[index - 1]:
            errors.append("approval_versions must be strictly increasing")
            break
    return errors


def validate_evidence(
    root: Path, client_dir: Path, evidence: dict[str, Any]
) -> list[str]:
    """Return deterministic, stable-sorted evidence errors (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []

    if not isinstance(evidence, dict):
        return ["evidence must be a mapping"]

    errors.extend(_schema_errors(root, evidence))

    client_id = evidence.get("client_id")
    if client_id != client_dir.name:
        errors.append(
            f"evidence client_id {client_id!r} does not match client directory "
            f"{client_dir.name!r}"
        )

    fixture_path = client_dir / FIXTURE_RELATIVE
    expected_fixture_version: Any = None
    if fixture_path.exists():
        try:
            expected_fixture_version = load_fixture(fixture_path).get(
                "fixture_version"
            )
        except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
            errors.append(f"{fixture_path}: {exc}")
    else:
        errors.append(f"{fixture_path}: missing fixture")
    if evidence.get("fixture_version") != expected_fixture_version:
        errors.append(
            f"evidence fixture_version {evidence.get('fixture_version')!r} does "
            f"not match fixture {expected_fixture_version!r}"
        )

    scenario_path = client_dir / SCENARIO_RELATIVE
    known_scenarios: list[str] = []
    if scenario_path.exists():
        try:
            known_scenarios = scenario_ids(load_scenario(scenario_path))
        except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
            errors.append(f"{scenario_path}: {exc}")
    else:
        errors.append(f"{scenario_path}: missing scenario")
    scenario_id = evidence.get("scenario_id")
    if scenario_id not in known_scenarios:
        errors.append(
            f"evidence scenario_id {scenario_id!r} is not a known scenario "
            f"{known_scenarios!r}"
        )

    assertions = evidence.get("assertions")
    if isinstance(assertions, list):
        for index, entry in enumerate(assertions):
            if not isinstance(entry, dict) or entry.get("passed") is not True:
                errors.append(
                    f"assertions[{index}]: every assertion must record passed true"
                )
    else:
        errors.append("assertions must be a list")

    errors.extend(_approval_version_errors(evidence.get("approval_versions")))

    review_rounds = evidence.get("review_rounds")
    if (
        isinstance(review_rounds, bool)
        or not isinstance(review_rounds, int)
        or review_rounds < 1
    ):
        errors.append("review_rounds must be an integer >= 1")

    for path in _forbidden_key_paths(evidence, FORBIDDEN_SCORE_KEYS):
        errors.append(f"evidence must not contain a subjective score key: {path}")

    for path in _forbidden_key_paths(evidence, FORBIDDEN_AUTHORITY_KEYS):
        errors.append(f"evidence must not copy authority state: {path}")

    return sorted(set(errors))
