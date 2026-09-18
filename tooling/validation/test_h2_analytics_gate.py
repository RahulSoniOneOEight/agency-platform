"""Deterministic H.2 analytics gate tests (Milestone H.2, Task 6)."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tooling.hardening.analytics import GOVERNED_EVENTS, evaluate_analytics

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"


def emitted(names: list[str]) -> list[dict]:
    return [{"name": name, "parameters": {"source": "test"}} for name in names]


def blocking(findings: list[dict]) -> list[dict]:
    return [
        finding
        for finding in findings
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]


class AnalyticsGateTests(unittest.TestCase):
    def test_all_required_events_present_has_no_blocking(self):
        findings = evaluate_analytics(ROOT, CLIENT, emitted(list(GOVERNED_EVENTS)))
        self.assertEqual([], blocking(findings), findings)

    def test_one_missing_required_event_blocks(self):
        names = [name for name in GOVERNED_EVENTS if name != "rfq_created"]
        findings = evaluate_analytics(ROOT, CLIENT, emitted(names))
        self.assertIn(
            "analytics-event-missing-rfq_created",
            [f["id"] for f in blocking(findings)],
        )

    def test_extra_event_is_advisory(self):
        names = list(GOVERNED_EVENTS) + ["experimental_promo"]
        findings = evaluate_analytics(ROOT, CLIENT, emitted(names))
        self.assertEqual([], blocking(findings))
        self.assertIn(
            "analytics-event-extra-experimental_promo",
            [f["id"] for f in findings if f["disposition"] == "advisory"],
        )

    def test_event_without_parameters_blocks(self):
        events = emitted(list(GOVERNED_EVENTS))
        events[0] = {"name": events[0]["name"]}
        findings = evaluate_analytics(ROOT, CLIENT, events)
        self.assertIn(
            "analytics-event-sign_in-parameters",
            [f["id"] for f in blocking(findings)],
        )

    def test_event_without_name_blocks(self):
        events = emitted(list(GOVERNED_EVENTS))
        events.append({"parameters": {}})
        findings = evaluate_analytics(ROOT, CLIENT, events)
        self.assertTrue(
            any(
                finding["id"].startswith("analytics-event-")
                and "invalid-name" in finding["id"]
                for finding in blocking(findings)
            )
        )

    def test_environment_is_attached(self):
        events = emitted([name for name in GOVERNED_EVENTS if name != "sign_in"])
        events.append(
            {
                "name": "experimental_promo",
                "parameters": {},
                "environment": "staging",
            }
        )
        findings = evaluate_analytics(ROOT, CLIENT, events)
        extra = next(
            finding
            for finding in findings
            if finding["id"] == "analytics-event-extra-experimental_promo"
        )
        self.assertIn("staging", extra["evidence_refs"])

    def test_missing_evidence_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            findings = evaluate_analytics(ROOT, Path(tmp), None)
        self.assertTrue(blocking(findings))
        self.assertEqual("analytics-evidence-missing", findings[0]["id"])

    def test_findings_are_deterministic(self):
        names = [name for name in GOVERNED_EVENTS if name not in ("sign_in", "order_created")]
        names.append("experimental")
        first = evaluate_analytics(ROOT, CLIENT, emitted(names))
        second = evaluate_analytics(ROOT, CLIENT, emitted(names))
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first, key=lambda f: (f["area"], f["id"])))


if __name__ == "__main__":
    unittest.main()
