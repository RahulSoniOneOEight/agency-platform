"""Deterministic H.2 production smoke and telemetry-health tests (Task 9).

Flutter-free and network-free: the production smoke runner is driven through its
injectable runner seam and the telemetry evaluator consumes recorded samples, so
every safety and blocking condition can be exercised without deploying anything
or sleeping.
"""

from __future__ import annotations

import copy
import json
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tooling.release.smoke import (
    CHECK_IDS,
    MUTATION_CHECK_ID,
    HttpProductionSmokeRunner,
    build_fixture_production_deployment,
    load_candidate,
    production_smoke_report_identity,
    run_production_smoke,
    validate_production_smoke,
)
from tooling.release.telemetry_health import (
    DEFAULT_ERROR_RATE_THRESHOLD,
    REQUIRED_SAMPLE_COUNT,
    SAMPLE_SPACING_SECONDS,
    build_fixture_samples,
    evaluate_telemetry_health,
    telemetry_report_identity,
    validate_telemetry_health,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SMOKE_REPORT = CLIENT / "production" / "evidence" / "production-smoke-report.json"
TELEMETRY_REPORT = CLIENT / "production" / "evidence" / "telemetry-health-report.json"

RUNNER_CHECK_IDS = tuple(
    check_id for check_id in CHECK_IDS if check_id != MUTATION_CHECK_ID
)


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _candidate() -> dict:
    return dict(load_candidate(CLIENT))


def _deployment() -> dict:
    return build_fixture_production_deployment(_candidate())


def _check(report: dict, check_id: str) -> dict:
    return next(check for check in report["checks"] if check["id"] == check_id)


def _runner_failing(fail_id: str, mutations=None):
    def runner(check, context):
        if check["id"] == fail_id:
            return {
                "passed": False,
                "detail": f"{fail_id} failed",
                "mutations": list(mutations or []),
            }
        return {"passed": True, "detail": "ok", "mutations": []}

    return runner


def _runner_mutating(operation: str):
    def runner(check, context):
        return {"passed": True, "detail": "ok", "mutations": [operation]}

    return runner


class ProductionSmokeTests(unittest.TestCase):
    def test_fixture_smoke_passes_all_checks(self):
        report = run_production_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual("production", report["environment"])
        self.assertEqual(list(CHECK_IDS), [c["id"] for c in report["checks"]])
        self.assertTrue(all(c["status"] == "passed" for c in report["checks"]))
        self.assertIs(True, report["low_risk"])
        self.assertEqual([], report["uncontrolled_mutations"])
        self.assertEqual("production-deploy-0001", report["deployment_id"])
        self.assertEqual(_candidate()["candidate_identity"], report["candidate_identity"])
        self.assertEqual(
            report["report_identity"], production_smoke_report_identity(report)
        )

    def test_each_runner_check_failure_is_detected(self):
        for check_id in RUNNER_CHECK_IDS:
            with self.subTest(check=check_id):
                report = run_production_smoke(
                    ROOT, CLIENT, _deployment(), http=_runner_failing(check_id)
                )
                self.assertEqual("failed", _check(report, check_id)["status"])

    def test_release_identity_binding_mismatch_is_detected(self):
        deployment = _deployment()
        deployment["artifact_digest"] = "sha256:" + "0" * 64
        report = run_production_smoke(ROOT, CLIENT, deployment)
        self.assertEqual("failed", _check(report, "release-identity")["status"])

    def test_default_runner_performs_no_mutation(self):
        report = run_production_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual([], report["uncontrolled_mutations"])
        self.assertEqual("passed", _check(report, MUTATION_CHECK_ID)["status"])

    def test_uncontrolled_mutation_is_detected(self):
        report = run_production_smoke(
            ROOT,
            CLIENT,
            _deployment(),
            http=_runner_mutating("order.create"),
        )
        self.assertEqual(["order.create"], report["uncontrolled_mutations"])
        self.assertEqual("failed", _check(report, MUTATION_CHECK_ID)["status"])
        self.assertIs(False, report["low_risk"])

    def test_sandbox_safe_mutation_is_allowed(self):
        deployment = _deployment()
        deployment["sandbox_safe_mutations"] = ["order.create"]
        report = run_production_smoke(
            ROOT,
            CLIENT,
            deployment,
            http=_runner_mutating("order.create"),
        )
        self.assertEqual([], report["uncontrolled_mutations"])
        self.assertEqual("passed", _check(report, MUTATION_CHECK_ID)["status"])
        self.assertIs(True, report["low_risk"])

    def test_smoke_is_deterministic_and_offline(self):
        first = run_production_smoke(ROOT, CLIENT, _deployment())
        second = run_production_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual(first, second)

    def test_committed_smoke_report_matches_fixture_run(self):
        committed = _load(SMOKE_REPORT)
        expected = run_production_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual(committed, expected)

    def test_committed_smoke_report_validates(self):
        self.assertEqual([], validate_production_smoke(ROOT, CLIENT))


class LiveProductionSmokeTests(unittest.TestCase):
    def _runner(self, body: str, status: int = 200) -> HttpProductionSmokeRunner:
        class _Stub(HttpProductionSmokeRunner):
            def _fetch(self, url, headers=None):
                return (200 <= status < 300, str(status), body)

        return _Stub()

    def _report(self, body: str, status: int = 200) -> dict:
        return run_production_smoke(
            ROOT, CLIENT, _deployment(), http=self._runner(body, status)
        )

    def test_matching_version_marker_passes(self):
        report = self._report(json.dumps({"build_version": "0.1.0+h2rc1"}))
        self.assertEqual("passed", _check(report, "release-identity")["status"])

    def test_stale_version_marker_fails(self):
        report = self._report(json.dumps({"build_version": "0.0.0-stale"}))
        self.assertEqual("failed", _check(report, "release-identity")["status"])

    def test_permission_denied_check_requires_403(self):
        report = self._report("{}", status=200)
        self.assertEqual("failed", _check(report, "permission-denied")["status"])


class TelemetryHealthTests(unittest.TestCase):
    def _samples(self) -> list[dict]:
        return build_fixture_samples(_candidate())

    def _evaluate(self, samples, policy=None) -> dict:
        return evaluate_telemetry_health(
            ROOT, CLIENT, samples, _candidate(), policy=policy
        )

    def test_healthy_window_is_healthy(self):
        report = self._evaluate(self._samples())
        self.assertEqual("healthy", report["outcome"])
        self.assertEqual([], report["blocking_reasons"])
        self.assertEqual(REQUIRED_SAMPLE_COUNT, report["sample_count"])
        self.assertEqual(SAMPLE_SPACING_SECONDS, report["spacing_seconds"])
        self.assertEqual(len(self._samples()), len(report["samples"]))
        self.assertEqual(report["report_identity"], telemetry_report_identity(report))

    def test_exactly_five_samples_required(self):
        for count in (4, 6):
            with self.subTest(count=count):
                samples = self._samples()
                if count > len(samples):
                    samples = samples + [copy.deepcopy(samples[-1])]
                report = self._evaluate(samples[:count])
                self.assertEqual("failed", report["outcome"])
                self.assertTrue(
                    any("sample_count" in reason for reason in report["blocking_reasons"])
                )

    def test_wrong_spacing_is_detected(self):
        samples = self._samples()
        moved = datetime.fromisoformat(
            samples[3]["at"].replace("Z", "+00:00")
        ) + timedelta(seconds=SAMPLE_SPACING_SECONDS)
        samples[3]["at"] = moved.isoformat().replace("+00:00", "Z")
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_out_of_order_index_is_detected(self):
        samples = self._samples()
        samples[2]["index"] = 7
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_wrong_release_version_is_detected(self):
        samples = self._samples()
        samples[1]["release_version"] = "0.0.0-stale"
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_deployment_unreachable_is_detected(self):
        samples = self._samples()
        samples[0]["deployment_reachable"] = False
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_failed_health_signal_is_detected(self):
        samples = self._samples()
        samples[4]["sentry_health_signal"] = "failed"
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_degraded_health_signal_is_degraded(self):
        samples = self._samples()
        samples[2]["sentry_health_signal"] = "degraded"
        report = self._evaluate(samples)
        self.assertEqual("degraded", report["outcome"])
        self.assertEqual([], report["blocking_reasons"])

    def test_critical_unhandled_error_is_detected(self):
        samples = self._samples()
        samples[3]["critical_unhandled_errors"] = [{"message": "boom"}]
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_error_rate_threshold_breach_is_detected(self):
        samples = self._samples()
        samples[2]["error_rate"] = DEFAULT_ERROR_RATE_THRESHOLD * 2
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_policy_threshold_override_is_applied(self):
        samples = self._samples()
        samples[2]["error_rate"] = 0.05
        failed = self._evaluate(samples)
        self.assertEqual("failed", failed["outcome"])
        relaxed = self._evaluate(samples, policy={"error_rate_threshold": 0.1})
        self.assertEqual("healthy", relaxed["outcome"])

    def test_smoke_not_passed_is_detected(self):
        samples = self._samples()
        samples[0]["smoke_passed"] = False
        report = self._evaluate(samples)
        self.assertEqual("failed", report["outcome"])

    def test_evaluator_is_deterministic_and_offline(self):
        first = self._evaluate(self._samples())
        second = self._evaluate(self._samples())
        self.assertEqual(first, second)

    def test_committed_telemetry_report_matches_fixture_evaluation(self):
        committed = _load(TELEMETRY_REPORT)
        expected = self._evaluate(self._samples())
        self.assertEqual(committed, expected)

    def test_committed_telemetry_report_validates(self):
        self.assertEqual([], validate_telemetry_health(ROOT, CLIENT))


if __name__ == "__main__":
    unittest.main()
