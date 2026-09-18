"""H.2 hardening validation and report regeneration (Task 7 / Task 14 entry).

``validate_hardening`` is the deterministic Task-14 gate for the committed H.2A
evidence. It returns a stable sorted list of error strings (``[]`` == valid):

- the committed staging smoke and hardening reports exist, parse, and match
  their JSON schemas;
- each report's ``report_identity`` self-verifies;
- the hardening report's ``candidate_identity`` / ``artifact_digest`` /
  ``migration_set_identity`` / ``release_config_identity`` and the smoke report's
  ``candidate_identity`` / ``artifact_digest`` match the committed release
  candidate (a candidate mismatch fails);
- the staging deployment artifact digest matches the candidate;
- the gate areas are exactly the expected set (no duplicates, none missing) and
  each gate's own aggregate is consistent with its findings;
- the top-level ``blocking_findings`` / ``advisory_findings`` equal the sorted
  union of every ``gate_results[*]`` finding (a dropped advisory or a hidden
  gate blocking finding fails);
- the report's ``staging_smoke_ref`` binds the committed smoke report identity,
  the committed staging deployment id, and the frozen candidate identities and
  critical-journey result;
- ``eligible_for_authorization`` is consistent with the blocking findings and
  the staging smoke result;
- the advisory finding list was retained (present and a list).

The CLI validates by default. ``--write`` deterministically regenerates the two
committed fixture reports from the committed fixture gate evidence, the frozen
candidate, and the committed staging deployment (no network). ``--live`` runs the
six gates against provider-injected evidence and the staging smoke against the
real deployment URL from ``STAGING_DEPLOYMENT_URL`` (or
``--staging-deployment-url`` / ``--staging-deployment``; used by the hardening
workflow; never creates authorization and never deploys production).
"""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from tooling.hardening.accessibility import evaluate_accessibility
from tooling.hardening.analytics import evaluate_analytics
from tooling.hardening.candidate import (
    CANDIDATE_NAME,
    RELEASE_RELATIVE,
)
from tooling.hardening.findings import AREAS, aggregate_gate
from tooling.hardening.migrations import evaluate_migrations
from tooling.hardening.observability import evaluate_observability
from tooling.hardening.performance import evaluate_performance
from tooling.hardening.report import (
    build_hardening_report,
    hardening_report_identity,
    hardening_report_path,
    write_hardening_report,
)
from tooling.hardening.security import evaluate_security
from tooling.hardening.staging_smoke import (
    HttpJourneyRunner,
    deployment_path,
    load_candidate,
    load_deployment,
    run_staging_smoke,
    smoke_report_identity,
    smoke_report_path,
    write_smoke_report,
)

SCHEMA_RELATIVE = Path("client-projects") / "schema"
SMOKE_SCHEMA_NAME = "h2-smoke-report.schema.json"
HARDENING_SCHEMA_NAME = "h2-hardening-report.schema.json"
HARDENING_RELATIVE = Path("production") / "hardening"
FIXTURE_GATE_EVIDENCE_NAME = "fixture-gate-evidence.json"

REPORT_CANDIDATE_FIELDS: tuple[str, ...] = (
    "candidate_identity",
    "artifact_digest",
    "migration_set_identity",
    "release_config_identity",
)
SMOKE_CANDIDATE_FIELDS: tuple[str, ...] = ("candidate_identity", "artifact_digest")


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_report(
    root: Path, path: Path, label: str, errors: list[str]
) -> Mapping[str, Any]:
    relative = _relative(root, path)
    if not path.is_file():
        errors.append(f"{relative}: missing {label}")
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"{relative}: cannot parse {label}: {exc}")
        return {}
    if not isinstance(payload, Mapping):
        errors.append(f"{relative}: {label} must be a JSON object")
        return {}
    return payload


def _schema_errors(
    root: Path,
    report_path: Path,
    report: Mapping[str, Any],
    schema_name: str,
) -> list[str]:
    if not report:
        return []
    relative = _relative(root, report_path)
    schema_path = Path(root) / SCHEMA_RELATIVE / schema_name
    if not schema_path.is_file():
        return [f"{_relative(root, schema_path)}: missing schema"]
    try:
        schema = _load_json(schema_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{_relative(root, schema_path)}: cannot parse schema: {exc}"]
    validator = Draft202012Validator(schema)
    errors: list[str] = []
    for error in validator.iter_errors(report):
        errors.append(f"{relative}: schema: {error.message}")
    return errors


def _gate_findings_errors(
    report_rel: str,
    report: Mapping[str, Any],
    errors: list[str],
) -> list[Mapping[str, Any]] | None:
    """Cross-check the top-level findings against ``gate_results``.

    Returns the recomputed union of every gate finding (or ``None`` when the
    gate results are too malformed to trust). A stable error is appended when
    the gate areas are not exactly the expected set (no duplicates, none
    missing), when a gate's own aggregate is internally inconsistent, or when
    the top-level blocking/advisory lists do not equal the sorted union of the
    gate findings. This catches a dropped advisory (empty list) and a blocking
    finding hidden inside a gate but omitted from the top level.
    """
    gate_results = report.get("gate_results")
    if not isinstance(gate_results, list):
        errors.append(f"{report_rel}: gate_results must be a list")
        return None

    areas = [
        gate.get("area") for gate in gate_results if isinstance(gate, Mapping)
    ]
    if len(areas) != len(gate_results):
        errors.append(f"{report_rel}: gate_results entries must be objects")
    if len(areas) != len(AREAS) or set(areas) != set(AREAS):
        errors.append(
            f"{report_rel}: gate_results must contain exactly each gate area "
            "once (no duplicates, none missing)"
        )

    union: list[Mapping[str, Any]] = []
    for gate in gate_results:
        if not isinstance(gate, Mapping):
            continue
        area = gate.get("area")
        findings = gate.get("findings")
        if not isinstance(findings, list):
            errors.append(
                f"{report_rel}: gate_results[{area}] findings must be a list"
            )
            continue
        normalized = [finding for finding in findings if isinstance(finding, Mapping)]
        aggregate = aggregate_gate(normalized)
        if gate.get("blocking_findings") != aggregate["blocking_findings"]:
            errors.append(
                f"{report_rel}: gate_results[{area}] blocking_findings do not "
                "match its findings"
            )
        if gate.get("advisory_findings") != aggregate["advisory_findings"]:
            errors.append(
                f"{report_rel}: gate_results[{area}] advisory_findings do not "
                "match its findings"
            )
        if gate.get("passed") is not aggregate["eligible"]:
            errors.append(
                f"{report_rel}: gate_results[{area}] passed is inconsistent "
                "with its findings"
            )
        union.extend(normalized)

    aggregate = aggregate_gate(union)
    if report.get("blocking_findings") != aggregate["blocking_findings"]:
        errors.append(
            f"{report_rel}: blocking_findings does not equal the sorted union "
            "of the gate_results findings"
        )
    if report.get("advisory_findings") != aggregate["advisory_findings"]:
        errors.append(
            f"{report_rel}: advisory_findings does not equal the sorted union "
            "of the gate_results findings"
        )
    return union


def _staging_ref_errors(
    report_rel: str,
    report: Mapping[str, Any],
    smoke: Mapping[str, Any],
    deployment: Mapping[str, Any],
    candidate: Mapping[str, Any],
    errors: list[str],
) -> None:
    """Verify the hardening report's ``staging_smoke_ref`` binding.

    The ref must point at the committed smoke report identity, the committed
    staging deployment id, the frozen candidate identities, and the committed
    smoke critical-journey result. Tampering any field (even with a recomputed
    hardening ``report_identity``) is therefore detected.
    """
    ref = report.get("staging_smoke_ref")
    if not isinstance(ref, Mapping):
        errors.append(f"{report_rel}: staging_smoke_ref must be an object")
        return
    if ref.get("report_identity") != smoke.get("report_identity"):
        errors.append(
            f"{report_rel}: staging_smoke_ref.report_identity does not match "
            "the committed staging smoke report"
        )
    if ref.get("deployment_id") != deployment.get("deployment_id"):
        errors.append(
            f"{report_rel}: staging_smoke_ref.deployment_id does not match the "
            "committed staging deployment"
        )
    if ref.get("artifact_digest") != candidate.get("artifact_digest"):
        errors.append(
            f"{report_rel}: staging_smoke_ref.artifact_digest does not match "
            "the committed release candidate"
        )
    if ref.get("candidate_identity") != candidate.get("candidate_identity"):
        errors.append(
            f"{report_rel}: staging_smoke_ref.candidate_identity does not match "
            "the committed release candidate"
        )
    if bool(ref.get("critical_journeys_passed")) != bool(
        smoke.get("critical_journeys_passed")
    ):
        errors.append(
            f"{report_rel}: staging_smoke_ref.critical_journeys_passed does not "
            "match the committed staging smoke report"
        )


def validate_hardening(root: Path, client_dir: Path) -> list[str]:
    """Return stable sorted H.2A evidence errors (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []

    candidate = load_candidate(client_dir)
    candidate_rel = _relative(
        root, client_dir / RELEASE_RELATIVE / CANDIDATE_NAME
    )

    smoke_path = smoke_report_path(client_dir)
    report_path = hardening_report_path(client_dir)
    smoke = _load_report(root, smoke_path, "staging smoke report", errors)
    report = _load_report(root, report_path, "H.2 hardening report", errors)

    errors.extend(_schema_errors(root, smoke_path, smoke, SMOKE_SCHEMA_NAME))
    errors.extend(
        _schema_errors(root, report_path, report, HARDENING_SCHEMA_NAME)
    )

    smoke_rel = _relative(root, smoke_path)
    report_rel = _relative(root, report_path)

    if smoke and smoke.get("report_identity") != smoke_report_identity(smoke):
        errors.append(f"{smoke_rel}: report_identity does not verify")
    if report and report.get("report_identity") != hardening_report_identity(report):
        errors.append(f"{report_rel}: report_identity does not verify")

    if not candidate:
        errors.append(f"{candidate_rel}: missing or invalid release candidate")
    else:
        for field in REPORT_CANDIDATE_FIELDS:
            if report.get(field) != candidate.get(field):
                errors.append(
                    f"{report_rel}: {field} does not match the committed "
                    "release candidate"
                )
        for field in SMOKE_CANDIDATE_FIELDS:
            if smoke.get(field) != candidate.get(field):
                errors.append(
                    f"{smoke_rel}: {field} does not match the committed "
                    "release candidate"
                )

    deployment = load_deployment(client_dir)
    deployment_rel = _relative(root, deployment_path(client_dir))
    if not deployment:
        errors.append(f"{deployment_rel}: missing or invalid staging deployment")
    elif deployment.get("artifact_digest") != candidate.get("artifact_digest"):
        errors.append(
            f"{deployment_rel}: artifact_digest does not match the committed "
            "release candidate"
        )

    union: list[Mapping[str, Any]] | None = None
    if report:
        advisory = report.get("advisory_findings")
        if not isinstance(advisory, list):
            errors.append(
                f"{report_rel}: advisory_findings must be retained as a list"
            )
        union = _gate_findings_errors(report_rel, report, errors)

    if report and smoke:
        blocking = (
            aggregate_gate(union)["blocking_findings"]
            if union is not None
            else report.get("blocking_findings")
        )
        expected = (not blocking) and bool(
            smoke.get("critical_journeys_passed")
        )
        if report.get("eligible_for_authorization") is not expected:
            errors.append(
                f"{report_rel}: eligible_for_authorization is inconsistent with "
                "the blocking findings and the staging smoke result"
            )
        _staging_ref_errors(
            report_rel, report, smoke, deployment, candidate, errors
        )

    return sorted(set(errors))


def _analytics_events(analytics: Any) -> Any:
    if isinstance(analytics, Mapping):
        return analytics.get("events")
    return analytics


def _evaluate_gates(
    root: Path,
    client_dir: Path,
    candidate: Mapping[str, Any],
    fixture: Mapping[str, Any],
) -> dict[str, list[dict]]:
    migrations = dict(fixture.get("migrations") or {})
    migrations["migration_set_identity"] = candidate.get("migration_set_identity")
    migrations["migration_set_entries"] = candidate.get("migration_set_entries")
    return {
        "security": evaluate_security(root, client_dir, fixture.get("security")),
        "performance": evaluate_performance(
            root, client_dir, fixture.get("performance")
        ),
        "accessibility": evaluate_accessibility(
            root, client_dir, fixture.get("accessibility")
        ),
        "analytics": evaluate_analytics(
            root, client_dir, _analytics_events(fixture.get("analytics"))
        ),
        "observability": evaluate_observability(
            root, client_dir, fixture.get("observability")
        ),
        "migrations": evaluate_migrations(root, client_dir, migrations),
    }


def _fixture_gate_evidence(client_dir: Path) -> Mapping[str, Any]:
    path = Path(client_dir) / HARDENING_RELATIVE / FIXTURE_GATE_EVIDENCE_NAME
    if not path.is_file():
        return {}
    payload = _load_json(path)
    return payload if isinstance(payload, Mapping) else {}


def evaluate_fixture_gates(
    root: Path, client_dir: Path
) -> dict[str, list[dict]]:
    """Evaluate all six gates from the committed deterministic fixture evidence."""
    candidate = load_candidate(client_dir)
    fixture = _fixture_gate_evidence(client_dir)
    return _evaluate_gates(root, client_dir, candidate, fixture)


def _write_reports(
    root: Path,
    client_dir: Path,
    candidate: Mapping[str, Any],
    gate_findings: Mapping[str, list[dict]],
    deployment: Mapping[str, Any],
    runner: Any | None,
) -> tuple[Path, Path]:
    smoke = run_staging_smoke(root, client_dir, deployment, http=runner)
    report = build_hardening_report(
        root, client_dir, candidate, gate_findings, smoke
    )
    return (
        write_smoke_report(root, client_dir, smoke),
        write_hardening_report(root, client_dir, report),
    )


def regenerate_fixture_reports(root: Path, client_dir: Path) -> tuple[Path, Path]:
    """Deterministically regenerate the committed fixture reports (offline)."""
    candidate = load_candidate(client_dir)
    gate_findings = evaluate_fixture_gates(root, client_dir)
    deployment = load_deployment(client_dir)
    return _write_reports(
        root, client_dir, candidate, gate_findings, deployment, None
    )


LIVE_DEPLOYMENT_URL_ENV = "STAGING_DEPLOYMENT_URL"
LIVE_DEPLOYMENT_FILE_ENV = "STAGING_DEPLOYMENT_FILE"
LIVE_DEPLOYMENT_ID_ENV = "STAGING_DEPLOYMENT_ID"


def build_live_deployment(
    candidate: Mapping[str, Any],
    url: str | None = None,
    deployment: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Build the live staging deployment context from a URL and/or artifact.

    The deployment produced by the staging workflow is the authority when
    supplied; a URL from the environment/CLI overrides its ``url``. Missing
    release-binding fields fall back to the frozen candidate so the smoke
    release-identity journey verifies the real build rather than the committed
    placeholder.
    """
    resolved: dict[str, Any] = (
        dict(deployment) if isinstance(deployment, Mapping) else {}
    )
    if url:
        resolved["url"] = url
    resolved.setdefault("environment", "staging")
    resolved.setdefault("status", "succeeded")
    resolved.setdefault("provider", "cloudflare-pages")
    resolved.setdefault("artifact_digest", candidate.get("artifact_digest"))
    resolved.setdefault("candidate_identity", candidate.get("candidate_identity"))
    resolved.setdefault("build_version", candidate.get("build_version"))
    if not resolved.get("deployment_id"):
        deployment_id = os.environ.get(LIVE_DEPLOYMENT_ID_ENV)
        if not deployment_id:
            deployment_id = f"staging-{resolved.get('build_version') or 'unknown'}"
        resolved["deployment_id"] = deployment_id
    return resolved


def _load_live_deployment(
    root: Path,
    client_dir: Path,
    candidate: Mapping[str, Any],
    deployment_url: str | None,
    deployment_file: str | None,
) -> dict[str, Any]:
    """Resolve the live staging deployment from CLI args or the environment."""
    url = deployment_url or os.environ.get(LIVE_DEPLOYMENT_URL_ENV)
    path_value = deployment_file or os.environ.get(LIVE_DEPLOYMENT_FILE_ENV)
    deployment: Mapping[str, Any] | None = None
    if path_value:
        path = Path(path_value)
        if not path.is_absolute():
            path = Path(root) / path
        if not path.is_file():
            raise SystemExit(f"{path_value}: staging deployment artifact not found")
        try:
            payload = _load_json(path)
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise SystemExit(f"{path_value}: cannot parse staging deployment: {exc}")
        deployment = payload if isinstance(payload, Mapping) else None
    if not url and deployment is None:
        raise SystemExit(
            "live hardening requires a staging deployment URL or artifact "
            f"({LIVE_DEPLOYMENT_URL_ENV} / {LIVE_DEPLOYMENT_FILE_ENV})"
        )
    resolved = build_live_deployment(candidate, url, deployment)
    if not isinstance(resolved.get("url"), str) or not resolved.get("url"):
        raise SystemExit(
            "live hardening requires a non-empty staging deployment URL "
            f"({LIVE_DEPLOYMENT_URL_ENV})"
        )
    return resolved


def regenerate_live_reports(
    root: Path,
    client_dir: Path,
    deployment: Mapping[str, Any] | None = None,
    runner: Any | None = None,
) -> tuple[Path, Path]:
    """Regenerate reports from live smoke and provider-injected gate evidence.

    The staging deployment context comes from the environment/CLI (the real URL
    produced by ``staging-deploy``), never from the committed placeholder
    deployment artifact. ``runner`` is injectable so tests stay network-free.
    """
    candidate = load_candidate(client_dir)
    if deployment is None:
        deployment = _load_live_deployment(root, client_dir, candidate, None, None)
    gate_findings = {
        "security": evaluate_security(root, client_dir, None),
        "performance": evaluate_performance(root, client_dir, None),
        "accessibility": evaluate_accessibility(root, client_dir, None),
        "analytics": evaluate_analytics(root, client_dir, None),
        "observability": evaluate_observability(root, client_dir, None),
        "migrations": evaluate_migrations(root, client_dir, None),
    }
    return _write_reports(
        root,
        client_dir,
        candidate,
        gate_findings,
        deployment,
        runner if runner is not None else HttpJourneyRunner(),
    )


def _parse_arguments(
    arguments: list[str],
) -> tuple[bool, bool, str | None, str | None, list[str]]:
    write = False
    live = False
    deployment_url: str | None = None
    deployment_file: str | None = None
    positional: list[str] = []
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--write":
            write = True
        elif argument == "--live":
            live = True
        elif argument in ("--staging-deployment-url", "--staging-deployment"):
            index += 1
            if index >= len(arguments):
                raise SystemExit(f"{argument} requires a value")
            if argument == "--staging-deployment-url":
                deployment_url = arguments[index]
            else:
                deployment_file = arguments[index]
        elif argument.startswith("--"):
            raise SystemExit(f"unknown option: {argument}")
        else:
            positional.append(argument)
        index += 1
    return write, live, deployment_url, deployment_file, positional


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate (default), ``--write``, or ``--live``."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    write, live, deployment_url, deployment_file, positional = _parse_arguments(
        arguments
    )
    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    if write:
        for path in regenerate_fixture_reports(root, client_dir):
            print(_relative(root, path))
        return 0

    if live:
        candidate = load_candidate(client_dir)
        deployment = _load_live_deployment(
            root, client_dir, candidate, deployment_url, deployment_file
        )
        for path in regenerate_live_reports(
            root, client_dir, deployment=deployment
        ):
            print(_relative(root, path))
        return 0

    errors = validate_hardening(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
