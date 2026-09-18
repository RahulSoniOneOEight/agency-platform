"""Deterministic H.2 observability gate tests (Milestone H.2, Task 6)."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tooling.hardening.observability import evaluate_observability

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"


def full_evidence() -> dict:
    return {
        "adapter_initialized": True,
        "tags": {
            "release": "0.1.0+h2rc1",
            "environment": "staging",
            "client": "reference-commerce",
            "candidate": "sha256:" + "a" * 64,
        },
        "exception_capture": {"handled": True, "unhandled": True},
        "redaction": {"proven": True},
    }


def blocking(findings: list[dict]) -> list[dict]:
    return [
        finding
        for finding in findings
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]


class ObservabilityGateTests(unittest.TestCase):
    def test_full_evidence_has_no_blocking(self):
        findings = evaluate_observability(ROOT, CLIENT, full_evidence())
        self.assertEqual([], blocking(findings), findings)

    def test_adapter_not_initialized_blocks(self):
        evidence = full_evidence()
        evidence["adapter_initialized"] = False
        findings = evaluate_observability(ROOT, CLIENT, evidence)
        self.assertIn(
            "observability-adapter-not-initialized",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_tag_blocks(self):
        for tag in ("release", "environment", "client", "candidate"):
            evidence = full_evidence()
            del evidence["tags"][tag]
            findings = evaluate_observability(ROOT, CLIENT, evidence)
            self.assertIn(
                f"observability-tag-{tag}",
                [f["id"] for f in blocking(findings)],
                tag,
            )

    def test_missing_handled_capture_blocks(self):
        evidence = full_evidence()
        evidence["exception_capture"]["handled"] = False
        findings = evaluate_observability(ROOT, CLIENT, evidence)
        self.assertIn(
            "observability-capture-handled",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_unhandled_capture_blocks(self):
        evidence = full_evidence()
        del evidence["exception_capture"]["unhandled"]
        findings = evaluate_observability(ROOT, CLIENT, evidence)
        self.assertIn(
            "observability-capture-unhandled",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_redaction_blocks(self):
        evidence = full_evidence()
        evidence["redaction"] = {"proven": False}
        findings = evaluate_observability(ROOT, CLIENT, evidence)
        self.assertIn(
            "observability-redaction",
            [f["id"] for f in blocking(findings)],
        )

    def test_alert_tuning_is_advisory(self):
        evidence = full_evidence()
        evidence["alert_tuning"] = ["tighten p95 alert threshold"]
        findings = evaluate_observability(ROOT, CLIENT, evidence)
        self.assertEqual([], blocking(findings))
        self.assertIn(
            "observability-alert_tuning-0",
            [f["id"] for f in findings if f["disposition"] == "advisory"],
        )

    def test_missing_evidence_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            findings = evaluate_observability(ROOT, Path(tmp), None)
        self.assertTrue(blocking(findings))
        self.assertEqual("observability-evidence-missing", findings[0]["id"])

    def test_findings_are_deterministic(self):
        evidence = full_evidence()
        evidence["tags"]["candidate"] = ""
        evidence["redaction"] = False
        first = evaluate_observability(ROOT, CLIENT, evidence)
        second = evaluate_observability(ROOT, CLIENT, evidence)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first, key=lambda f: (f["area"], f["id"])))


if __name__ == "__main__":
    unittest.main()
