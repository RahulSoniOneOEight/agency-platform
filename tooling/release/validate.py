"""H.2 reference end-to-end release validator (Milestone H.2, Task 13).

This is the Task-14 entry point for the reference-commerce release proof. It
composes the *complete* H.2 evidence chain into a single deterministic, offline
gate:

    candidate identity
    -> H.2A hardening evidence (all six gates)
    -> exact Milestone-G production authorization (H.2 -> G bridge)
    -> exact-artifact promotion (no rebuild)
    -> production smoke
    -> telemetry health
    -> immutable ReleaseRecord
    -> governed recovery evidence

``validate_release`` returns a stable sorted list of error strings; ``[]`` means
the committed reference proof is internally consistent, self-verifying, and
authorized end to end. It performs no network access, never deploys anything, and
never creates, grants, or mutates a ``ProductionAuthorization``.

The committed reference proof is a *healthy* end-to-end production release
(acceptance criterion 46), so this validator also requires the committed
ReleaseRecord to be ``healthy``; the failed-release recovery path is proved
separately by the governed recovery evidence that is validated here.
"""

from __future__ import annotations

import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from tooling.hardening.candidate import validate_candidate
from tooling.hardening.validate import validate_hardening
from tooling.production_authorization.errors import ProductionAuthorizationError
from tooling.production_authorization.models import ProductionAuthorization
from tooling.release.coordinator import (
    H2AuthorizationBridgeError,
    verify_h2_authorized_candidate,
)
from tooling.release.evidence import (
    build_h2_g_candidate,
    load_artifact_manifest,
    load_f_report,
    load_h2_authorization,
    load_h2_authorization_ref,
    load_h2_candidate,
    load_hardening_report,
    load_staging_deployment,
)
from tooling.release.recovery import validate_recovery
from tooling.release.release_record import (
    load_release_record,
    load_staging_smoke_report,
    validate_release_record,
)
from tooling.release.smoke import load_production_smoke_report
from tooling.release.telemetry_health import load_telemetry_report

RELEASE_RELATIVE = Path("production") / "release"
EVIDENCE_RELATIVE = Path("production") / "evidence"
AUTHORIZATION_BODY_RELATIVE = (
    Path("release") / "reference-proof" / "production-authorization-v0001.json"
)

CANDIDATE_NAME = "candidate.json"
MANIFEST_NAME = "artifact-manifest.json"
STAGING_DEPLOYMENT_NAME = "staging-deployment.json"
AUTHORIZATION_REF_NAME = "production-authorization-ref.json"
HARDENING_REPORT_NAME = "h2-hardening-report.json"
STAGING_SMOKE_NAME = "staging-smoke-report.json"
PRODUCTION_SMOKE_NAME = "production-smoke-report.json"
TELEMETRY_REPORT_NAME = "telemetry-health-report.json"
RELEASE_RECORD_NAME = "release-record.json"

REFERENCE_OUTCOME = "healthy"


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _candidate_errors(root: Path, client_dir: Path) -> list[str]:
    """Candidate identity / artifact-manifest integrity (Task 5)."""
    return list(validate_candidate(root, client_dir))


def _hardening_errors(root: Path, client_dir: Path) -> list[str]:
    """H.2A hardening evidence, plus the explicit eligibility gate.

    ``validate_hardening`` proves the committed report is internally consistent
    with the committed fixture gate evidence; the extra checks here ensure the
    frozen candidate is actually *eligible* to be put forward for authorization
    and that no open blocking finding (e.g. a failed migration gate) is present.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    errors = list(validate_hardening(root, client_dir))
    report = load_hardening_report(client_dir)
    report_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / HARDENING_REPORT_NAME
    )
    if not report:
        errors.append(f"{report_rel}: missing or invalid H.2 hardening report")
        return sorted(set(errors))
    if report.get("eligible_for_authorization") is not True:
        errors.append(
            f"{report_rel}: hardening report is not eligible for authorization"
        )
    blocking = report.get("blocking_findings")
    if isinstance(blocking, list):
        for finding in blocking:
            if isinstance(finding, Mapping):
                errors.append(
                    f"{report_rel}: open blocking finding {finding.get('id')!r}"
                )
    return sorted(set(errors))


def _authorization_bridge_errors(root: Path, client_dir: Path) -> list[str]:
    """Project the H.2 candidate to G and verify the exact authorization.

    G validity is delegated in full to the existing release gate via
    ``verify_h2_authorized_candidate``; the H.2-only bindings are checked there
    too. Failures are normalized to stable error strings (never raised).
    """
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []

    candidate = load_h2_candidate(client_dir)
    candidate_rel = _relative(
        root, client_dir / RELEASE_RELATIVE / CANDIDATE_NAME
    )
    ref_rel = _relative(
        root, client_dir / RELEASE_RELATIVE / AUTHORIZATION_REF_NAME
    )
    body_rel = _relative(root, client_dir / AUTHORIZATION_BODY_RELATIVE)

    if not candidate:
        return [f"{candidate_rel}: missing or invalid H.2 release candidate"]

    report = load_hardening_report(client_dir)
    f_report = load_f_report(root, client_dir)
    ref = load_h2_authorization_ref(client_dir)
    body = load_h2_authorization(client_dir)

    if not ref:
        errors.append(f"{ref_rel}: missing or invalid G authorization ref")
        return sorted(set(errors))
    if not body:
        errors.append(
            f"{body_rel}: missing or invalid committed G authorization body"
        )
        return sorted(set(errors))

    try:
        g_candidate = build_h2_g_candidate(candidate, report, f_report)
    except ValueError as exc:
        errors.append(
            f"{ref_rel}: cannot project the H.2 candidate into the G candidate: "
            f"{exc}"
        )
        return sorted(set(errors))

    try:
        authorization = ProductionAuthorization.from_dict(body)
    except ProductionAuthorizationError as exc:
        errors.append(f"{body_rel}: committed G authorization is invalid: {exc}")
        return sorted(set(errors))

    try:
        verify_h2_authorized_candidate(candidate, g_candidate, authorization)
    except H2AuthorizationBridgeError as exc:
        errors.append(f"{ref_rel}: {exc}")
    except ProductionAuthorizationError as exc:
        errors.append(f"{ref_rel}: {exc}")
    return sorted(set(errors))


def _promotion_errors(root: Path, client_dir: Path) -> list[str]:
    """Prove the no-rebuild, exact-artifact promotion chain.

    Every artifact digest in the chain -- the committed manifest, the staged
    deployment, the authorization ref and body, the promoted production smoke
    report, the telemetry report, and the ReleaseRecord -- must equal the frozen
    candidate digest, and the source SHA must be identical across the candidate,
    the authorization, and the record. This is the end-to-end ``no rebuild after
    authorization`` proof (acceptance criteria 15, 16, and 41). The ReleaseRecord
    ``staging_evidence`` binding is checked here as well.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []

    candidate = load_h2_candidate(client_dir)
    if not candidate:
        return [
            f"{_relative(root, client_dir / RELEASE_RELATIVE / CANDIDATE_NAME)}: "
            "missing or invalid H.2 release candidate"
        ]

    digest = candidate.get("artifact_digest")
    source_sha = candidate.get("source_sha")
    candidate_identity = candidate.get("candidate_identity")

    def digest_mismatch(label: str, value: Any, reference: str) -> None:
        if value != digest:
            errors.append(
                f"{reference}: {label} artifact digest {value!r} does not match "
                f"the frozen candidate {digest!r} (no-rebuild violated)"
            )

    manifest = load_artifact_manifest(client_dir)
    digest_mismatch(
        "manifest",
        manifest.get("artifact_digest"),
        _relative(root, client_dir / RELEASE_RELATIVE / MANIFEST_NAME),
    )

    staging = load_staging_deployment(client_dir)
    staging_rel = _relative(
        root, client_dir / RELEASE_RELATIVE / STAGING_DEPLOYMENT_NAME
    )
    digest_mismatch("staged", staging.get("artifact_digest"), staging_rel)
    if staging.get("candidate_identity") != candidate_identity:
        errors.append(
            f"{staging_rel}: candidate_identity does not match the frozen candidate"
        )

    ref = load_h2_authorization_ref(client_dir)
    ref_rel = _relative(
        root, client_dir / RELEASE_RELATIVE / AUTHORIZATION_REF_NAME
    )
    digest_mismatch("authorized", ref.get("artifact_digest"), ref_rel)
    if ref.get("source_sha") != source_sha:
        errors.append(
            f"{ref_rel}: source_sha does not match the frozen candidate"
        )

    body = load_h2_authorization(client_dir)
    body_rel = _relative(root, client_dir / AUTHORIZATION_BODY_RELATIVE)
    build = body.get("build")
    build_hash = build.get("hash") if isinstance(build, Mapping) else None
    digest_mismatch("authorized", build_hash, body_rel)
    if body.get("source_commit_sha") != source_sha:
        errors.append(
            f"{body_rel}: source_commit_sha does not match the frozen candidate"
        )

    smoke = load_production_smoke_report(client_dir)
    smoke_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / PRODUCTION_SMOKE_NAME
    )
    promoted = smoke.get("artifact_digest")
    if promoted != digest:
        errors.append(
            f"{smoke_rel}: promoted artifact digest {promoted!r} does not match "
            f"the staged/authorized artifact {digest!r} (no-rebuild violated)"
        )
    if smoke.get("candidate_identity") != candidate_identity:
        errors.append(
            f"{smoke_rel}: candidate_identity does not match the frozen candidate"
        )

    telemetry = load_telemetry_report(client_dir)
    telemetry_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / TELEMETRY_REPORT_NAME
    )
    digest_mismatch(
        "telemetry", telemetry.get("artifact_digest"), telemetry_rel
    )
    if telemetry.get("candidate_identity") != candidate_identity:
        errors.append(
            f"{telemetry_rel}: candidate_identity does not match the frozen "
            "candidate"
        )

    record = load_release_record(client_dir)
    record_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / RELEASE_RECORD_NAME
    )
    digest_mismatch("release record", record.get("artifact_digest"), record_rel)
    if record.get("source_sha") != source_sha:
        errors.append(
            f"{record_rel}: source_sha does not match the frozen candidate"
        )

    staging_smoke = load_staging_smoke_report(client_dir)
    staging_smoke_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / STAGING_SMOKE_NAME
    )
    if record.get("staging_evidence") != staging_smoke.get("report_identity"):
        errors.append(
            f"{record_rel}: staging_evidence does not bind the committed staging "
            f"smoke report {staging_smoke_rel}"
        )

    return sorted(set(errors))


def _production_health_errors(root: Path, client_dir: Path) -> list[str]:
    """Production smoke and bounded telemetry health must both be healthy."""
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []

    smoke = load_production_smoke_report(client_dir)
    smoke_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / PRODUCTION_SMOKE_NAME
    )
    if not smoke:
        errors.append(f"{smoke_rel}: missing or invalid production smoke report")
    else:
        checks = smoke.get("checks")
        if not isinstance(checks, list):
            errors.append(f"{smoke_rel}: checks must be a list")
        else:
            for check in checks:
                if isinstance(check, Mapping) and check.get("status") != "passed":
                    errors.append(
                        f"{smoke_rel}: production smoke check "
                        f"{check.get('id')!r} did not pass"
                    )
        if smoke.get("low_risk") is not True:
            errors.append(f"{smoke_rel}: production smoke is not low risk")
        if smoke.get("uncontrolled_mutations"):
            errors.append(
                f"{smoke_rel}: production smoke has uncontrolled mutations"
            )

    telemetry = load_telemetry_report(client_dir)
    telemetry_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / TELEMETRY_REPORT_NAME
    )
    if not telemetry:
        errors.append(
            f"{telemetry_rel}: missing or invalid telemetry health report"
        )
    else:
        outcome = telemetry.get("outcome")
        if outcome != REFERENCE_OUTCOME:
            errors.append(
                f"{telemetry_rel}: telemetry health outcome {outcome!r} is not "
                f"{REFERENCE_OUTCOME}"
            )
        reasons = telemetry.get("blocking_reasons")
        if isinstance(reasons, list):
            for reason in reasons:
                if isinstance(reason, str) and reason:
                    errors.append(f"{telemetry_rel}: {reason}")

    return sorted(set(errors))


def _release_record_errors(root: Path, client_dir: Path) -> list[str]:
    """The immutable ReleaseRecord and its bindings, plus the healthy outcome."""
    root = Path(root)
    client_dir = Path(client_dir)
    errors = list(validate_release_record(root, client_dir))
    record = load_release_record(client_dir)
    record_rel = _relative(
        root, client_dir / EVIDENCE_RELATIVE / RELEASE_RECORD_NAME
    )
    if record and record.get("release_status") != REFERENCE_OUTCOME:
        errors.append(
            f"{record_rel}: reference proof release_status must be "
            f"{REFERENCE_OUTCOME!r}"
        )
    return sorted(set(errors))


def validate_release(root: Path, client_dir: Path) -> list[str]:
    """Validate the complete committed H.2 reference release proof.

    Returns stable sorted errors; ``[]`` means the candidate identity, the H.2A
    hardening evidence, the exact Milestone-G authorization, the no-rebuild
    artifact promotion, the production smoke, the telemetry health window, the
    immutable ReleaseRecord, and the governed recovery evidence are all present,
    self-verifying, and mutually consistent. No network access is performed.
    """
    root = Path(root)
    client_dir = Path(client_dir)

    errors: list[str] = []
    errors.extend(_candidate_errors(root, client_dir))
    errors.extend(_hardening_errors(root, client_dir))
    errors.extend(_authorization_bridge_errors(root, client_dir))
    errors.extend(_promotion_errors(root, client_dir))
    errors.extend(_production_health_errors(root, client_dir))
    errors.extend(_release_record_errors(root, client_dir))
    errors.extend(validate_recovery(root, client_dir))
    return sorted(set(errors))


def _parse_arguments(arguments: list[str]) -> list[str]:
    positional: list[str] = []
    for argument in arguments:
        if argument.startswith("--"):
            raise SystemExit(f"unknown option: {argument}")
        positional.append(argument)
    return positional


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate the committed reference release proof.

    ``python -m tooling.release.validate client-projects/reference-commerce``
    """
    arguments = list(sys.argv[1:] if argv is None else argv)
    positional = _parse_arguments(arguments)
    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    errors = validate_release(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
