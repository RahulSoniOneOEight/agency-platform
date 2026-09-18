"""Deterministic H.2 accessibility gate tests (Milestone H.2, Task 6)."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tooling.hardening.accessibility import (
    CRITICAL_JOURNEYS,
    REQUIRED_CHECKS,
    evaluate_accessibility,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"


def full_journeys() -> dict:
    return {
        journey: {check: True for check in (*REQUIRED_CHECKS, "labels", "contrast")}
        for journey in CRITICAL_JOURNEYS
    }


def blocking(findings: list[dict]) -> list[dict]:
    return [
        finding
        for finding in findings
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]


class AccessibilityGateTests(unittest.TestCase):
    def test_full_evidence_has_no_blocking(self):
        findings = evaluate_accessibility(
            ROOT, CLIENT, {"journeys": full_journeys()}
        )
        self.assertEqual([], blocking(findings), findings)

    def test_missing_keyboard_on_critical_journey_blocks(self):
        journeys = full_journeys()
        journeys["sign-in"]["keyboard"] = False
        findings = evaluate_accessibility(ROOT, CLIENT, {"journeys": journeys})
        self.assertIn(
            "accessibility-sign-in-keyboard",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_focus_on_critical_journey_blocks(self):
        journeys = full_journeys()
        del journeys["catalog"]["focus"]
        findings = evaluate_accessibility(ROOT, CLIENT, {"journeys": journeys})
        self.assertIn(
            "accessibility-catalog-focus",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_semantics_on_critical_journey_blocks(self):
        journeys = full_journeys()
        journeys["cart-order"]["semantics"] = False
        findings = evaluate_accessibility(ROOT, CLIENT, {"journeys": journeys})
        self.assertIn(
            "accessibility-cart-order-semantics",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_critical_journey_blocks(self):
        journeys = full_journeys()
        del journeys["rfq-quotation-order"]
        findings = evaluate_accessibility(ROOT, CLIENT, {"journeys": journeys})
        self.assertIn(
            "accessibility-rfq-quotation-order-missing",
            [f["id"] for f in blocking(findings)],
        )

    def test_non_critical_manual_issue_is_advisory(self):
        evidence = {
            "journeys": full_journeys(),
            "manual_review": [
                {
                    "id": "m1",
                    "journey": "marketing-footer",
                    "severity": "medium",
                    "summary": "footer focus ring is subtle",
                }
            ],
        }
        findings = evaluate_accessibility(ROOT, CLIENT, evidence)
        self.assertEqual([], blocking(findings))
        advisory_ids = [
            f["id"] for f in findings if f["disposition"] == "advisory"
        ]
        self.assertIn("accessibility-manual-m1", advisory_ids)

    def test_manual_issue_on_critical_journey_blocks(self):
        evidence = {
            "journeys": full_journeys(),
            "manual_review": [
                {
                    "id": "m2",
                    "journey": "sign-in",
                    "severity": "high",
                    "summary": "screen reader cannot reach submit",
                }
            ],
        }
        findings = evaluate_accessibility(ROOT, CLIENT, evidence)
        self.assertIn(
            "accessibility-manual-m2",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_evidence_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            findings = evaluate_accessibility(ROOT, Path(tmp), None)
        self.assertTrue(blocking(findings))
        self.assertEqual("accessibility-evidence-missing", findings[0]["id"])

    def test_findings_are_deterministic(self):
        journeys = full_journeys()
        journeys["sign-in"]["keyboard"] = False
        journeys["catalog"]["semantics"] = False
        evidence = {"journeys": journeys}
        first = evaluate_accessibility(ROOT, CLIENT, evidence)
        second = evaluate_accessibility(ROOT, CLIENT, evidence)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first, key=lambda f: (f["area"], f["id"])))


if __name__ == "__main__":
    unittest.main()
