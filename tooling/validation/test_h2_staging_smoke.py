"""Deterministic H.2 staging smoke tests (Milestone H.2, Task 7).

Flutter-free and network-free: the smoke runner is driven through its injectable
journey-runner seam so every critical staged journey (B2C, B2B, session refresh,
permission denial, backend failure mapping, and release identity) can be failed
and detected without touching staging.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from tooling.hardening.staging_smoke import (
    JOURNEY_NAMES,
    run_staging_smoke,
    smoke_report_identity,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
DEPLOYMENT_PATH = CLIENT / "production" / "release" / "staging-deployment.json"


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _deployment() -> dict:
    return _load(DEPLOYMENT_PATH)


def _failing_runner(fail_name: str, error_class: str = "staging_smoke_failed"):
    def runner(journey, context):
        if journey["name"] == fail_name:
            steps = [
                {"name": step, "passed": False} for step in journey["steps"]
            ]
            return {"passed": False, "steps": steps, "error_class": error_class}
        return {"passed": True, "error_class": None}

    return runner


class StagingSmokeTests(unittest.TestCase):
    def test_fixture_smoke_passes_all_critical_journeys(self):
        report = run_staging_smoke(ROOT, CLIENT, _deployment())
        self.assertTrue(report["critical_journeys_passed"])
        self.assertEqual("staging", report["environment"])
        self.assertEqual(
            list(JOURNEY_NAMES),
            [journey["name"] for journey in report["journeys"]],
        )
        self.assertTrue(all(journey["passed"] for journey in report["journeys"]))
        self.assertEqual(
            "sha256:be27d17be2be37bf05778fefb983b1116fa5e45e029a7e06b180e68fcfbc98da",
            report["candidate_identity"],
        )
        self.assertEqual("staging-deploy-0001", report["deployment_id"])

    def test_each_critical_journey_failure_is_detected(self):
        for name in JOURNEY_NAMES:
            with self.subTest(journey=name):
                report = run_staging_smoke(
                    ROOT, CLIENT, _deployment(), http=_failing_runner(name)
                )
                self.assertFalse(report["critical_journeys_passed"])
                journey = next(
                    entry
                    for entry in report["journeys"]
                    if entry["name"] == name
                )
                self.assertFalse(journey["passed"])
                self.assertEqual("staging_smoke_failed", journey["error_class"])
                self.assertTrue(all(not step["passed"] for step in journey["steps"]))

    def test_b2c_step_failure_is_detected(self):
        def runner(journey, context):
            if journey["name"] == "b2c-order":
                steps = [
                    {"name": step, "passed": step != "cart"}
                    for step in journey["steps"]
                ]
                return {
                    "passed": False,
                    "steps": steps,
                    "error_class": "staging_smoke_failed",
                }
            return {"passed": True, "error_class": None}

        report = run_staging_smoke(ROOT, CLIENT, _deployment(), http=runner)
        self.assertFalse(report["critical_journeys_passed"])
        b2c = next(j for j in report["journeys"] if j["name"] == "b2c-order")
        cart = next(step for step in b2c["steps"] if step["name"] == "cart")
        self.assertFalse(cart["passed"])
        self.assertFalse(b2c["passed"])

    def test_b2b_step_failure_is_detected(self):
        def runner(journey, context):
            if journey["name"] == "b2b-quote-order":
                steps = [
                    {"name": step, "passed": step != "quotation"}
                    for step in journey["steps"]
                ]
                return {
                    "passed": False,
                    "steps": steps,
                    "error_class": "staging_smoke_failed",
                }
            return {"passed": True, "error_class": None}

        report = run_staging_smoke(ROOT, CLIENT, _deployment(), http=runner)
        self.assertFalse(report["critical_journeys_passed"])
        b2b = next(
            j for j in report["journeys"] if j["name"] == "b2b-quote-order"
        )
        quotation = next(
            step for step in b2b["steps"] if step["name"] == "quotation"
        )
        self.assertFalse(quotation["passed"])

    def test_release_identity_detects_deployment_digest_mismatch(self):
        deployment = dict(_deployment())
        deployment["artifact_digest"] = "sha256:" + "0" * 64
        report = run_staging_smoke(ROOT, CLIENT, deployment)
        self.assertFalse(report["critical_journeys_passed"])
        release = next(
            j for j in report["journeys"] if j["name"] == "release-identity"
        )
        self.assertFalse(release["passed"])
        self.assertEqual("artifact_digest_mismatch", release["error_class"])

    def test_report_identity_self_verifies(self):
        report = run_staging_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual(
            report["report_identity"], smoke_report_identity(report)
        )

    def test_output_is_deterministic_and_sorted(self):
        first = run_staging_smoke(ROOT, CLIENT, _deployment())
        second = run_staging_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual(first, second)
        names = [journey["name"] for journey in first["journeys"]]
        self.assertEqual(sorted(names), names)
        self.assertEqual(len(names), len(set(names)))

    def test_committed_smoke_report_matches_fixture_run(self):
        committed = _load(CLIENT / "production" / "evidence" / "staging-smoke-report.json")
        expected = run_staging_smoke(ROOT, CLIENT, _deployment())
        self.assertEqual(committed, expected)


if __name__ == "__main__":
    unittest.main()
