"""Deterministic H.2 ReleaseRecord tests (Milestone H.2, Task 9).

Flutter-free and offline. These tests prove the committed release record is
self-verifying and bound to the committed candidate, G authorization, hardening
report, production smoke report, and telemetry health report; that the healthy,
degraded, and failed outcome invariants are enforced; and that the committed
fixtures validate against their JSON schemas.
"""

from __future__ import annotations

import contextlib
import copy
import json
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

from jsonschema import Draft202012Validator

from tooling.hardening.report import load_hardening_report
from tooling.release.evidence import h2_authorization_path, load_h2_authorization_ref
from tooling.release.release_record import (
    _hardening_errors,
    _production_smoke_errors,
    build_release_record,
    load_release_record,
    release_record_identity,
    release_record_path,
    validate_release_record,
)
from tooling.release.smoke import (
    build_fixture_production_deployment,
    load_candidate,
    production_smoke_report_identity,
    run_production_smoke,
)
from tooling.release.telemetry_health import (
    build_fixture_samples,
    evaluate_telemetry_health,
    telemetry_report_identity,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SCHEMA_DIR = ROOT / "client-projects" / "schema"
EVIDENCE = CLIENT / "production" / "evidence"
RELEASE_RECORD = EVIDENCE / "release-record.json"
STAGING_SMOKE = EVIDENCE / "staging-smoke-report.json"
SMOKE_REPORT = EVIDENCE / "production-smoke-report.json"
TELEMETRY_REPORT = EVIDENCE / "telemetry-health-report.json"


def _validate(record: dict, **patches: object) -> list[str]:
    """Validate *record* with release_record loaders replaced by *patches*."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "release-record.json"
        path.write_text(json.dumps(record), encoding="utf-8")
        with mock.patch(
            "tooling.release.release_record.release_record_path", return_value=path
        ):
            with contextlib.ExitStack() as stack:
                for target, value in patches.items():
                    stack.enter_context(
                        mock.patch(
                            f"tooling.release.release_record.{target}",
                            return_value=value,
                        )
                    )
                return validate_release_record(ROOT, CLIENT)


def _recomputed_record(**evidence_updates: object) -> dict:
    record = dict(_load(RELEASE_RECORD))
    record.update(evidence_updates)
    record["release_identity"] = release_record_identity(record)
    return record


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _inputs() -> dict:
    candidate = dict(load_candidate(CLIENT))
    deployment = build_fixture_production_deployment(candidate)
    production_smoke = run_production_smoke(ROOT, CLIENT, deployment)
    telemetry_health = evaluate_telemetry_health(
        ROOT, CLIENT, build_fixture_samples(candidate), candidate
    )
    return {
        "candidate": candidate,
        "deployment": deployment,
        "production_smoke": production_smoke,
        "telemetry_health": telemetry_health,
        "authorization_ref": dict(load_h2_authorization_ref(CLIENT)),
        "hardening_report": dict(load_hardening_report(CLIENT)),
        "staging_smoke": dict(_load(STAGING_SMOKE)),
    }


def _build(inputs: dict, outcome: str = "healthy", **overrides):
    values = dict(inputs)
    values.update(overrides)
    return build_release_record(
        ROOT,
        CLIENT,
        values["candidate"],
        values["authorization_ref"],
        values["hardening_report"],
        values["staging_smoke"],
        values["production_smoke"],
        values["telemetry_health"],
        values["deployment"],
        outcome,
    )


class ReleaseRecordFixtureTests(unittest.TestCase):
    def test_validate_release_record_is_clean(self):
        self.assertEqual([], validate_release_record(ROOT, CLIENT))

    def test_committed_record_matches_builder_output(self):
        committed = _load(RELEASE_RECORD)
        expected = _build(_inputs())
        self.assertEqual(committed, expected)

    def test_committed_record_identity_self_verifies(self):
        committed = _load(RELEASE_RECORD)
        self.assertEqual(
            committed["release_identity"], release_record_identity(committed)
        )

    def test_committed_record_is_healthy_and_bound(self):
        committed = _load(RELEASE_RECORD)
        candidate = dict(load_candidate(CLIENT))
        self.assertEqual("healthy", committed["release_status"])
        self.assertEqual(candidate["source_sha"], committed["source_sha"])
        self.assertEqual(candidate["artifact_digest"], committed["artifact_digest"])
        self.assertEqual(
            candidate["release_config_identity"],
            committed["release_config_identity"],
        )
        self.assertEqual(
            "pa-reference-commerce-production-h2-0001",
            committed["production_authorization_id"],
        )
        self.assertTrue(committed["production_smoke_evidence"])
        self.assertTrue(committed["telemetry_health_evidence"])
        self.assertTrue(committed["deployment_target"])


class ReleaseRecordOutcomeInvariantTests(unittest.TestCase):
    def test_healthy_requires_deployment_evidence(self):
        with self.assertRaises(ValueError):
            _build(_inputs(), deployment={})

    def test_healthy_requires_production_smoke_evidence(self):
        with self.assertRaises(ValueError):
            _build(_inputs(), production_smoke={})

    def test_healthy_requires_telemetry_health_evidence(self):
        with self.assertRaises(ValueError):
            _build(_inputs(), telemetry_health={})

    def test_healthy_requires_production_authorization_id(self):
        with self.assertRaises(ValueError):
            _build(_inputs(), authorization_ref={})

    def test_degraded_requires_incident_or_advisory_refs(self):
        hardening = {
            **load_hardening_report(CLIENT),
            "advisory_findings": [],
        }
        with self.assertRaises(ValueError):
            _build(_inputs(), outcome="degraded", hardening_report=hardening)

    def test_degraded_builds_with_advisory_refs(self):
        record = _build(_inputs(), outcome="degraded")
        self.assertEqual("degraded", record["release_status"])
        self.assertTrue(record["incident_or_advisory_refs"])

    def test_failed_requires_failure_evidence(self):
        telemetry = {**_inputs()["telemetry_health"], "blocking_reasons": []}
        with self.assertRaises(ValueError):
            _build(_inputs(), outcome="failed", telemetry_health=telemetry)

    def test_failed_requires_recovery_disposition(self):
        inputs = _inputs()
        telemetry = {
            **inputs["telemetry_health"],
            "blocking_reasons": ["sample[0]: deployment unreachable"],
        }
        with self.assertRaises(ValueError):
            _build(inputs, outcome="failed", telemetry_health=telemetry)

    def test_failed_builds_with_failure_and_recovery(self):
        inputs = _inputs()
        telemetry = {
            **inputs["telemetry_health"],
            "blocking_reasons": ["sample[0]: deployment unreachable"],
        }
        deployment = {
            **inputs["deployment"],
            "rollback_or_recovery_ref": "production/hardening/recovery-policy.yaml",
        }
        record = _build(
            inputs,
            outcome="failed",
            telemetry_health=telemetry,
            deployment=deployment,
        )
        self.assertEqual("failed", record["release_status"])
        self.assertTrue(record["incident_or_advisory_refs"])
        self.assertEqual(
            "production/hardening/recovery-policy.yaml",
            record["rollback_or_recovery_ref"],
        )


class ReleaseRecordIdentityTests(unittest.TestCase):
    def test_identity_is_stable(self):
        first = _build(_inputs())
        second = _build(_inputs())
        self.assertEqual(first["release_identity"], second["release_identity"])
        self.assertEqual(first, second)

    def test_identity_changes_when_a_field_is_tampered(self):
        record = _build(_inputs())
        tampered = dict(record)
        tampered["completed_at"] = "2026-09-18T10:11:00.000Z"
        self.assertNotEqual(
            record["release_identity"], release_record_identity(tampered)
        )

    def test_tampered_committed_record_fails_validation(self):
        tampered = dict(_load(RELEASE_RECORD))
        tampered["release_identity"] = "sha256:" + "0" * 64
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release-record.json"
            path.write_text(json.dumps(tampered), encoding="utf-8")
            with mock.patch(
                "tooling.release.release_record.release_record_path",
                return_value=path,
            ):
                errors = validate_release_record(ROOT, CLIENT)
        self.assertTrue(
            any("release_identity does not verify" in error for error in errors),
            errors,
        )

    def test_validate_catches_healthy_missing_evidence(self):
        record = dict(_load(RELEASE_RECORD))
        record["production_smoke_evidence"] = None
        record["release_identity"] = release_record_identity(record)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release-record.json"
            path.write_text(json.dumps(record), encoding="utf-8")
            with mock.patch(
                "tooling.release.release_record.release_record_path",
                return_value=path,
            ):
                errors = validate_release_record(ROOT, CLIENT)
        self.assertTrue(
            any(
                "healthy release requires a non-empty production_smoke_evidence"
                in error
                for error in errors
            ),
            errors,
        )

    def test_candidate_mismatch_is_caught(self):
        tampered = dict(load_candidate(CLIENT))
        tampered["artifact_digest"] = "sha256:" + "1" * 64
        with mock.patch(
            "tooling.release.release_record.load_candidate",
            return_value=tampered,
        ):
            errors = validate_release_record(ROOT, CLIENT)
        self.assertTrue(
            any(
                "artifact_digest does not match the committed release candidate"
                in error
                for error in errors
            ),
            errors,
        )

    def test_authorization_mismatch_is_caught(self):
        tampered = dict(load_h2_authorization_ref(CLIENT))
        tampered["authorization_id"] = "pa-tampered-0001"
        with mock.patch(
            "tooling.release.release_record.load_h2_authorization_ref",
            return_value=tampered,
        ):
            errors = validate_release_record(ROOT, CLIENT)
        self.assertTrue(
            any(
                "production_authorization_id does not match the committed G "
                "authorization" in error
                for error in errors
            ),
            errors,
        )


class ReleaseEvidenceContentTests(unittest.TestCase):
    """The validator re-validates evidence content, never trusting metadata."""

    def test_empty_smoke_checks_are_rejected(self):
        report = dict(_load(SMOKE_REPORT))
        report["checks"] = []
        report["report_identity"] = production_smoke_report_identity(report)
        record = _recomputed_record(
            production_smoke_evidence=report["report_identity"]
        )
        errors = _validate(record, load_production_smoke_report=report)
        self.assertTrue(
            any(
                "checks do not equal the canonical check set" in error
                for error in errors
            ),
            errors,
        )

    def test_truncated_telemetry_samples_with_lying_sample_count_are_rejected(self):
        report = dict(_load(TELEMETRY_REPORT))
        report["samples"] = report["samples"][:3]
        report["sample_count"] = 5
        report["spacing_seconds"] = 60
        report["outcome"] = "healthy"
        report["report_identity"] = telemetry_report_identity(report)
        record = _recomputed_record(
            telemetry_health_evidence=report["report_identity"]
        )
        errors = _validate(record, load_telemetry_report=report)
        self.assertTrue(
            any("does not match the re-derived outcome" in error for error in errors),
            errors,
        )

    def test_tampered_telemetry_spacing_is_rejected(self):
        report = copy.deepcopy(_load(TELEMETRY_REPORT))
        moved = datetime.fromisoformat(
            report["samples"][3]["at"].replace("Z", "+00:00")
        ) + timedelta(seconds=60)
        report["samples"][3]["at"] = moved.isoformat().replace("+00:00", "Z")
        report["report_identity"] = telemetry_report_identity(report)
        record = _recomputed_record(
            telemetry_health_evidence=report["report_identity"]
        )
        errors = _validate(record, load_telemetry_report=report)
        self.assertTrue(
            any("does not match the re-derived outcome" in error for error in errors),
            errors,
        )

    def test_telemetry_environment_mismatch_is_rejected(self):
        report = dict(_load(TELEMETRY_REPORT))
        report["environment"] = "staging"
        report["report_identity"] = telemetry_report_identity(report)
        record = _recomputed_record(
            telemetry_health_evidence=report["report_identity"]
        )
        errors = _validate(record, load_telemetry_report=report)
        self.assertTrue(
            any(
                "environment does not match the release record environment" in error
                for error in errors
            ),
            errors,
        )

    def test_telemetry_artifact_digest_mismatch_is_rejected(self):
        report = dict(_load(TELEMETRY_REPORT))
        report["artifact_digest"] = "sha256:" + "1" * 64
        report["report_identity"] = telemetry_report_identity(report)
        record = _recomputed_record(
            telemetry_health_evidence=report["report_identity"]
        )
        errors = _validate(record, load_telemetry_report=report)
        self.assertTrue(
            any(
                "artifact_digest does not match the H.2 candidate" in error
                for error in errors
            ),
            errors,
        )

    def test_authorization_body_source_sha_mismatch_is_rejected(self):
        body = dict(_load(h2_authorization_path(CLIENT)))
        body["source_commit_sha"] = "0" * 40
        with mock.patch(
            "tooling.release.release_record.load_h2_authorization",
            return_value=body,
        ):
            errors = validate_release_record(ROOT, CLIENT)
        self.assertTrue(
            any(
                "source_commit_sha does not match the H.2 candidate" in error
                for error in errors
            ),
            errors,
        )

    def test_authorization_body_build_hash_mismatch_is_rejected(self):
        body = dict(_load(h2_authorization_path(CLIENT)))
        body["build"] = {**body["build"], "hash": "sha256:" + "2" * 64}
        with mock.patch(
            "tooling.release.release_record.load_h2_authorization",
            return_value=body,
        ):
            errors = validate_release_record(ROOT, CLIENT)
        self.assertTrue(
            any(
                "build.hash does not match the H.2 candidate" in error
                for error in errors
            ),
            errors,
        )


class ReleaseEvidenceHelperBindingTests(unittest.TestCase):
    """Direct coverage of the smoke/hardening binding-mismatch branches."""

    def _arguments(self) -> tuple[str, Path, dict, dict]:
        return (
            "release-record.json",
            CLIENT,
            dict(_load(RELEASE_RECORD)),
            dict(load_candidate(CLIENT)),
        )

    def test_production_smoke_candidate_binding_mismatch(self):
        report = dict(_load(SMOKE_REPORT))
        report["candidate_identity"] = "sha256:" + "2" * 64
        relative, client_dir, record, candidate = self._arguments()
        with mock.patch(
            "tooling.release.release_record.load_production_smoke_report",
            return_value=report,
        ):
            errors = _production_smoke_errors(
                ROOT, relative, client_dir, record, candidate
            )
        self.assertTrue(
            any("bound to another candidate" in error for error in errors), errors
        )

    def test_production_smoke_artifact_binding_mismatch(self):
        report = dict(_load(SMOKE_REPORT))
        report["artifact_digest"] = "sha256:" + "3" * 64
        relative, client_dir, record, candidate = self._arguments()
        with mock.patch(
            "tooling.release.release_record.load_production_smoke_report",
            return_value=report,
        ):
            errors = _production_smoke_errors(
                ROOT, relative, client_dir, record, candidate
            )
        self.assertTrue(
            any(
                "artifact_digest does not match the H.2 candidate" in error
                for error in errors
            ),
            errors,
        )

    def test_hardening_candidate_binding_mismatch(self):
        report = dict(load_hardening_report(CLIENT))
        report["candidate_identity"] = "sha256:" + "4" * 64
        relative, client_dir, record, candidate = self._arguments()
        with mock.patch(
            "tooling.release.release_record.load_hardening_report",
            return_value=report,
        ):
            errors = _hardening_errors(
                ROOT, relative, client_dir, record, candidate
            )
        self.assertTrue(
            any(
                "candidate_identity does not match the H.2 candidate" in error
                for error in errors
            ),
            errors,
        )

    def test_hardening_artifact_binding_mismatch(self):
        report = dict(load_hardening_report(CLIENT))
        report["artifact_digest"] = "sha256:" + "5" * 64
        relative, client_dir, record, candidate = self._arguments()
        with mock.patch(
            "tooling.release.release_record.load_hardening_report",
            return_value=report,
        ):
            errors = _hardening_errors(
                ROOT, relative, client_dir, record, candidate
            )
        self.assertTrue(
            any(
                "artifact_digest does not match the H.2 candidate" in error
                for error in errors
            ),
            errors,
        )


class SchemaValidationTests(unittest.TestCase):
    def _schema(self, name: str) -> dict:
        return json.loads((SCHEMA_DIR / name).read_text(encoding="utf-8"))

    def _errors(self, schema: dict, payload: object) -> list:
        return list(Draft202012Validator(schema).iter_errors(payload))

    def test_release_record_schema_validates_committed_fixture(self):
        self.assertEqual(
            [], self._errors(self._schema("h2-release-record.schema.json"), _load(RELEASE_RECORD))
        )

    def test_telemetry_schema_validates_committed_fixture(self):
        self.assertEqual(
            [],
            self._errors(
                self._schema("h2-telemetry-health-report.schema.json"),
                _load(EVIDENCE / "telemetry-health-report.json"),
            ),
        )

    def test_release_record_schema_rejects_unknown_field(self):
        payload = dict(_load(RELEASE_RECORD))
        payload["unexpected"] = True
        self.assertTrue(
            self._errors(self._schema("h2-release-record.schema.json"), payload)
        )

    def test_release_record_schema_rejects_missing_field(self):
        payload = dict(_load(RELEASE_RECORD))
        payload.pop("release_identity")
        self.assertTrue(
            self._errors(self._schema("h2-release-record.schema.json"), payload)
        )

    def test_telemetry_schema_rejects_wrong_outcome(self):
        payload = copy.deepcopy(_load(EVIDENCE / "telemetry-health-report.json"))
        payload["outcome"] = "unknown"
        self.assertTrue(
            self._errors(
                self._schema("h2-telemetry-health-report.schema.json"), payload
            )
        )


if __name__ == "__main__":
    unittest.main()
