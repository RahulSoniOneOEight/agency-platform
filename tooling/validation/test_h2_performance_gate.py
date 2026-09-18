"""Deterministic H.2 performance gate tests (Milestone H.2, Task 6).

Boundary behaviour is exact: a value equal to its budget passes, a value
strictly greater is blocking, and ``baseline_regression_percent`` fails above
20.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.hardening.performance import (
    BUDGET_RELATIVE,
    MEASUREMENT_BUDGETS,
    evaluate_performance,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"


def budgets() -> dict:
    path = CLIENT / BUDGET_RELATIVE
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def at_threshold() -> dict:
    policy = budgets()
    return {
        measurement: policy[budget_key]
        for measurement, budget_key in MEASUREMENT_BUDGETS.items()
    }


def blocking(findings: list[dict]) -> list[dict]:
    return [
        finding
        for finding in findings
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]


class PerformanceGateTests(unittest.TestCase):
    def test_values_at_threshold_pass(self):
        findings = evaluate_performance(ROOT, CLIENT, at_threshold())
        self.assertEqual([], blocking(findings), findings)

    def test_threshold_plus_one_fails_blocking(self):
        measurements = at_threshold()
        key = "critical_api_p95_ms"
        measurements[key] = measurements[key] + 1
        findings = evaluate_performance(ROOT, CLIENT, measurements)
        blocking_ids = [f["id"] for f in blocking(findings)]
        self.assertIn("performance-critical_api_p95_ms-over-budget", blocking_ids)

    def test_each_budget_boundary_blocks_at_plus_one(self):
        for measurement, budget_key in MEASUREMENT_BUDGETS.items():
            measurements = at_threshold()
            measurements[measurement] = measurements[measurement] + 1
            findings = evaluate_performance(ROOT, CLIENT, measurements)
            self.assertIn(
                f"performance-{measurement}-over-budget",
                [f["id"] for f in blocking(findings)],
                measurement,
            )

    def test_baseline_regression_at_20_passes(self):
        measurements = at_threshold()
        measurements["baseline_regression_percent"] = 20
        findings = evaluate_performance(ROOT, CLIENT, measurements)
        self.assertNotIn(
            "performance-baseline_regression_percent-over-budget",
            [f["id"] for f in findings],
        )

    def test_baseline_regression_at_21_fails(self):
        measurements = at_threshold()
        measurements["baseline_regression_percent"] = 21
        findings = evaluate_performance(ROOT, CLIENT, measurements)
        self.assertIn(
            "performance-baseline_regression_percent-over-budget",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_measurement_blocks(self):
        measurements = at_threshold()
        del measurements["main_js_raw_bytes"]
        findings = evaluate_performance(ROOT, CLIENT, measurements)
        self.assertIn(
            "performance-measurement-missing-main_js_raw_bytes",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_evidence_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            findings = evaluate_performance(ROOT, Path(tmp), None)
        self.assertTrue(blocking(findings))
        self.assertEqual("performance-evidence-missing", findings[0]["id"])

    def test_findings_are_deterministic(self):
        measurements = at_threshold()
        measurements["main_js_raw_bytes"] = measurements["main_js_raw_bytes"] + 1
        first = evaluate_performance(ROOT, CLIENT, measurements)
        second = evaluate_performance(ROOT, CLIENT, measurements)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first, key=lambda f: (f["area"], f["id"])))


if __name__ == "__main__":
    unittest.main()
