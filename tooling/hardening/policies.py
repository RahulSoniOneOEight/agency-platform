"""Deterministic validation of repository-owned H.2 hardening policies.

The validator only reads committed YAML policy files. It never contacts a
scanner, a provider, or any network service, so it is safe in normal CI where
no production credentials exist.

Every policy is a YAML mapping carrying a positive ``policy_version``. The
reference client must provide exactly six policy files under
``production/hardening/``:

- ``hardening-policy.yaml``
- ``security-policy.yaml``
- ``performance-budget.yaml``
- ``accessibility-policy.yaml``
- ``analytics-taxonomy.yaml``
- ``recovery-policy.yaml``

The validator enforces the reference performance budgets, the exact critical
journeys, the exact release outcomes, the security blocking severities, the
governed analytics events, and the recovery rules (previous-known-good-only
application rollback, reversible-flag-only database reversal, prohibited blind
database rollback, and new-artifact-is-a-new-candidate). No policy may mark
production authorization as automated: authorization remains the human
Milestone-G gate.

Errors are returned as a stable sorted list of strings (``[]`` means valid).
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Callable

import yaml

HARDENING_RELATIVE = Path("production") / "hardening"

POLICY_FILES: dict[str, str] = {
    "hardening": "hardening-policy.yaml",
    "security": "security-policy.yaml",
    "performance": "performance-budget.yaml",
    "accessibility": "accessibility-policy.yaml",
    "analytics": "analytics-taxonomy.yaml",
    "recovery": "recovery-policy.yaml",
}

SUB_POLICY_KEYS: tuple[str, ...] = (
    "security",
    "performance",
    "accessibility",
    "analytics",
    "recovery",
)

CRITICAL_JOURNEYS: tuple[str, ...] = (
    "sign-in",
    "catalog",
    "product-detail",
    "cart-order",
    "b2b-account-credit",
    "rfq-quotation-order",
)

RELEASE_OUTCOMES: tuple[str, ...] = ("healthy", "degraded", "failed")

BLOCKING_SEVERITIES: tuple[str, ...] = ("critical", "high")

ADVISORY_SEVERITIES: tuple[str, ...] = ("medium", "low", "info")

RELEASE_RELEVANT_STATUSES: tuple[str, ...] = ("open",)

PERFORMANCE_BUDGETS: dict[str, int] = {
    "main_js_raw_bytes_max": 4_500_000,
    "web_build_total_bytes_max": 18_000_000,
    "first_contentful_paint_ms_max": 3_000,
    "largest_contentful_paint_ms_max": 4_500,
    "critical_screen_ready_ms_max": 4_500,
    "critical_api_p95_ms_max": 1_200,
    "baseline_regression_percent_max": 20,
}

RECOVERY_MODES: tuple[str, ...] = (
    "application-rollback",
    "database-reverse-migration",
    "forward-recovery-migration",
    "manual-halt",
)

GOVERNED_EVENTS: tuple[str, ...] = (
    "sign_in",
    "catalog_view",
    "product_view",
    "cart_created",
    "cart_updated",
    "checkout_or_order_start",
    "order_created",
    "business_account_selected",
    "credit_viewed",
    "rfq_created",
    "quotation_viewed",
    "quotation_converted",
)


def _relative(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _is_positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _as_mapping(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def _as_name_set(entries: object, key: str) -> set[str]:
    """Collect the ``key`` field (or bare string) from a list of entries."""
    names: set[str] = set()
    if not isinstance(entries, list):
        return names
    for entry in entries:
        if isinstance(entry, str):
            names.add(entry)
        elif isinstance(entry, dict) and isinstance(entry.get(key), str):
            names.add(entry[key])
    return names


def _load_policy(
    path: Path, relative: str, errors: list[str]
) -> dict[str, Any] | None:
    if not path.is_file():
        errors.append(f"{relative}: missing policy file")
        return None
    raw = path.read_text(encoding="utf-8", errors="replace")
    try:
        payload = yaml.safe_load(raw)
    except yaml.YAMLError:
        errors.append(f"{relative}: invalid YAML")
        return None
    if not isinstance(payload, dict):
        errors.append(f"{relative}: policy must be a mapping")
        return None
    return payload


def _validate_policy_version(relative: str, policy: dict, errors: list[str]) -> None:
    version = policy.get("policy_version")
    if not _is_positive_int(version):
        errors.append(f"{relative}: policy_version must be a positive integer")


def _find_automated_authorization(value: object, prefix: str = "") -> list[str]:
    """Return dotted key paths that mark production authorization automated."""
    violations: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                continue
            path = f"{prefix}.{key}" if prefix else key
            if key == "automated_production_authorization" and bool(child):
                violations.append(path)
            if key == "production_authorization" and isinstance(child, dict):
                if bool(child.get("automated")):
                    violations.append(f"{path}.automated")
            violations.extend(_find_automated_authorization(child, path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            violations.extend(
                _find_automated_authorization(child, f"{prefix}[{index}]")
            )
    return violations


def _validate_no_automated_authorization(
    relative: str, policy: dict, errors: list[str]
) -> None:
    for path in _find_automated_authorization(policy):
        errors.append(
            f"{relative}: production authorization must not be automated ({path})"
        )


def _validate_required_names(
    relative: str,
    policy: dict,
    key: str,
    expected: tuple[str, ...],
    errors: list[str],
) -> None:
    actual = _as_name_set(policy.get(key), "name")
    if actual != set(expected):
        errors.append(
            f"{relative}: {key} must be exactly {list(expected)}"
        )


def _validate_hardening(
    relative: str, policy: dict, hardening_dir: Path, errors: list[str]
) -> None:
    if policy.get("client_id") != "reference-commerce":
        errors.append(f"{relative}: client_id must be 'reference-commerce'")

    _validate_required_names(
        relative, policy, "critical_journeys", CRITICAL_JOURNEYS, errors
    )
    _validate_required_names(
        relative, policy, "release_outcomes", RELEASE_OUTCOMES, errors
    )

    gate_model = _as_mapping(policy.get("gate_model"))
    if gate_model.get("blocking_disposition") != "blocking":
        errors.append(f"{relative}: gate_model.blocking_disposition must be 'blocking'")
    if gate_model.get("open_status_blocks") is not True:
        errors.append(f"{relative}: gate_model.open_status_blocks must be true")
    if gate_model.get("advisory_retained") is not True:
        errors.append(f"{relative}: gate_model.advisory_retained must be true")

    sub_policies = _as_mapping(policy.get("sub_policies"))
    for key in SUB_POLICY_KEYS:
        reference = sub_policies.get(key)
        if not isinstance(reference, str) or not reference:
            errors.append(f"{relative}: sub_policies.{key} must reference a file")
        elif not (hardening_dir / reference).is_file():
            errors.append(
                f"{relative}: sub_policies.{key} references missing file {reference!r}"
            )


def _validate_security(relative: str, policy: dict, errors: list[str]) -> None:
    blocking = _as_name_set(policy.get("blocking_severities"), "name")
    if not set(BLOCKING_SEVERITIES).issubset(blocking):
        errors.append(
            f"{relative}: blocking_severities must include {list(BLOCKING_SEVERITIES)}"
        )
    advisory = _as_name_set(policy.get("advisory_severities"), "name")
    if not set(ADVISORY_SEVERITIES).issubset(advisory):
        errors.append(
            f"{relative}: advisory_severities must include {list(ADVISORY_SEVERITIES)}"
        )
    statuses = _as_name_set(policy.get("release_relevant_statuses"), "name")
    if not set(RELEASE_RELEVANT_STATUSES).issubset(statuses):
        errors.append(
            f"{relative}: release_relevant_statuses must include "
            f"{list(RELEASE_RELEVANT_STATUSES)}"
        )
    _validate_checks(relative, policy, errors)


def _validate_performance(relative: str, policy: dict, errors: list[str]) -> None:
    for key, expected in PERFORMANCE_BUDGETS.items():
        value = policy.get(key)
        if not isinstance(value, int) or isinstance(value, bool):
            errors.append(f"{relative}: {key} must be an integer")
        elif value <= 0:
            errors.append(f"{relative}: {key} must be a positive integer")
        elif value != expected:
            errors.append(f"{relative}: {key} must equal {expected}")


def _validate_accessibility(relative: str, policy: dict, errors: list[str]) -> None:
    _validate_required_names(
        relative, policy, "critical_journeys", CRITICAL_JOURNEYS, errors
    )
    for key in ("blocking_rule", "advisory_rule"):
        value = policy.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{relative}: {key} must be a non-empty string")
    _validate_checks(relative, policy, errors)


def _validate_analytics(relative: str, policy: dict, errors: list[str]) -> None:
    if policy.get("environment_separation") is not True:
        errors.append(f"{relative}: environment_separation must be true")
    if policy.get("consent_handling") is not True:
        errors.append(f"{relative}: consent_handling must be true")
    events = policy.get("events")
    if not isinstance(events, list):
        events = []
    required = {
        name
        for name in _as_name_set(events, "name")
        if any(
            isinstance(entry, dict)
            and entry.get("name") == name
            and entry.get("required") is True
            for entry in events
        )
    }
    missing = [name for name in GOVERNED_EVENTS if name not in required]
    if missing:
        errors.append(
            f"{relative}: governed events must be required: {missing}"
        )


def _validate_recovery(relative: str, policy: dict, errors: list[str]) -> None:
    modes = _as_name_set(policy.get("modes"), "name")
    for mode in RECOVERY_MODES:
        if mode not in modes:
            errors.append(f"{relative}: modes missing required mode: {mode}")

    application = _as_mapping(policy.get("application_rollback"))
    if application.get("previous_known_good_only") is not True:
        errors.append(
            f"{relative}: application_rollback.previous_known_good_only must be true"
        )

    database = _as_mapping(policy.get("database_reversal"))
    if database.get("requires_reversible_flag") is not True:
        errors.append(
            f"{relative}: database_reversal.requires_reversible_flag must be true"
        )
    if database.get("blind_rollback_prohibited") is not True:
        errors.append(
            f"{relative}: database_reversal.blind_rollback_prohibited must be true"
        )

    if policy.get("new_artifact_is_new_candidate") is not True:
        errors.append(f"{relative}: new_artifact_is_new_candidate must be true")


def _validate_checks(relative: str, policy: dict, errors: list[str]) -> None:
    checks = policy.get("checks")
    if not isinstance(checks, list) or not checks:
        errors.append(f"{relative}: checks must be a non-empty list")
        return
    for index, check in enumerate(checks):
        if not isinstance(check, dict):
            errors.append(f"{relative}: checks[{index}] must be a mapping")
            continue
        if not isinstance(check.get("id"), str) or not check["id"]:
            errors.append(f"{relative}: checks[{index}].id must be a non-empty string")
        if not isinstance(check.get("release_relevant"), bool):
            errors.append(
                f"{relative}: checks[{index}].release_relevant must be a boolean"
            )


VALIDATORS: dict[str, Callable[..., None]] = {
    "hardening": _validate_hardening,
    "security": _validate_security,
    "performance": _validate_performance,
    "accessibility": _validate_accessibility,
    "analytics": _validate_analytics,
    "recovery": _validate_recovery,
}


def validate_hardening_policies(root: Path, client_dir: Path) -> list[str]:
    """Return stable sorted hardening-policy errors (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)
    hardening_dir = client_dir / HARDENING_RELATIVE

    if not hardening_dir.is_dir():
        return [
            f"{_relative(hardening_dir, root)}: missing hardening policy directory"
        ]

    errors: list[str] = []
    policies: dict[str, dict] = {}
    for name, filename in POLICY_FILES.items():
        path = hardening_dir / filename
        relative = _relative(path, root)
        policy = _load_policy(path, relative, errors)
        if policy is None:
            continue
        policies[name] = policy
        _validate_policy_version(relative, policy, errors)
        _validate_no_automated_authorization(relative, policy, errors)

    for name, policy in policies.items():
        relative = _relative(hardening_dir / POLICY_FILES[name], root)
        validator = VALIDATORS[name]
        if name == "hardening":
            validator(relative, policy, hardening_dir, errors)
        else:
            validator(relative, policy, errors)

    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate hardening policies, print errors, return code."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(arguments[0])
        if arguments
        else root / "client-projects" / "reference-commerce"
    )
    errors = validate_hardening_policies(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
