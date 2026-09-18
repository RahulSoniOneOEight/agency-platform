"""Deterministic H.2 reference-commerce end-to-end release proof (Task 13).

This is the reference proof required by spec section 22 and acceptance criteria
13-16, 21, 34-36, 41, 42, and 46. It is Flutter-free, network-free, and
provider-free: every provider response is a committed deterministic fixture or an
injected synthetic runner, so the complete release control flow can be proved
without deploying anything and without any credential.

The proof covers:

1. **Happy path** -- candidate build -> staging deploy fixture -> all H.2A gates
   pass -> candidate freeze -> exact G authorization fixture -> exact-artifact
   production promotion (the *same* artifact digest as staged) -> production smoke
   -> telemetry health -> healthy ReleaseRecord. The production artifact digest is
   asserted identical to the staged/authorized digest (no rebuild).
2. **Negative scenarios**, each failing closed with the correct failure class:
   candidate mismatch, artifact digest mismatch (production artifact differs from
   the staged/authorized artifact), invalid/revoked authorization (via
   ``AuthorizationEvent``), migration failure, production smoke failure,
   telemetry failure, and a governed rollback/recovery path.
3. ``validate_release(ROOT, client_dir) == []`` on the committed reference proof.
4. No network calls; deterministic.

No live Cloudflare/Supabase staging or production deployment is ever triggered by
this module (the live proof is intentionally deferred pending explicit human
authorization).
"""

from __future__ import annotations

import copy
import dataclasses
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tooling.hardening.candidate import (
    ARTIFACT_FIXTURE_NAME,
    build_candidate,
    validate_candidate,
    verify_candidate_artifact,
)
from tooling.hardening.findings import AREAS, aggregate_gate
from tooling.hardening.migrations import evaluate_migrations
from tooling.hardening.report import (
    build_hardening_report,
    hardening_report_identity,
    load_hardening_report,
)
from tooling.hardening.validate import evaluate_fixture_gates, validate_hardening
from tooling.production_authorization.errors import (
    ProductionAuthorizationCandidateMismatch,
    ProductionAuthorizationInvalidated,
)
from tooling.production_authorization.models import ProductionAuthorization
from tooling.production_authorization.validity import AuthorizationEvent
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
    load_staging_deployment,
)
from tooling.release.recovery import (
    ACTION_APPLICATION_ROLLBACK,
    build_reference_recovery_report,
    plan_recovery,
    recovery_report_identity,
    validate_recovery,
)
from tooling.release.release_record import (
    build_release_record,
    load_release_record,
    load_staging_smoke_report,
    release_record_identity,
    validate_release_record,
)
from tooling.release.smoke import (
    CHECK_IDS,
    build_fixture_production_deployment,
    load_candidate,
    load_production_smoke_report,
    production_smoke_report_identity,
    run_production_smoke,
    validate_production_smoke,
)
from tooling.release.telemetry_health import (
    build_fixture_samples,
    evaluate_telemetry_health,
    load_telemetry_report,
    validate_telemetry_health,
)
from tooling.release.validate import (
    main as validate_main,
    validate_release,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SCHEMA_DIR = ROOT / "client-projects" / "schema"
EVIDENCE = CLIENT / "production" / "evidence"
RELEASE = CLIENT / "production" / "release"
HARDENING = CLIENT / "production" / "hardening"
FIXTURE_GATE_EVIDENCE = HARDENING / "fixture-gate-evidence.json"


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _candidate() -> dict:
    return dict(load_candidate(CLIENT))


def _check(report: dict, check_id: str) -> dict:
    return next(check for check in report["checks"] if check["id"] == check_id)


def _chain() -> dict:
    """Compose the deterministic healthy end-to-end release chain."""
    candidate = _candidate()
    staging = dict(load_staging_deployment(CLIENT))
    hardening = dict(load_hardening_report(CLIENT))
    f_report = load_f_report(ROOT, CLIENT)
    g_candidate = build_h2_g_candidate(candidate, hardening, f_report)
    authorization = ProductionAuthorization.from_dict(load_h2_authorization(CLIENT))
    deployment = build_fixture_production_deployment(candidate)
    production_smoke = run_production_smoke(ROOT, CLIENT, deployment)
    telemetry = evaluate_telemetry_health(
        ROOT, CLIENT, build_fixture_samples(candidate), candidate
    )
    staging_smoke = dict(load_staging_smoke_report(CLIENT))
    record = build_release_record(
        ROOT,
        CLIENT,
        candidate,
        dict(load_h2_authorization_ref(CLIENT)),
        hardening,
        staging_smoke,
        production_smoke,
        telemetry,
        deployment,
        "healthy",
    )
    return {
        "candidate": candidate,
        "staging": staging,
        "hardening": hardening,
        "f_report": f_report,
        "g_candidate": g_candidate,
        "authorization": authorization,
        "deployment": deployment,
        "production_smoke": production_smoke,
        "telemetry": telemetry,
        "staging_smoke": staging_smoke,
        "record": record,
    }


def _materialize_client(root: Path) -> Path:
    """Copy the committed reference client + shared inputs into a temp root."""
    client = root / "client-projects" / "reference-commerce"
    shutil.copytree(CLIENT, client)
    shutil.copytree(SCHEMA_DIR, root / "client-projects" / "schema")
    shutil.copytree(ROOT / "supabase", root / "supabase")
    return client


class HappyPathTests(unittest.TestCase):
    """Candidate -> staging -> gates -> freeze -> authorization -> release."""

    def test_candidate_rebuilds_from_the_committed_artifact_fixture(self):
        candidate = _candidate()
        rebuilt = build_candidate(
            ROOT,
            CLIENT,
            RELEASE / ARTIFACT_FIXTURE_NAME,
            candidate["source_sha"],
            candidate["build_version"],
        )
        self.assertEqual(candidate, rebuilt)
        self.assertEqual([], validate_candidate(ROOT, CLIENT))

    def test_staging_deployment_is_bound_to_the_exact_candidate(self):
        candidate = _candidate()
        staging = load_staging_deployment(CLIENT)
        self.assertEqual("staging", staging["environment"])
        self.assertEqual(candidate["artifact_digest"], staging["artifact_digest"])
        self.assertEqual(
            candidate["candidate_identity"], staging["candidate_identity"]
        )

    def test_all_h2a_gates_pass_and_the_candidate_is_eligible(self):
        gates = evaluate_fixture_gates(ROOT, CLIENT)
        self.assertEqual(set(AREAS), set(gates))
        for area, findings in gates.items():
            with self.subTest(area=area):
                self.assertEqual([], aggregate_gate(findings)["blocking_findings"])
        report = load_hardening_report(CLIENT)
        self.assertIs(True, report["eligible_for_authorization"])
        self.assertEqual([], report["blocking_findings"])

    def test_hardening_report_rebuilds_from_the_committed_fixture(self):
        expected = build_hardening_report(
            ROOT,
            CLIENT,
            _candidate(),
            evaluate_fixture_gates(ROOT, CLIENT),
            dict(load_staging_smoke_report(CLIENT)),
        )
        self.assertEqual(dict(load_hardening_report(CLIENT)), expected)
        self.assertEqual(
            expected["report_identity"], hardening_report_identity(expected)
        )
        self.assertEqual([], validate_hardening(ROOT, CLIENT))

    def test_exact_g_authorization_authorizes_the_frozen_candidate(self):
        chain = _chain()
        self.assertIsNone(
            verify_h2_authorized_candidate(
                chain["candidate"], chain["g_candidate"], chain["authorization"]
            )
        )
        self.assertEqual(
            chain["candidate"]["artifact_digest"],
            chain["authorization"].build_hash,
        )
        self.assertEqual(
            chain["candidate"]["source_sha"],
            chain["authorization"].source_commit_sha,
        )

    def test_production_promotes_the_exact_staged_artifact_without_rebuild(self):
        chain = _chain()
        candidate_digest = chain["candidate"]["artifact_digest"]
        staged = chain["staging"]["artifact_digest"]
        authorized = chain["authorization"].build_hash
        promoted = chain["deployment"]["artifact_digest"]
        self.assertEqual(candidate_digest, staged)
        self.assertEqual(staged, authorized)
        self.assertEqual(authorized, promoted)
        self.assertEqual(promoted, chain["production_smoke"]["artifact_digest"])
        self.assertEqual(promoted, chain["telemetry"]["artifact_digest"])
        self.assertEqual(promoted, chain["record"]["artifact_digest"])
        self.assertEqual(0, len({candidate_digest, staged, authorized, promoted}) - 1)

    def test_production_smoke_passes_all_checks(self):
        chain = _chain()
        report = chain["production_smoke"]
        self.assertEqual(list(CHECK_IDS), [check["id"] for check in report["checks"]])
        self.assertTrue(all(check["status"] == "passed" for check in report["checks"]))
        self.assertIs(True, report["low_risk"])
        self.assertEqual([], report["uncontrolled_mutations"])
        self.assertEqual([], validate_production_smoke(ROOT, CLIENT))

    def test_telemetry_health_window_is_healthy(self):
        chain = _chain()
        report = chain["telemetry"]
        self.assertEqual("healthy", report["outcome"])
        self.assertEqual([], report["blocking_reasons"])
        self.assertEqual([], validate_telemetry_health(ROOT, CLIENT))

    def test_healthy_release_record_binds_the_full_chain(self):
        chain = _chain()
        record = chain["record"]
        self.assertEqual("healthy", record["release_status"])
        self.assertEqual(chain["candidate"]["artifact_digest"], record["artifact_digest"])
        self.assertEqual(chain["candidate"]["source_sha"], record["source_sha"])
        self.assertEqual(
            chain["authorization"].authorization_id,
            record["production_authorization_id"],
        )
        self.assertEqual(
            chain["staging_smoke"]["report_identity"], record["staging_evidence"]
        )
        self.assertEqual(
            chain["production_smoke"]["report_identity"],
            record["production_smoke_evidence"],
        )
        self.assertEqual(
            chain["telemetry"]["report_identity"],
            record["telemetry_health_evidence"],
        )
        self.assertEqual(
            chain["deployment"]["deployment_id"], record["deployment_target"]
        )
        self.assertEqual(
            record["release_identity"], release_record_identity(record)
        )

    def test_committed_evidence_matches_the_deterministic_rebuild(self):
        chain = _chain()
        self.assertEqual(
            dict(load_production_smoke_report(CLIENT)), chain["production_smoke"]
        )
        self.assertEqual(dict(load_telemetry_report(CLIENT)), chain["telemetry"])
        self.assertEqual(dict(load_release_record(CLIENT)), chain["record"])
        self.assertEqual(
            dict(load_staging_smoke_report(CLIENT)), chain["staging_smoke"]
        )

    def test_reference_proof_is_deterministic(self):
        first = _chain()
        second = _chain()
        self.assertEqual(first, second)


class ReferenceValidatorTests(unittest.TestCase):
    def test_committed_reference_proof_validates_end_to_end(self):
        self.assertEqual([], validate_release(ROOT, CLIENT))

    def test_validator_is_deterministic(self):
        self.assertEqual(
            validate_release(ROOT, CLIENT), validate_release(ROOT, CLIENT)
        )

    def test_main_returns_zero_for_the_reference_proof(self):
        self.assertEqual(
            0, validate_main(["client-projects/reference-commerce"])
        )

    def test_release_record_validator_is_clean(self):
        self.assertEqual([], validate_release_record(ROOT, CLIENT))

    def test_recovery_validator_is_clean(self):
        self.assertEqual([], validate_recovery(ROOT, CLIENT))


class CandidateMismatchTests(unittest.TestCase):
    def test_candidate_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = _materialize_client(root)
            candidate_path = client / "production" / "release" / "candidate.json"
            candidate = _load(candidate_path)
            candidate["artifact_digest"] = "sha256:" + "0" * 64
            candidate_path.write_text(
                json.dumps(candidate), encoding="utf-8"
            )
            candidate_errors = validate_candidate(root, client)
            errors = validate_release(root, client)
        self.assertTrue(candidate_errors)
        self.assertTrue(
            any("fixture-derived candidate" in error for error in errors),
            errors,
        )
        self.assertTrue(any("candidate" in error for error in errors), errors)

    def test_tampered_candidate_manifest_binding_fails_closed(self):
        candidate = copy.deepcopy(_candidate())
        candidate["artifact_digest"] = "sha256:" + "0" * 64
        errors = verify_candidate_artifact(candidate, load_artifact_manifest(CLIENT))
        self.assertTrue(
            any("does not match candidate.artifact_digest" in error for error in errors),
            errors,
        )

    def test_h2_candidate_digest_mismatch_fails_closed(self):
        chain = _chain()
        bad = dict(chain["candidate"])
        bad["artifact_digest"] = "sha256:" + "1" * 64
        with self.assertRaises(H2AuthorizationBridgeError):
            verify_h2_authorized_candidate(
                bad, chain["g_candidate"], chain["authorization"]
            )


class ArtifactDigestMismatchTests(unittest.TestCase):
    def test_production_artifact_differing_from_staged_fails_closed(self):
        chain = _chain()
        deployment = dict(chain["deployment"])
        deployment["artifact_digest"] = "sha256:" + "2" * 64
        report = run_production_smoke(ROOT, CLIENT, deployment)
        self.assertEqual("failed", _check(report, "release-identity")["status"])

    def test_validator_rejects_a_promoted_digest_that_differs_from_staged(self):
        tampered = dict(load_production_smoke_report(CLIENT))
        tampered["artifact_digest"] = "sha256:" + "3" * 64
        tampered["report_identity"] = production_smoke_report_identity(tampered)
        with mock.patch(
            "tooling.release.validate.load_production_smoke_report",
            return_value=tampered,
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertTrue(
            any(
                "promoted artifact digest" in error and "no-rebuild violated" in error
                for error in errors
            ),
            errors,
        )

    def test_validator_rejects_a_staged_digest_that_differs_from_the_candidate(self):
        tampered = dict(load_staging_deployment(CLIENT))
        tampered["artifact_digest"] = "sha256:" + "4" * 64
        with mock.patch(
            "tooling.release.validate.load_staging_deployment",
            return_value=tampered,
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertTrue(
            any(
                "staged artifact digest" in error and "no-rebuild violated" in error
                for error in errors
            ),
            errors,
        )

    def test_validator_rejects_an_authorization_body_digest_mismatch(self):
        tampered = dict(load_h2_authorization(CLIENT))
        tampered["build"] = {**tampered["build"], "hash": "sha256:" + "5" * 64}
        with mock.patch(
            "tooling.release.validate.load_h2_authorization",
            return_value=tampered,
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertTrue(
            any(
                "authorized artifact digest" in error
                and "no-rebuild violated" in error
                for error in errors
            ),
            errors,
        )


class AuthorizationFailureTests(unittest.TestCase):
    def _event(self, authorization: ProductionAuthorization, event_type: str) -> AuthorizationEvent:
        return AuthorizationEvent(
            event_id=f"event-{event_type}",
            authorization_id=authorization.authorization_id,
            event_type=event_type,
            reason=f"reference proof {event_type}",
            actor=authorization.authorized_by,
            occurred_at=authorization.authorized_at,
        )

    def test_invalidated_authorization_fails_closed(self):
        chain = _chain()
        event = self._event(chain["authorization"], "invalidated")
        with self.assertRaises(ProductionAuthorizationInvalidated):
            verify_h2_authorized_candidate(
                chain["candidate"],
                chain["g_candidate"],
                chain["authorization"],
                (event,),
            )

    def test_revoked_authorization_fails_closed(self):
        chain = _chain()
        event = self._event(chain["authorization"], "revoked")
        with self.assertRaises(ProductionAuthorizationInvalidated):
            verify_h2_authorized_candidate(
                chain["candidate"],
                chain["g_candidate"],
                chain["authorization"],
                (event,),
            )

    def test_authorization_for_another_build_fails_closed(self):
        chain = _chain()
        other = dataclasses.replace(
            chain["authorization"], build_hash="sha256:" + "6" * 64
        )
        with self.assertRaises(ProductionAuthorizationCandidateMismatch):
            verify_h2_authorized_candidate(
                chain["candidate"], chain["g_candidate"], other
            )

    def test_committed_authorization_is_the_exact_candidate_fixture(self):
        chain = _chain()
        ref = load_h2_authorization_ref(CLIENT)
        self.assertEqual(
            chain["authorization"].authorization_id, ref["authorization_id"]
        )
        self.assertEqual(
            chain["authorization"].build_hash, chain["candidate"]["artifact_digest"]
        )
        self.assertEqual(
            chain["authorization"].source_commit_sha, chain["candidate"]["source_sha"]
        )


class MigrationFailureTests(unittest.TestCase):
    def _failing_report(self) -> dict:
        fixture = _load(FIXTURE_GATE_EVIDENCE)
        evidence = dict(fixture["migrations"])
        evidence["staging_apply"] = {"ok": False}
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        gate_findings = evaluate_fixture_gates(ROOT, CLIENT)
        gate_findings["migrations"] = findings
        return build_hardening_report(
            ROOT,
            CLIENT,
            _candidate(),
            gate_findings,
            dict(load_staging_smoke_report(CLIENT)),
        )

    def test_migration_apply_failure_is_a_blocking_finding(self):
        report = self._failing_report()
        blocking = [finding["id"] for finding in report["blocking_findings"]]
        self.assertIn("migrations-staging-apply", blocking)
        self.assertIs(False, report["eligible_for_authorization"])

    def test_validator_rejects_an_ineligible_hardening_report(self):
        report = self._failing_report()
        with mock.patch(
            "tooling.release.validate.load_hardening_report", return_value=report
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertTrue(
            any("not eligible for authorization" in error for error in errors),
            errors,
        )
        self.assertTrue(
            any("migrations-staging-apply" in error for error in errors), errors
        )

    def test_blocked_migration_prevents_authorization_eligibility(self):
        report = self._failing_report()
        self.assertFalse(report["eligible_for_authorization"])
        self.assertTrue(report["blocking_findings"])


class ProductionSmokeFailureTests(unittest.TestCase):
    def _failing_smoke(self, check_id: str) -> dict:
        def runner(check, context):
            if check["id"] == check_id:
                return {
                    "passed": False,
                    "detail": f"{check_id} failed",
                    "mutations": [],
                }
            return {"passed": True, "detail": "ok", "mutations": []}

        return run_production_smoke(
            ROOT,
            CLIENT,
            build_fixture_production_deployment(_candidate()),
            http=runner,
        )

    def test_production_smoke_check_failure_is_detected(self):
        report = self._failing_smoke("app-shell")
        self.assertEqual("failed", _check(report, "app-shell")["status"])

    def test_validator_rejects_a_failed_production_smoke(self):
        report = self._failing_smoke("app-shell")
        with mock.patch(
            "tooling.release.validate.load_production_smoke_report",
            return_value=report,
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertTrue(
            any(
                "production smoke check 'app-shell' did not pass" in error
                for error in errors
            ),
            errors,
        )


class TelemetryFailureTests(unittest.TestCase):
    def _failing_telemetry(self) -> dict:
        samples = build_fixture_samples(_candidate())
        samples[0]["deployment_reachable"] = False
        return evaluate_telemetry_health(ROOT, CLIENT, samples, _candidate())

    def test_unreachable_deployment_is_a_failed_health_window(self):
        report = self._failing_telemetry()
        self.assertEqual("failed", report["outcome"])
        self.assertTrue(report["blocking_reasons"])

    def test_validator_rejects_a_failed_telemetry_health_window(self):
        report = self._failing_telemetry()
        with mock.patch(
            "tooling.release.validate.load_telemetry_report",
            return_value=report,
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertTrue(
            any(
                "telemetry health outcome 'failed' is not healthy" in error
                for error in errors
            ),
            errors,
        )


class RecoveryPathTests(unittest.TestCase):
    def test_failed_release_produces_a_governed_recovery_report(self):
        report = build_reference_recovery_report(ROOT, CLIENT)
        self.assertEqual("failed", report["failed_release"]["release_status"])
        self.assertEqual("healthy", report["previous_known_good"]["release_status"])
        self.assertEqual(ACTION_APPLICATION_ROLLBACK, report["decision"]["action"])
        self.assertTrue(report["decision"]["permitted"])
        self.assertEqual("passed", report["verification_result"])
        self.assertEqual(
            report["previous_known_good"]["artifact_digest"],
            report["decision"]["target_artifact_digest"],
        )
        self.assertEqual(report["report_identity"], recovery_report_identity(report))

    def test_committed_recovery_report_validates(self):
        self.assertEqual([], validate_recovery(ROOT, CLIENT))

    def test_a_new_artifact_is_a_new_candidate_not_a_rollback(self):
        committed = load_release_record(CLIENT)
        new_digest = "sha256:" + "9" * 64
        failed = {
            "release_id": f"{committed['release_id']}-failed",
            "artifact_digest": new_digest,
            "release_status": "failed",
            "previous_known_good_release_id": committed["release_id"],
            "recovery": {
                "action": ACTION_APPLICATION_ROLLBACK,
                "target_artifact_digest": new_digest,
            },
        }
        decision = plan_recovery(
            failed,
            {
                "modes": ["application-rollback", "manual-halt"],
                "application_rollback": {"previous_known_good_only": True},
            },
            committed,
        )
        self.assertFalse(decision["permitted"])
        self.assertEqual("new_artifact_is_new_candidate", decision["reason"])

    def test_validator_composes_the_recovery_gate(self):
        with mock.patch(
            "tooling.release.validate.validate_recovery",
            return_value=["recovery-report.json: forged"],
        ):
            errors = validate_release(ROOT, CLIENT)
        self.assertIn("recovery-report.json: forged", errors)


class OfflineAndSafetyTests(unittest.TestCase):
    def test_validate_release_makes_no_network_calls(self):
        with mock.patch(
            "socket.socket",
            side_effect=AssertionError("network access attempted"),
        ):
            self.assertEqual([], validate_release(ROOT, CLIENT))

    def test_validator_source_is_provider_neutral_and_offline(self):
        source = (ROOT / "tooling" / "release" / "validate.py").read_text(
            encoding="utf-8"
        ).lower()
        for token in (
            "urllib",
            "requests",
            "http.client",
            "socket",
            "wrangler",
            "cloudflare",
            "supabase",
            "sentry",
            "ga4",
        ):
            self.assertNotIn(token, source)

    def test_committed_proof_carries_no_live_credentials(self):
        text = ""
        for path in sorted(RELEASE.rglob("*")) + sorted(EVIDENCE.rglob("*")):
            if path.is_file() and path.suffix in (".json", ".md", ".yaml", ".yml"):
                text += path.read_text(encoding="utf-8", errors="replace")
        for marker in ("-----BEGIN", "ghp_", "sk-", "AKIA", "Bearer ey"):
            self.assertNotIn(marker, text)

    def test_reference_urls_are_reserved_placeholders(self):
        staging = load_staging_deployment(CLIENT)
        self.assertIn(".example", staging["url"])


if __name__ == "__main__":
    unittest.main()
