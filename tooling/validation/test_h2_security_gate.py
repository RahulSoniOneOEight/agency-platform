"""Deterministic H.2 security gate tests (Milestone H.2, Task 6).

Flutter-free and network-free: the evaluator only consumes injected static
evidence, so these tests prove the blocking/advisory policy without a scanner.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tooling.hardening.findings import aggregate_gate, make_finding
from tooling.hardening.security import evaluate_security

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"


def scanner_finding(
    identifier: str,
    severity: str,
    *,
    status: str = "open",
    release_relevant: bool = True,
) -> dict:
    return {
        "id": identifier,
        "severity": severity,
        "status": status,
        "release_relevant": release_relevant,
        "summary": f"scanner {identifier}",
    }


def blocking(findings: list[dict]) -> list[dict]:
    return [
        finding
        for finding in findings
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]


class SecurityGateTests(unittest.TestCase):
    def test_critical_open_is_blocking(self):
        findings = evaluate_security(
            ROOT, CLIENT, {"findings": [scanner_finding("CVE-1", "critical")]}
        )
        self.assertTrue(blocking(findings))
        self.assertEqual("critical", findings[0]["severity"])

    def test_high_open_is_blocking(self):
        findings = evaluate_security(
            ROOT, CLIENT, {"findings": [scanner_finding("CVE-2", "high")]}
        )
        self.assertTrue(blocking(findings))

    def test_medium_open_is_advisory(self):
        findings = evaluate_security(
            ROOT, CLIENT, {"findings": [scanner_finding("CVE-3", "medium")]}
        )
        self.assertFalse(blocking(findings))
        self.assertEqual("advisory", findings[0]["disposition"])

    def test_low_and_info_are_advisory(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [scanner_finding("L", "low"), scanner_finding("I", "info")]},
        )
        self.assertFalse(blocking(findings))
        self.assertEqual(2, len(findings))

    def test_closed_high_does_not_block(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [scanner_finding("CVE-4", "high", status="closed")]},
        )
        self.assertFalse(blocking(findings))
        self.assertEqual("closed", findings[0]["status"])

    def test_waived_high_does_not_block(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [scanner_finding("CVE-5", "critical", status="waived")]},
        )
        self.assertFalse(blocking(findings))

    def test_non_release_relevant_high_is_advisory(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [scanner_finding("CVE-6", "high", release_relevant=False)]},
        )
        self.assertFalse(blocking(findings))

    def test_omitted_release_relevant_critical_blocks(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [{"id": "CVE-OMIT-C", "severity": "critical"}]},
        )
        self.assertTrue(blocking(findings))
        ids = [finding["id"] for finding in findings]
        self.assertIn("security-scanner-CVE-OMIT-C", ids)
        self.assertTrue(
            any(
                identifier.startswith("security-classification-missing")
                for identifier in ids
            ),
            ids,
        )

    def test_omitted_release_relevant_high_blocks(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [{"id": "CVE-OMIT-H", "severity": "high"}]},
        )
        self.assertTrue(blocking(findings))
        self.assertTrue(
            any(
                finding["id"].startswith("security-classification-missing")
                for finding in blocking(findings)
            ),
            findings,
        )

    def test_null_release_relevant_critical_blocks(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {
                "findings": [
                    {"id": "CVE-NULL-C", "severity": "critical", "release_relevant": None}
                ]
            },
        )
        self.assertTrue(blocking(findings))
        self.assertTrue(
            any(
                finding["id"].startswith("security-classification-missing")
                for finding in blocking(findings)
            ),
            findings,
        )

    def test_omitted_release_relevant_medium_is_advisory(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [{"id": "CVE-OMIT-M", "severity": "medium"}]},
        )
        self.assertFalse(blocking(findings))
        self.assertFalse(
            any(
                finding["id"].startswith("security-classification-missing")
                for finding in findings
            ),
            findings,
        )

    def test_malformed_findings_container_blocks(self):
        findings = evaluate_security(
            ROOT, CLIENT, {"findings": {"id": "CVE-1", "severity": "high"}}
        )
        self.assertTrue(blocking(findings))
        self.assertEqual("security-evidence-invalid", findings[0]["id"])

    def test_string_findings_container_blocks(self):
        findings = evaluate_security(ROOT, CLIENT, {"findings": "not-a-list"})
        self.assertTrue(blocking(findings))
        self.assertEqual("security-evidence-invalid", findings[0]["id"])

    def test_null_findings_container_blocks(self):
        findings = evaluate_security(ROOT, CLIENT, {"findings": None})
        self.assertTrue(blocking(findings))
        self.assertEqual("security-evidence-invalid", findings[0]["id"])

    def test_absent_findings_keeps_existing_behavior(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"secret_leak": False, "rls_validation": {"ok": True}},
        )
        self.assertEqual([], findings)

    def test_severity_with_whitespace_classifies_as_critical(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [scanner_finding("CVE-WS", " critical ")]},
        )
        self.assertTrue(blocking(findings))
        self.assertEqual("critical", findings[0]["severity"])

    def test_secret_leak_blocks(self):
        findings = evaluate_security(ROOT, CLIENT, {"secret_leak": True})
        self.assertTrue(blocking(findings))
        self.assertIn("security-secret-leak", [f["id"] for f in findings])

    def test_rls_validation_failure_blocks(self):
        findings = evaluate_security(
            ROOT, CLIENT, {"rls_validation": {"ok": False}}
        )
        self.assertTrue(blocking(findings))
        self.assertIn("security-rls-validation", [f["id"] for f in findings])

    def test_production_debug_blocks(self):
        findings = evaluate_security(
            ROOT, CLIENT, {"production_debug_enabled": True}
        )
        self.assertTrue(blocking(findings))
        self.assertIn("security-production-debug", [f["id"] for f in findings])

    def test_clean_evidence_has_no_blocking(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {
                "findings": [scanner_finding("CVE-7", "medium")],
                "secret_leak": False,
                "rls_validation": {"ok": True},
                "production_debug_enabled": False,
            },
        )
        self.assertFalse(blocking(findings))

    def test_missing_evidence_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            findings = evaluate_security(ROOT, Path(tmp), None)
        self.assertTrue(blocking(findings))
        self.assertEqual("security-evidence-missing", findings[0]["id"])

    def test_provider_native_severity_is_preserved(self):
        findings = evaluate_security(
            ROOT,
            CLIENT,
            {"findings": [scanner_finding("CVE-8", "low")]},
        )
        self.assertEqual("low", findings[0]["severity"])

    def test_findings_are_deterministic(self):
        evidence = {
            "findings": [
                scanner_finding("Z", "high"),
                scanner_finding("A", "medium"),
            ]
        }
        first = evaluate_security(ROOT, CLIENT, evidence)
        second = evaluate_security(ROOT, CLIENT, evidence)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first, key=lambda f: (f["area"], f["id"])))

    def test_aggregate_gate_blocks_only_open_blocking(self):
        open_blocking = make_finding(
            "a", "security", "high", "blocking", "open", "open blocker"
        )
        closed_blocking = make_finding(
            "b", "security", "high", "blocking", "closed", "closed blocker"
        )
        advisory = make_finding(
            "c", "security", "medium", "advisory", "open", "advisory"
        )

        gate = aggregate_gate([open_blocking, closed_blocking, advisory])
        self.assertFalse(gate["eligible"])
        self.assertEqual(["a"], [f["id"] for f in gate["blocking_findings"]])
        self.assertEqual(["c"], [f["id"] for f in gate["advisory_findings"]])
        self.assertEqual(3, len(gate["findings"]))

        gate_without_open = aggregate_gate([closed_blocking, advisory])
        self.assertTrue(gate_without_open["eligible"])

    def test_aggregate_gate_waived_blocking_does_not_block(self):
        waived_blocking = make_finding(
            "w", "security", "critical", "blocking", "waived", "waived blocker"
        )
        gate = aggregate_gate([waived_blocking])
        self.assertTrue(gate["eligible"])
        self.assertEqual([], gate["blocking_findings"])
        self.assertEqual(1, len(gate["findings"]))


if __name__ == "__main__":
    unittest.main()
