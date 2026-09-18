"""Deterministic assertion engine for the reference-client cycle scenarios.

Every assertion inspects a canonical artifact or the synthetic fixture. It never
reads a copied review/approval/QA state file from ``reference-e2e/``: that
directory is evidence only (RF6).
"""

from __future__ import annotations

import fnmatch
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from tooling.prototype.build_runtime_bundle import compose_runtime_bundle
from tooling.reference_client.fixture import (
    fixture_identity,
    load_fixture,
    validate_fixture,
)
from tooling.reference_client.scenario import load_scenario, scenario_ids

ASSERTIONS_RELATIVE = Path("reference-e2e") / "assertions.yaml"
SCENARIO_RELATIVE = Path("reference-e2e") / "scenario.yaml"
FIXTURE_RELATIVE = Path("reference-e2e") / "fixture.yaml"
WORKFLOW_STATE_RELATIVE = Path("workflow-state.yaml")
GENERATED_RELATIVE = Path("apps") / "prototype_app" / "assets" / "generated"

SUPPORTED_ASSERTION_VERSIONS = frozenset({1})

# Canonical authority record filenames that must never be duplicated as evidence
# under ``reference-e2e/``.
FORBIDDEN_AUTHORITY_FILENAMES: tuple[str, ...] = (
    "review-state.*",
    "review_state.*",
    "review-index.*",
    "review_index.*",
    "feedback*.*",
    "approval*.*",
    "batch*.*",
    "qa-*.*",
    "qa_finding*.*",
    "qa_findings*.*",
    "findings*.*",
    "runs*.*",
)

_KIND_PARAMS: dict[str, frozenset[str]] = {
    "fixture_coverage": frozenset({"b2c", "b2b"}),
    "fixture_integrity": frozenset({"expected_identity"}),
    "direction_ids": frozenset({"expected"}),
    "direction_identity": frozenset({"expected"}),
    "journey_contains": frozenset({"direction", "step"}),
    "artifact_exists": frozenset({"path"}),
    "workflow_state": frozenset(
        {"current_stage", "status", "completed", "skipped_stages"}
    ),
    "bundle_client_id": frozenset({"expected"}),
    "bundle_fresh": frozenset(),
    "no_duplicate_authority": frozenset(),
}

SUPPORTED_ASSERTION_KINDS = frozenset(_KIND_PARAMS)


@dataclass(frozen=True)
class AssertionResult:
    id: str
    scenario: str
    description: str
    passed: bool
    detail: str | None = None


def load_assertions(path: Path) -> dict[str, Any]:
    """Load an assertion document as a mapping.

    The canonical file is a mapping with an ``assertions`` list. A bare YAML list
    is also accepted and wrapped for convenience.
    """
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, list):
        return {"assertions": data}
    if not isinstance(data, dict):
        raise ValueError(f"assertions must be a mapping or list: {path}")
    return data


def _assertion_definitions(document: dict[str, Any]) -> list[dict[str, Any]]:
    definitions = document.get("assertions")
    if not isinstance(definitions, list):
        return []
    return [entry for entry in definitions if isinstance(entry, dict)]


def _canonical_bundle_bytes(bundle: dict[str, Any]) -> bytes:
    return (
        json.dumps(bundle, indent=2, sort_keys=True, allow_nan=False) + "\n"
    ).encode("utf-8")


def _bundle_path(root: Path, client_id: str) -> Path:
    return root / GENERATED_RELATIVE / f"{client_id}.json"


def _load_bundle(root: Path, client_id: str) -> dict[str, Any]:
    path = _bundle_path(root, client_id)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"runtime bundle must be an object: {path}")
    return data


def _load_yaml(path: Path) -> Any:
    return yaml.safe_load(Path(path).read_text(encoding="utf-8"))


def _evaluate_fixture_coverage(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    fixture = load_fixture(client_dir / FIXTURE_RELATIVE)
    coverage = fixture.get("coverage")
    if not isinstance(coverage, dict):
        coverage = {}
    actual = {"b2c": coverage.get("b2c"), "b2b": coverage.get("b2b")}
    expected = {"b2c": params["b2c"], "b2b": params["b2b"]}
    if actual == expected:
        return True, None
    return False, f"fixture coverage {actual!r} does not match {expected!r}"


def _evaluate_fixture_integrity(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    errors = validate_fixture(root, client_dir)
    if errors:
        return False, "fixture validation failed: " + "; ".join(errors[:3])
    fixture = load_fixture(client_dir / FIXTURE_RELATIVE)
    actual = fixture_identity(fixture)
    expected = params["expected_identity"]
    if actual == expected:
        return True, None
    return False, (
        f"fixture identity {actual!r} does not match the pinned {expected!r} "
        "(fixture content changed without updating the determinism assertion)"
    )


def _evaluate_journey_contains(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    direction_id = params["direction"]
    step = params["step"]
    path = client_dir / "directions" / f"direction-{direction_id}.yaml"
    if not path.exists():
        return False, f"missing direction file {path.name}"
    document = _load_yaml(path)
    if not isinstance(document, dict):
        return False, f"{path.name} is not a mapping"

    steps: list[str] = []
    primary = document.get("primary_journey")
    if isinstance(primary, dict) and isinstance(primary.get("steps"), list):
        steps.extend(str(item) for item in primary["steps"])
    secondary = document.get("secondary_journeys")
    if isinstance(secondary, list):
        for journey in secondary:
            if isinstance(journey, dict) and isinstance(journey.get("steps"), list):
                steps.extend(str(item) for item in journey["steps"])
    if step in steps:
        return True, None
    return False, (
        f"direction {direction_id!r} journey does not contain step {step!r} "
        f"(found {sorted(set(steps))!r})"
    )


def _evaluate_direction_ids(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    bundle = _load_bundle(root, client_dir.name)
    directions = bundle.get("directions")
    actual = sorted(directions.keys()) if isinstance(directions, dict) else []
    expected = sorted(params["expected"])
    if actual == expected:
        return True, None
    return False, f"runtime direction ids {actual!r} do not match {expected!r}"


def _evaluate_direction_identity(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    expected = params["expected"]
    actual: dict[str, Any] = {}
    for direction_id in sorted(expected):
        path = client_dir / "directions" / f"direction-{direction_id}.yaml"
        if not path.exists():
            actual[direction_id] = None
            continue
        document = _load_yaml(path)
        actual[direction_id] = (
            document.get("archetype") if isinstance(document, dict) else None
        )
    if actual == expected:
        return True, None
    return False, f"direction identities {actual!r} do not match {expected!r}"


def _evaluate_artifact_exists(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    relative = params["path"]
    if (client_dir / relative).exists():
        return True, None
    return False, f"missing canonical artifact {relative!r}"


def _evaluate_workflow_state(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    state = _load_yaml(client_dir / WORKFLOW_STATE_RELATIVE)
    if not isinstance(state, dict):
        return False, "workflow-state.yaml is not a mapping"

    problems: list[str] = []
    if state.get("current_stage") != params["current_stage"]:
        problems.append(
            f"current_stage {state.get('current_stage')!r} != {params['current_stage']!r}"
        )
    if state.get("status") != params["status"]:
        problems.append(f"status {state.get('status')!r} != {params['status']!r}")

    completed = state.get("completed")
    completed_set = set(completed) if isinstance(completed, list) else set()
    missing_completed = sorted(set(params["completed"]) - completed_set)
    if missing_completed:
        problems.append(f"missing completed stages {missing_completed!r}")

    skipped = state.get("skipped")
    skipped_set = {
        entry.get("stage")
        for entry in skipped
        if isinstance(entry, dict) and isinstance(entry.get("stage"), str)
    } if isinstance(skipped, list) else set()
    missing_skipped = sorted(set(params["skipped_stages"]) - skipped_set)
    if missing_skipped:
        problems.append(f"missing skipped stages {missing_skipped!r}")

    if problems:
        return False, "; ".join(problems)
    return True, None


def _evaluate_bundle_client_id(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    expected = params["expected"]
    bundle = _load_bundle(root, expected)
    if bundle.get("client_id") == expected:
        return True, None
    return False, (
        f"runtime bundle client_id {bundle.get('client_id')!r} != {expected!r}"
    )


def _evaluate_bundle_fresh(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    bundle = compose_runtime_bundle(root, client_dir)
    expected_bytes = _canonical_bundle_bytes(bundle)
    path = _bundle_path(root, client_dir.name)
    if not path.exists():
        return False, f"missing committed runtime bundle {path}"
    committed = path.read_bytes()
    if committed == expected_bytes:
        return True, None
    return False, (
        "committed runtime bundle is not byte-fresh against a fresh in-memory "
        "composition"
    )


def _evaluate_no_duplicate_authority(
    root: Path, client_dir: Path, params: dict[str, Any]
) -> tuple[bool, str | None]:
    evidence_dir = client_dir / "reference-e2e"
    if not evidence_dir.exists():
        return True, None
    offenders: list[str] = []
    for path in sorted(evidence_dir.rglob("*")):
        if not path.is_file():
            continue
        if any(
            fnmatch.fnmatch(path.name, pattern)
            for pattern in FORBIDDEN_AUTHORITY_FILENAMES
        ):
            offenders.append(path.relative_to(client_dir).as_posix())
    if offenders:
        return False, f"reference-e2e/ duplicates canonical authority: {offenders!r}"
    return True, None


_EVALUATORS = {
    "fixture_coverage": _evaluate_fixture_coverage,
    "fixture_integrity": _evaluate_fixture_integrity,
    "journey_contains": _evaluate_journey_contains,
    "direction_ids": _evaluate_direction_ids,
    "direction_identity": _evaluate_direction_identity,
    "artifact_exists": _evaluate_artifact_exists,
    "workflow_state": _evaluate_workflow_state,
    "bundle_client_id": _evaluate_bundle_client_id,
    "bundle_fresh": _evaluate_bundle_fresh,
    "no_duplicate_authority": _evaluate_no_duplicate_authority,
}


def _evaluate(
    root: Path, client_dir: Path, definition: dict[str, Any]
) -> AssertionResult:
    assertion_id = definition.get("id")
    scenario = definition.get("scenario")
    description = definition.get("description")
    kind = definition.get("kind")
    params = definition.get("params")
    if not isinstance(params, dict):
        params = {}

    result_id = assertion_id if isinstance(assertion_id, str) else "<unknown>"
    result_scenario = scenario if isinstance(scenario, str) else "<unknown>"
    result_description = description if isinstance(description, str) else ""

    evaluator = _EVALUATORS.get(kind) if isinstance(kind, str) else None
    if evaluator is None:
        return AssertionResult(
            id=result_id,
            scenario=result_scenario,
            description=result_description,
            passed=False,
            detail=f"unsupported assertion kind {kind!r}",
        )

    try:
        passed, detail = evaluator(root, client_dir, params)
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, yaml.YAMLError) as exc:
        return AssertionResult(
            id=result_id,
            scenario=result_scenario,
            description=result_description,
            passed=False,
            detail=f"{type(exc).__name__}: {exc}",
        )

    return AssertionResult(
        id=result_id,
        scenario=result_scenario,
        description=result_description,
        passed=passed,
        detail=detail,
    )


def evaluate_assertions(root: Path, client_dir: Path) -> list[AssertionResult]:
    """Evaluate every assertion definition against canonical artifacts.

    An empty assertion set is a hard error: a scenario with nothing to prove
    must never report a vacuous pass.
    """
    document = load_assertions(client_dir / ASSERTIONS_RELATIVE)
    definitions = _assertion_definitions(document)
    if not definitions:
        raise ValueError("assertions must contain at least one assertion definition")
    return [_evaluate(root, client_dir, definition) for definition in definitions]


def _params_errors(
    index: int, kind: str, params: Any
) -> list[str]:
    if not isinstance(params, dict):
        return [f"assertions.{index}: params must be a mapping"]
    required = _KIND_PARAMS[kind]
    actual = set(params)
    errors: list[str] = []
    missing = sorted(required - actual)
    extra = sorted(actual - required)
    if missing:
        errors.append(f"assertions.{index}: kind {kind!r} missing params {missing!r}")
    if extra:
        errors.append(f"assertions.{index}: kind {kind!r} has unknown params {extra!r}")
    return errors


def _kind_value_errors(index: int, kind: str, params: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if kind == "fixture_coverage":
        for key in ("b2c", "b2b"):
            if not isinstance(params.get(key), bool):
                errors.append(f"assertions.{index}: params.{key} must be a boolean")
    elif kind == "direction_ids":
        expected = params.get("expected")
        if not isinstance(expected, list) or any(
            not isinstance(item, str) for item in expected
        ):
            errors.append(
                f"assertions.{index}: params.expected must be a list of strings"
            )
    elif kind == "direction_identity":
        expected = params.get("expected")
        if not isinstance(expected, dict) or any(
            not isinstance(value, str) for value in expected.values()
        ):
            errors.append(
                f"assertions.{index}: params.expected must be a string mapping"
            )
    elif kind in {"artifact_exists", "bundle_client_id"}:
        key = "path" if kind == "artifact_exists" else "expected"
        if not isinstance(params.get(key), str) or not params[key]:
            errors.append(f"assertions.{index}: params.{key} must be a non-empty string")
    elif kind == "workflow_state":
        for key in ("current_stage", "status"):
            if not isinstance(params.get(key), str) or not params[key]:
                errors.append(
                    f"assertions.{index}: params.{key} must be a non-empty string"
                )
        for key in ("completed", "skipped_stages"):
            value = params.get(key)
            if not isinstance(value, list) or any(
                not isinstance(item, str) for item in value
            ):
                errors.append(
                    f"assertions.{index}: params.{key} must be a list of strings"
                )
    return errors


def validate_assertions(root: Path, client_dir: Path) -> list[str]:
    """Return deterministic, stable-sorted assertion errors (``[]`` == valid)."""
    path = client_dir / ASSERTIONS_RELATIVE
    if not path.exists():
        return [f"{path}: missing assertions"]
    try:
        document = load_assertions(path)
    except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
        return [f"{path}: {exc}"]

    errors: list[str] = []

    version = document.get("version")
    if version is None:
        errors.append(f"{path}: assertions require a version")
    elif version not in SUPPORTED_ASSERTION_VERSIONS:
        errors.append(f"{path}: unsupported assertions version {version!r}")

    client_id = document.get("client_id")
    if client_id is None:
        errors.append(f"{path}: assertions require a client_id")
    elif client_id != client_dir.name:
        errors.append(
            f"{path}: client_id {client_id!r} does not match client directory "
            f"{client_dir.name!r}"
        )

    scenario_path = client_dir / SCENARIO_RELATIVE
    known_scenarios: list[str] = []
    if scenario_path.exists():
        try:
            known_scenarios = scenario_ids(load_scenario(scenario_path))
        except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
            errors.append(f"{scenario_path}: {exc}")

    definitions = document.get("assertions")
    if not isinstance(definitions, list) or not definitions:
        errors.append(f"{path}: assertions must be a non-empty list")
        return sorted(set(errors))

    seen_ids: set[str] = set()
    for index, definition in enumerate(definitions):
        if not isinstance(definition, dict):
            errors.append(f"assertions.{index}: assertion must be a mapping")
            continue
        for key in ("id", "scenario", "kind", "description"):
            if not isinstance(definition.get(key), str) or not definition[key]:
                errors.append(
                    f"assertions.{index}: {key} must be a non-empty string"
                )

        assertion_id = definition.get("id")
        if isinstance(assertion_id, str):
            if assertion_id in seen_ids:
                errors.append(f"assertions.{index}: duplicate assertion id {assertion_id!r}")
            seen_ids.add(assertion_id)

        scenario = definition.get("scenario")
        if isinstance(scenario, str) and known_scenarios and scenario not in known_scenarios:
            errors.append(
                f"assertions.{index}: unknown scenario {scenario!r}"
            )

        kind = definition.get("kind")
        if not isinstance(kind, str) or kind not in SUPPORTED_ASSERTION_KINDS:
            errors.append(f"assertions.{index}: unsupported kind {kind!r}")
            continue

        params = definition.get("params")
        errors.extend(_params_errors(index, kind, params))
        if isinstance(params, dict):
            errors.extend(_kind_value_errors(index, kind, params))

    return sorted(set(errors))
