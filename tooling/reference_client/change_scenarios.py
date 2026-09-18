"""Change-boundary policy and machine-evidence validator for the reference client.

Two responsibilities, both Flutter-free (RF17):

1. **Change classification policy.** :func:`classify_change` decides whether a
   change is contract-impacting. It returns ``implementation_only`` *only* when
   the descriptor explicitly proves the change is internal and invisible; any
   missing, ambiguous, or contradictory field falls back to
   ``contract_impacting`` (the uncertainty rule).
2. **Change-scenario evidence validation.** :func:`validate_change_evidence`
   checks the committed machine evidence emitted by the Dart E2E change test
   against the JSON schema and the deterministic boundary invariants. Evidence
   is evidence only (RF6): it never copies review/approval authority bodies and
   never collapses the programme into a subjective score.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

import yaml
from jsonschema import Draft202012Validator

from tooling.reference_client.fixture import FIXTURE_RELATIVE, load_fixture
from tooling.reference_client.scenario import (
    SCENARIO_RELATIVE,
    load_scenario,
    scenario_ids,
)

CONTRACT_IMPACTING = "contract_impacting"
IMPLEMENTATION_ONLY = "implementation_only"

SCHEMA_RELATIVE = (
    Path("client-projects")
    / "schema"
    / "reference-client-change-evidence.schema.json"
)

# Subjective aggregate-quality keys are forbidden anywhere in the evidence.
FORBIDDEN_SCORE_KEYS: frozenset[str] = frozenset(
    {"overall_score", "score", "quality_score"}
)

# Copied review/approval authority bodies must never appear in evidence.
FORBIDDEN_AUTHORITY_KEYS: frozenset[str] = frozenset(
    {"history", "reviewed_by", "approved_by", "text"}
)


def classify_change(change: Mapping[str, Any]) -> str:
    """Classify a change descriptor as implementation-only or contract-impacting.

    A descriptor is implementation-only only when it *explicitly* declares all of
    the following: ``internal_only is True``, ``affects_review_decisions is
    False``, ``affects_governed_screens is False``,
    ``affects_approved_journeys is False``, ``visible_to_client is False``, and
    ``uncertain is not True``. Anything else — a missing field, a non-boolean
    value, or a contradictory signal — is contract-impacting (the uncertainty
    default).
    """
    if not isinstance(change, Mapping):
        return CONTRACT_IMPACTING
    implementation_only = (
        change.get("internal_only") is True
        and change.get("affects_review_decisions") is False
        and change.get("affects_governed_screens") is False
        and change.get("affects_approved_journeys") is False
        and change.get("visible_to_client") is False
        and change.get("uncertain") is not True
    )
    return IMPLEMENTATION_ONLY if implementation_only else CONTRACT_IMPACTING


def contract_impacting_change() -> dict[str, Any]:
    """The canonical deterministic contract-impacting change descriptor."""
    return {
        "internal_only": False,
        "affects_review_decisions": True,
        "affects_governed_screens": True,
        "affects_approved_journeys": True,
        "visible_to_client": True,
        "uncertain": False,
    }


def implementation_only_change() -> dict[str, Any]:
    """The canonical deterministic implementation-only change descriptor."""
    return {
        "internal_only": True,
        "affects_review_decisions": False,
        "affects_governed_screens": False,
        "affects_approved_journeys": False,
        "visible_to_client": False,
        "uncertain": False,
    }


def _schema_errors(root: Path, evidence: dict[str, Any]) -> list[str]:
    schema_path = root / SCHEMA_RELATIVE
    if not schema_path.exists():
        return [f"{schema_path}: missing change-evidence schema"]
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(evidence), key=lambda error: list(error.path))
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


def _integer(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _approval_version_errors(versions: Any, label: str) -> list[str]:
    if not isinstance(versions, list) or not versions:
        return [f"{label} must be a non-empty list"]
    errors: list[str] = []
    for index, value in enumerate(versions):
        if not _integer(value):
            errors.append(f"{label}[{index}] must be an integer")
    if errors:
        return errors
    if versions[0] != 1:
        errors.append(f"{label} must start at 1")
    for index in range(1, len(versions)):
        if versions[index] <= versions[index - 1]:
            errors.append(f"{label} must be strictly increasing")
            break
    return errors


def _contract_change_errors(contract: Any) -> list[str]:
    if not isinstance(contract, Mapping):
        return ["contract_change must be a mapping"]

    errors: list[str] = []
    versions = contract.get("approval_versions")
    if isinstance(versions, list) and len(versions) < 2:
        errors.append(
            "contract_change.approval_versions must have at least two entries"
        )
    errors.extend(
        _approval_version_errors(versions, "contract_change.approval_versions")
    )

    if contract.get("v1_immutable") is not True:
        errors.append("contract_change.v1_immutable must be true")

    v2_version = contract.get("v2_version")
    valid_versions = (
        isinstance(versions, list)
        and versions
        and all(_integer(value) for value in versions)
    )
    if valid_versions and v2_version != max(versions):
        errors.append(
            "contract_change.v2_version must equal the maximum approval version"
        )
    if _integer(v2_version):
        if contract.get("v2_supersedes") != v2_version - 1:
            errors.append(
                "contract_change.v2_supersedes must equal v2_version - 1"
            )
    else:
        errors.append("contract_change.v2_version must be an integer")

    v2_review_round = contract.get("v2_review_round")
    if not _integer(v2_review_round) or v2_review_round < 2:
        errors.append("contract_change.v2_review_round must be an integer >= 2")

    if contract.get("v2_hash_differs") is not True:
        errors.append("contract_change.v2_hash_differs must be true")
    if contract.get("third_approval_refused") is not True:
        errors.append("contract_change.third_approval_refused must be true")

    return errors


def _implementation_only_errors(implementation: Any) -> list[str]:
    if not isinstance(implementation, Mapping):
        return ["implementation_only must be a mapping"]

    errors: list[str] = []
    versions = implementation.get("approval_versions")
    if isinstance(versions, list) and len(versions) != 1:
        errors.append(
            "implementation_only.approval_versions must have exactly one entry"
        )
    errors.extend(
        _approval_version_errors(
            versions, "implementation_only.approval_versions"
        )
    )

    if implementation.get("review_round") != 1:
        errors.append("implementation_only.review_round must be 1")
    if implementation.get("classification") != IMPLEMENTATION_ONLY:
        errors.append(
            "implementation_only.classification must be 'implementation_only'"
        )
    if implementation.get("approved_hash_unchanged") is not True:
        errors.append("implementation_only.approved_hash_unchanged must be true")
    if implementation.get("default_classification") != CONTRACT_IMPACTING:
        errors.append(
            "implementation_only.default_classification must be "
            "'contract_impacting'"
        )

    return errors


def validate_change_evidence(
    root: Path, client_dir: Path, evidence: dict[str, Any]
) -> list[str]:
    """Return deterministic, stable-sorted change-evidence errors (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)

    if not isinstance(evidence, dict):
        return ["evidence must be a mapping"]

    errors: list[str] = []
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

    scenario_ids_value = evidence.get("scenario_ids")
    if isinstance(scenario_ids_value, list):
        for index, scenario_id in enumerate(scenario_ids_value):
            if scenario_id not in known_scenarios:
                errors.append(
                    f"evidence scenario_ids[{index}] {scenario_id!r} is not a "
                    f"known scenario {known_scenarios!r}"
                )
    else:
        errors.append("evidence scenario_ids must be a list")

    errors.extend(_contract_change_errors(evidence.get("contract_change")))
    errors.extend(
        _implementation_only_errors(evidence.get("implementation_only"))
    )

    assertions = evidence.get("assertions")
    if isinstance(assertions, list):
        for index, entry in enumerate(assertions):
            if not isinstance(entry, Mapping) or entry.get("passed") is not True:
                errors.append(
                    f"assertions[{index}]: every assertion must record passed true"
                )
    else:
        errors.append("assertions must be a list")

    for path in _forbidden_key_paths(evidence, FORBIDDEN_SCORE_KEYS):
        errors.append(f"evidence must not contain a subjective score key: {path}")

    for path in _forbidden_key_paths(evidence, FORBIDDEN_AUTHORITY_KEYS):
        errors.append(f"evidence must not copy authority state: {path}")

    return sorted(set(errors))
