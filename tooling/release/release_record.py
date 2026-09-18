"""H.2 immutable production ReleaseRecord (Milestone H.2, Task 9; spec section 18).

Every production release attempt produces exactly one immutable ``ReleaseRecord``
(acceptance criterion 34). The record binds the approved experience, the H.1
foundation evidence, the exact source SHA, the exact built artifact, the exact
migration set, the release configuration, the H.2A hardening evidence, the G
``ProductionAuthorization``, the deployment result, and the production health
result (acceptance criterion 35).

The field names mirror
``packages/agency_operations_core/lib/src/release/release_record.dart`` exactly.
``release_identity`` is the canonical ``sha256:`` identity over every immutable
field *excluding* ``release_identity`` itself, so the record is self-verifying.

Outcome invariants (spec section 17, acceptance criteria 36-38):

- ``healthy`` requires production deployment evidence, production smoke evidence,
  telemetry health evidence, and a non-empty production authorization id;
- ``degraded`` requires at least one incident/advisory reference;
- ``failed`` requires failure evidence and a recovery disposition.

The module is pure and offline. It never creates, mutates, or substitutes for a
``ProductionAuthorization``.
"""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Mapping, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from tooling.hardening.candidate import (
    canonical_identity,
    verify_candidate_artifact,
)
from tooling.hardening.report import load_hardening_report
from tooling.release.evidence import (
    load_artifact_manifest,
    load_h2_authorization,
    load_h2_authorization_ref,
)
from tooling.release.smoke import (
    CHECK_IDS as SMOKE_CHECK_IDS,
    ENVIRONMENT as PRODUCTION_ENVIRONMENT,
    build_fixture_production_deployment,
    load_candidate,
    load_production_smoke_report,
    production_smoke_report_identity,
    run_production_smoke,
    validate_production_smoke,
    write_smoke_report,
)
from tooling.release.telemetry_health import (
    REQUIRED_SAMPLE_COUNT,
    SAMPLE_SPACING_SECONDS,
    build_fixture_samples,
    evaluate_telemetry_health,
    load_telemetry_report,
    telemetry_report_identity,
    validate_telemetry_health,
    write_telemetry_report,
)

RELEASE_RECORD_NAME = "release-record.json"
EVIDENCE_RELATIVE = Path("production") / "evidence"
SCHEMA_RELATIVE = Path("client-projects") / "schema"
SCHEMA_NAME = "h2-release-record.schema.json"

RELEASE_OUTCOMES: tuple[str, ...] = ("healthy", "degraded", "failed")

CANONICAL_FIELDS: tuple[str, ...] = (
    "release_id",
    "client_id",
    "environment",
    "source_sha",
    "artifact_digest",
    "build_version",
    "migration_set",
    "release_config_identity",
    "hardening_report_id",
    "production_authorization_id",
    "staging_evidence",
    "production_smoke_evidence",
    "telemetry_health_evidence",
    "deployment_target",
    "release_status",
    "incident_or_advisory_refs",
    "rollback_or_recovery_ref",
    "previous_known_good_release_id",
    "started_at",
    "completed_at",
)

_SOURCE_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _text(value: Any) -> str | None:
    return value if isinstance(value, str) and value else None


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return []
    return [item for item in value if isinstance(item, str) and item]


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _format_timestamp(value: datetime) -> str:
    return (
        value.astimezone(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def release_record_identity(record: Mapping[str, Any]) -> str:
    """Return the canonical identity over the immutable fields.

    ``release_identity`` is excluded, matching the Dart ``releaseIdentity`` getter.
    """
    body = {key: value for key, value in record.items() if key != "release_identity"}
    return canonical_identity(body)


def _resolve_timestamps(
    deployment: Mapping[str, Any], telemetry_health: Mapping[str, Any]
) -> tuple[str, str]:
    started = _text(deployment.get("started_at"))
    completed = _text(deployment.get("completed_at"))
    samples = telemetry_health.get("samples")
    if (
        isinstance(samples, Sequence)
        and not isinstance(samples, (str, bytes))
        and samples
    ):
        first, last = samples[0], samples[-1]
        if isinstance(first, Mapping) and not started:
            started = _text(first.get("at"))
        if isinstance(last, Mapping) and not completed:
            completed = _text(last.get("at"))

    if not started or not completed:
        raise ValueError("release record requires started_at and completed_at")

    started_dt = _parse_timestamp(started)
    completed_dt = _parse_timestamp(completed)
    if started_dt is None or completed_dt is None:
        raise ValueError("started_at and completed_at must be ISO-8601 timestamps")
    if completed_dt < started_dt:
        raise ValueError("completed_at must not be before started_at")
    return _format_timestamp(started_dt), _format_timestamp(completed_dt)


def _outcome_evidence(
    outcome: str,
    hardening_report: Mapping[str, Any],
    telemetry_health: Mapping[str, Any],
    production_smoke: Mapping[str, Any],
    deployment: Mapping[str, Any],
) -> tuple[list[str], str | None]:
    refs: set[str] = set()
    for source in (deployment, production_smoke, telemetry_health):
        refs.update(_string_list(source.get("incident_refs")))

    if outcome == "degraded":
        findings = hardening_report.get("advisory_findings")
        if isinstance(findings, Sequence) and not isinstance(findings, (str, bytes)):
            for finding in findings:
                if isinstance(finding, Mapping):
                    identifier = finding.get("id")
                    if isinstance(identifier, str) and identifier:
                        refs.add(identifier)

    if outcome == "failed":
        refs.update(_string_list(telemetry_health.get("blocking_reasons")))

    rollback_ref: str | None = None
    if outcome == "failed":
        rollback_ref = _text(deployment.get("rollback_or_recovery_ref")) or _text(
            deployment.get("recovery_ref")
        )
    return sorted(refs), rollback_ref


def build_release_record(
    root: Path,
    client_dir: Path,
    candidate: Mapping[str, Any],
    authorization_ref: Mapping[str, Any],
    hardening_report: Mapping[str, Any],
    staging_smoke: Mapping[str, Any],
    production_smoke: Mapping[str, Any],
    telemetry_health: Mapping[str, Any],
    deployment: Mapping[str, Any],
    outcome: str,
    previous_known_good_release_id: str | None = None,
) -> dict[str, Any]:
    """Build the immutable ReleaseRecord for one production attempt.

    Raises ``ValueError`` when the outcome invariants are violated or a required
    immutable binding is missing.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    candidate = candidate if isinstance(candidate, Mapping) else {}
    authorization_ref = (
        authorization_ref if isinstance(authorization_ref, Mapping) else {}
    )
    hardening_report = (
        hardening_report if isinstance(hardening_report, Mapping) else {}
    )
    staging_smoke = staging_smoke if isinstance(staging_smoke, Mapping) else {}
    production_smoke = production_smoke if isinstance(production_smoke, Mapping) else {}
    telemetry_health = telemetry_health if isinstance(telemetry_health, Mapping) else {}
    deployment = deployment if isinstance(deployment, Mapping) else {}

    if outcome not in RELEASE_OUTCOMES:
        raise ValueError(f"outcome must be one of {RELEASE_OUTCOMES}")

    client_id = _text(candidate.get("client_id"))
    environment = _text(candidate.get("target_environment"))
    source_sha = _text(candidate.get("source_sha"))
    artifact_digest = _text(candidate.get("artifact_digest"))
    build_version = _text(candidate.get("build_version"))
    release_config_identity = _text(candidate.get("release_config_identity"))
    hardening_report_id = _text(hardening_report.get("report_identity"))

    for field, value in (
        ("client_id", client_id),
        ("environment", environment),
        ("source_sha", source_sha),
        ("artifact_digest", artifact_digest),
        ("build_version", build_version),
        ("release_config_identity", release_config_identity),
        ("hardening_report_id", hardening_report_id),
    ):
        if value is None:
            raise ValueError(f"release record requires a non-empty {field}")

    if not _SOURCE_SHA_RE.match(source_sha or ""):
        raise ValueError("source_sha must be 40 lowercase hex characters")
    if not _SHA256_RE.match(artifact_digest or ""):
        raise ValueError("artifact_digest must match ^sha256:[0-9a-f]{64}$")
    if not _SHA256_RE.match(release_config_identity or ""):
        raise ValueError("release_config_identity must match ^sha256:[0-9a-f]{64}$")

    migration_set = candidate.get("migration_set")
    if not isinstance(migration_set, Sequence) or isinstance(
        migration_set, (str, bytes)
    ):
        migration_set = []
    migration_set = [item for item in migration_set if isinstance(item, str)]

    production_authorization_id = _text(
        authorization_ref.get("authorization_id")
    )
    staging_evidence = _text(staging_smoke.get("report_identity"))
    production_smoke_evidence = _text(production_smoke.get("report_identity"))
    telemetry_health_evidence = _text(telemetry_health.get("report_identity"))
    deployment_target = _text(deployment.get("deployment_id")) or _text(
        deployment.get("url")
    )

    incident_refs, rollback_ref = _outcome_evidence(
        outcome, hardening_report, telemetry_health, production_smoke, deployment
    )

    if outcome == "healthy":
        missing = [
            name
            for name, value in (
                ("deployment_target", deployment_target),
                ("production_smoke_evidence", production_smoke_evidence),
                ("telemetry_health_evidence", telemetry_health_evidence),
                ("production_authorization_id", production_authorization_id),
            )
            if value is None
        ]
        if missing:
            raise ValueError(
                "healthy release requires production deployment evidence, "
                "production smoke evidence, telemetry health evidence, and a "
                "production authorization id; missing: " + ", ".join(missing)
            )
    elif outcome == "degraded":
        if not incident_refs:
            raise ValueError(
                "degraded release requires at least one incident/advisory reference"
            )
    elif outcome == "failed":
        if not incident_refs:
            raise ValueError(
                "failed release requires failure evidence (incident/advisory refs)"
            )
        if rollback_ref is None:
            raise ValueError(
                "failed release requires a recovery disposition "
                "(rollback_or_recovery_ref)"
            )

    started_at, completed_at = _resolve_timestamps(deployment, telemetry_health)

    release_id = _text(deployment.get("release_id")) or (
        f"rel-{client_id}-{environment}-{build_version}"
    )

    record: dict[str, Any] = {
        "release_id": release_id,
        "client_id": client_id,
        "environment": environment,
        "source_sha": source_sha,
        "artifact_digest": artifact_digest,
        "build_version": build_version,
        "migration_set": migration_set,
        "release_config_identity": release_config_identity,
        "hardening_report_id": hardening_report_id,
        "production_authorization_id": production_authorization_id,
        "staging_evidence": staging_evidence,
        "production_smoke_evidence": production_smoke_evidence,
        "telemetry_health_evidence": telemetry_health_evidence,
        "deployment_target": deployment_target,
        "release_status": outcome,
        "incident_or_advisory_refs": incident_refs,
        "rollback_or_recovery_ref": rollback_ref,
        "previous_known_good_release_id": previous_known_good_release_id,
        "started_at": started_at,
        "completed_at": completed_at,
    }
    record["release_identity"] = release_record_identity(record)
    return record


def release_record_path(client_dir: Path) -> Path:
    return Path(client_dir) / EVIDENCE_RELATIVE / RELEASE_RECORD_NAME


def load_release_record(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed release record, or ``{}`` when absent/invalid."""
    path = release_record_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def write_release_record(
    root: Path, client_dir: Path, record: Mapping[str, Any]
) -> Path:
    path = release_record_path(client_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return path


def _schema_errors(
    root: Path, record_path: Path, record: Mapping[str, Any]
) -> list[str]:
    relative = _relative(root, record_path)
    schema_path = Path(root) / SCHEMA_RELATIVE / SCHEMA_NAME
    if not schema_path.is_file():
        return [f"{_relative(root, schema_path)}: missing schema"]
    try:
        schema = _load_json(schema_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{_relative(root, schema_path)}: cannot parse schema: {exc}"]
    validator = Draft202012Validator(schema)
    return [
        f"{relative}: schema: {error.message}"
        for error in validator.iter_errors(record)
    ]


def _candidate_binding_errors(
    relative: str, record: Mapping[str, Any], candidate: Mapping[str, Any]
) -> list[str]:
    errors: list[str] = []
    expected = {
        "client_id": candidate.get("client_id"),
        "environment": candidate.get("target_environment"),
        "source_sha": candidate.get("source_sha"),
        "artifact_digest": candidate.get("artifact_digest"),
        "build_version": candidate.get("build_version"),
        "migration_set": list(candidate.get("migration_set") or []),
        "release_config_identity": candidate.get("release_config_identity"),
    }
    for field, value in expected.items():
        if record.get(field) != value:
            errors.append(
                f"{relative}: {field} does not match the committed release candidate"
            )
    return errors


def _authorization_errors(
    root: Path,
    relative: str,
    client_dir: Path,
    record: Mapping[str, Any],
    candidate: Mapping[str, Any],
) -> list[str]:
    errors: list[str] = []
    ref = load_h2_authorization_ref(client_dir)
    if not ref:
        errors.append(
            f"{_relative(root, client_dir / 'production' / 'release' / 'production-authorization-ref.json')}: "
            "missing or invalid"
        )
        return errors
    if record.get("production_authorization_id") != ref.get("authorization_id"):
        errors.append(
            f"{relative}: production_authorization_id does not match the "
            "committed G authorization"
        )
    body = load_h2_authorization(client_dir)
    if not body:
        errors.append(
            f"{relative}: committed G authorization body is missing or invalid"
        )
    else:
        if body.get("authorization_id") != ref.get("authorization_id"):
            errors.append(
                f"{relative}: committed G authorization body id does not match the ref"
            )
        if body.get("source_commit_sha") != candidate.get("source_sha"):
            errors.append(
                f"{relative}: committed G authorization body source_commit_sha does "
                "not match the H.2 candidate"
            )
        build = body.get("build")
        if not isinstance(build, Mapping):
            errors.append(
                f"{relative}: committed G authorization body build hash is missing"
            )
        elif build.get("hash") != candidate.get("artifact_digest"):
            errors.append(
                f"{relative}: committed G authorization body build.hash does not "
                "match the H.2 candidate"
            )
    for field in (
        "candidate_identity",
        "artifact_digest",
        "source_sha",
        "migration_set_identity",
        "release_config_identity",
    ):
        if candidate.get(field) is not None and ref.get(field) != candidate.get(field):
            errors.append(
                f"{relative}: committed G authorization {field} does not match "
                "the H.2 candidate"
            )
    return errors


def _hardening_errors(
    root: Path,
    relative: str,
    client_dir: Path,
    record: Mapping[str, Any],
    candidate: Mapping[str, Any],
) -> list[str]:
    errors: list[str] = []
    report = load_hardening_report(client_dir)
    report_path = client_dir / "production" / "evidence" / "h2-hardening-report.json"
    if not report:
        errors.append(f"{_relative(root, report_path)}: missing or invalid")
        return errors
    if record.get("hardening_report_id") != report.get("report_identity"):
        errors.append(
            f"{relative}: hardening_report_id does not match the committed "
            "hardening report"
        )
    for field in ("candidate_identity", "artifact_digest"):
        if report.get(field) != candidate.get(field):
            errors.append(
                f"{relative}: committed hardening report {field} does not match "
                "the H.2 candidate"
            )
    return errors


def _production_smoke_errors(
    root: Path,
    relative: str,
    client_dir: Path,
    record: Mapping[str, Any],
    candidate: Mapping[str, Any],
) -> list[str]:
    errors: list[str] = []
    report = load_production_smoke_report(client_dir)
    report_path = client_dir / "production" / "evidence" / "production-smoke-report.json"
    if not report:
        errors.append(f"{_relative(root, report_path)}: missing or invalid")
        return errors
    errors.extend(validate_production_smoke(root, client_dir))
    if report.get("report_identity") != production_smoke_report_identity(report):
        errors.append(
            f"{_relative(root, report_path)}: report_identity does not verify"
        )
    if record.get("production_smoke_evidence") != report.get("report_identity"):
        errors.append(
            f"{relative}: production_smoke_evidence does not match the committed "
            "production smoke report"
        )
    if report.get("candidate_identity") != candidate.get("candidate_identity"):
        errors.append(
            f"{relative}: committed production smoke report is bound to another "
            "candidate"
        )
    if report.get("artifact_digest") != candidate.get("artifact_digest"):
        errors.append(
            f"{relative}: committed production smoke report artifact_digest does "
            "not match the H.2 candidate"
        )
    if report.get("environment") != PRODUCTION_ENVIRONMENT:
        errors.append(
            f"{relative}: committed production smoke report environment is not "
            f"{PRODUCTION_ENVIRONMENT}"
        )
    if report.get("low_risk") is not True:
        errors.append(
            f"{relative}: committed production smoke report is not low risk"
        )
    if report.get("uncontrolled_mutations"):
        errors.append(
            f"{relative}: committed production smoke report has uncontrolled "
            "mutations"
        )
    checks = report.get("checks")
    if not isinstance(checks, list):
        errors.append(
            f"{relative}: committed production smoke report checks must be a list"
        )
    else:
        check_ids = [
            check.get("id") for check in checks if isinstance(check, Mapping)
        ]
        if check_ids != list(SMOKE_CHECK_IDS):
            errors.append(
                f"{relative}: committed production smoke report checks do not equal "
                "the canonical check set"
            )
        for check in checks:
            if isinstance(check, Mapping) and check.get("status") != "passed":
                errors.append(
                    f"{relative}: committed production smoke check "
                    f"{check.get('id')} did not pass"
                )
    return errors


def _telemetry_errors(
    root: Path,
    relative: str,
    client_dir: Path,
    record: Mapping[str, Any],
    candidate: Mapping[str, Any],
) -> list[str]:
    errors: list[str] = []
    report = load_telemetry_report(client_dir)
    report_path = client_dir / "production" / "evidence" / "telemetry-health-report.json"
    if not report:
        errors.append(f"{_relative(root, report_path)}: missing or invalid")
        return errors
    errors.extend(validate_telemetry_health(root, client_dir))
    if report.get("report_identity") != telemetry_report_identity(report):
        errors.append(
            f"{_relative(root, report_path)}: report_identity does not verify"
        )
    if record.get("telemetry_health_evidence") != report.get("report_identity"):
        errors.append(
            f"{relative}: telemetry_health_evidence does not match the committed "
            "telemetry health report"
        )
    if report.get("candidate_identity") != candidate.get("candidate_identity"):
        errors.append(
            f"{relative}: committed telemetry health report is bound to another "
            "candidate"
        )
    if report.get("artifact_digest") != candidate.get("artifact_digest"):
        errors.append(
            f"{relative}: committed telemetry health report artifact_digest does "
            "not match the H.2 candidate"
        )
    if report.get("environment") != record.get("environment"):
        errors.append(
            f"{relative}: committed telemetry health report environment does not "
            "match the release record environment"
        )
    if report.get("sample_count") != REQUIRED_SAMPLE_COUNT:
        errors.append(
            f"{relative}: committed telemetry health report sample_count is not "
            f"{REQUIRED_SAMPLE_COUNT}"
        )
    if report.get("spacing_seconds") != SAMPLE_SPACING_SECONDS:
        errors.append(
            f"{relative}: committed telemetry health report spacing_seconds is "
            f"not {SAMPLE_SPACING_SECONDS}"
        )

    derived = evaluate_telemetry_health(
        root,
        client_dir,
        report.get("samples") or [],
        candidate,
    )
    derived_outcome = derived.get("outcome")
    if report.get("outcome") != derived_outcome:
        errors.append(
            f"{relative}: committed telemetry health report outcome "
            f"{report.get('outcome')!r} does not match the re-derived outcome "
            f"{derived_outcome!r}"
        )
    status = record.get("release_status")
    expected_outcome = {
        "healthy": "healthy",
        "degraded": "degraded",
        "failed": "failed",
    }.get(status)
    if expected_outcome is not None and derived_outcome != expected_outcome:
        errors.append(
            f"{relative}: re-derived telemetry health outcome "
            f"{derived_outcome!r} is inconsistent with release_status "
            f"{status!r}"
        )
    return errors


def _outcome_invariant_errors(
    relative: str, record: Mapping[str, Any]
) -> list[str]:
    errors: list[str] = []
    status = record.get("release_status")
    if status not in RELEASE_OUTCOMES:
        errors.append(
            f"{relative}: release_status must be one of {RELEASE_OUTCOMES}"
        )
        return errors
    if status == "healthy":
        for field in (
            "deployment_target",
            "production_smoke_evidence",
            "telemetry_health_evidence",
            "production_authorization_id",
        ):
            if not record.get(field):
                errors.append(
                    f"{relative}: healthy release requires a non-empty {field}"
                )
    elif status == "degraded":
        if not record.get("incident_or_advisory_refs"):
            errors.append(
                f"{relative}: degraded release requires an incident/advisory "
                "reference"
            )
    elif status == "failed":
        if not record.get("incident_or_advisory_refs"):
            errors.append(
                f"{relative}: failed release requires failure evidence"
            )
        if not record.get("rollback_or_recovery_ref"):
            errors.append(
                f"{relative}: failed release requires a recovery disposition"
            )
    return errors


def validate_release_record(root: Path, client_dir: Path) -> list[str]:
    """Validate the committed ReleaseRecord and all of its bindings.

    Returns stable sorted errors; ``[]`` means the record exists, parses, matches
    its schema, self-verifies its identity, binds the committed candidate, the
    committed G authorization, the committed hardening report, the committed
    production smoke report, and the committed telemetry health report, and
    satisfies the release-outcome invariants.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    record_path = release_record_path(client_dir)
    relative = _relative(root, record_path)

    if not record_path.is_file():
        return [f"{relative}: missing release record"]
    try:
        record = _load_json(record_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{relative}: cannot parse release record: {exc}"]
    if not isinstance(record, Mapping):
        return [f"{relative}: release record must be a JSON object"]

    errors: list[str] = []
    errors.extend(_schema_errors(root, record_path, record))

    if record.get("release_identity") != release_record_identity(record):
        errors.append(f"{relative}: release_identity does not verify")

    candidate = load_candidate(client_dir)
    if not candidate:
        errors.append(f"{relative}: committed release candidate is missing or invalid")
    else:
        errors.extend(_candidate_binding_errors(relative, record, candidate))
        manifest = load_artifact_manifest(client_dir)
        errors.extend(
            f"{relative}: {error}"
            for error in verify_candidate_artifact(candidate, manifest)
        )
        errors.extend(
            _authorization_errors(root, relative, client_dir, record, candidate)
        )
        errors.extend(
            _hardening_errors(root, relative, client_dir, record, candidate)
        )
        errors.extend(
            _production_smoke_errors(root, relative, client_dir, record, candidate)
        )
        errors.extend(
            _telemetry_errors(root, relative, client_dir, record, candidate)
        )

    errors.extend(_outcome_invariant_errors(relative, record))
    return sorted(set(errors))


def _parse_arguments(arguments: list[str]) -> tuple[bool, list[str]]:
    write = False
    positional: list[str] = []
    for argument in arguments:
        if argument == "--write":
            write = True
        elif argument.startswith("--"):
            raise SystemExit(f"unknown option: {argument}")
        else:
            positional.append(argument)
    return write, positional


def _regenerate_fixtures(
    root: Path, client_dir: Path
) -> tuple[Mapping[str, Any], Mapping[str, Any], dict[str, Any], dict[str, Any]]:
    """Regenerate the committed smoke + telemetry reports and return the inputs."""
    candidate = load_candidate(client_dir)
    deployment = build_fixture_production_deployment(candidate)
    production_smoke = run_production_smoke(root, client_dir, deployment)
    telemetry_health = evaluate_telemetry_health(
        root, client_dir, build_fixture_samples(candidate), candidate
    )
    write_smoke_report(root, client_dir, production_smoke)
    write_telemetry_report(root, client_dir, telemetry_health)
    return candidate, deployment, production_smoke, telemetry_health


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate (default) or ``--write`` the release record.

    ``--write`` deterministically regenerates the committed production smoke,
    telemetry health, and release-record fixtures from the committed candidate,
    hardening report, staging smoke report, and synthetic G authorization ref.
    It never deploys anything and never creates authorization.
    """
    arguments = list(sys.argv[1:] if argv is None else argv)
    write, positional = _parse_arguments(arguments)
    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    if write:
        (
            candidate,
            deployment,
            production_smoke,
            telemetry_health,
        ) = _regenerate_fixtures(root, client_dir)
        authorization_ref = load_h2_authorization_ref(client_dir)
        hardening_report = load_hardening_report(client_dir)
        staging_smoke = _load_json(
            client_dir / "production" / "evidence" / "staging-smoke-report.json"
        )
        record = build_release_record(
            root,
            client_dir,
            candidate,
            authorization_ref,
            hardening_report,
            staging_smoke,
            production_smoke,
            telemetry_health,
            deployment,
            "healthy",
        )
        path = write_release_record(root, client_dir, record)
        print(_relative(root, path))
        return 0

    errors = validate_release_record(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
