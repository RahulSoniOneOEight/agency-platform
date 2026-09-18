"""Deterministic H.2 migration gate tests (Milestone H.2, Task 6)."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tooling.hardening.candidate import CANDIDATE_NAME, RELEASE_RELATIVE
from tooling.hardening.migrations import evaluate_migrations

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"


def candidate() -> dict:
    path = CLIENT / RELEASE_RELATIVE / CANDIDATE_NAME
    return json.loads(path.read_text(encoding="utf-8"))


def full_evidence() -> dict:
    payload = candidate()
    return {
        "migration_set_identity": payload["migration_set_identity"],
        "migration_set_entries": payload["migration_set_entries"],
        "migration_classes": {
            path: "additive" for path in payload["migration_set"]
        },
        "staging_apply": {"ok": True},
        "post_apply_verification": {"ok": True},
        "recovery_treatment": {},
    }


def blocking(findings: list[dict]) -> list[dict]:
    return [
        finding
        for finding in findings
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]


class MigrationGateTests(unittest.TestCase):
    def test_full_evidence_has_no_blocking(self):
        findings = evaluate_migrations(ROOT, CLIENT, full_evidence())
        self.assertEqual([], blocking(findings), findings)

    def test_identity_mismatch_blocks(self):
        evidence = full_evidence()
        evidence["migration_set_identity"] = "sha256:" + "0" * 64
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertIn(
            "migrations-identity-mismatch",
            [f["id"] for f in blocking(findings)],
        )

    def test_entries_mismatch_blocks(self):
        evidence = full_evidence()
        evidence["migration_set_entries"] = []
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertIn(
            "migrations-entries-mismatch",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_staging_apply_blocks(self):
        evidence = full_evidence()
        del evidence["staging_apply"]
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertIn(
            "migrations-staging-apply",
            [f["id"] for f in blocking(findings)],
        )

    def test_failed_staging_apply_blocks(self):
        evidence = full_evidence()
        evidence["staging_apply"] = {"ok": False}
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertIn(
            "migrations-staging-apply",
            [f["id"] for f in blocking(findings)],
        )

    def test_missing_post_apply_verification_blocks(self):
        evidence = full_evidence()
        del evidence["post_apply_verification"]
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertIn(
            "migrations-post-apply-verification",
            [f["id"] for f in blocking(findings)],
        )

    def test_destructive_migration_without_recovery_blocks(self):
        evidence = full_evidence()
        path = next(iter(evidence["migration_classes"]))
        evidence["migration_classes"][path] = "destructive"
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertTrue(
            any(
                finding["id"].startswith("migrations-recovery-")
                for finding in blocking(findings)
            ),
            findings,
        )

    def test_destructive_repo_class_cannot_be_erased_by_declared_classes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            migrations = root / "supabase" / "migrations"
            migrations.mkdir(parents=True)
            (migrations / "0001_destructive.sql").write_text(
                "-- migration-class: destructive\nSELECT 1;\n",
                encoding="utf-8",
            )
            evidence = full_evidence()
            evidence["migration_classes"] = {}
            findings = evaluate_migrations(root, CLIENT, evidence)
            self.assertTrue(
                any(
                    finding["id"].startswith("migrations-recovery-")
                    for finding in blocking(findings)
                ),
                findings,
            )

    def test_declared_additive_cannot_downgrade_repo_destructive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            migrations = root / "supabase" / "migrations"
            migrations.mkdir(parents=True)
            path = "supabase/migrations/0001_destructive.sql"
            (migrations / "0001_destructive.sql").write_text(
                "-- migration-class: destructive\nSELECT 1;\n",
                encoding="utf-8",
            )
            evidence = full_evidence()
            evidence["migration_classes"] = {path: "additive"}
            findings = evaluate_migrations(root, CLIENT, evidence)
            self.assertTrue(
                any(
                    finding["id"].startswith("migrations-recovery-")
                    for finding in blocking(findings)
                ),
                findings,
            )

    def test_destructive_migration_with_recovery_passes(self):
        evidence = full_evidence()
        path = next(iter(evidence["migration_classes"]))
        evidence["migration_classes"][path] = "transformative"
        evidence["recovery_treatment"] = {
            path: {"treatment": "forward-recovery-migration"}
        }
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertEqual([], blocking(findings), findings)

    def test_optimization_recommendations_are_advisory(self):
        evidence = full_evidence()
        evidence["optimization_recommendations"] = ["combine indexes"]
        findings = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertEqual([], blocking(findings))
        self.assertIn(
            "migrations-optimization-0",
            [f["id"] for f in findings if f["disposition"] == "advisory"],
        )

    def test_missing_evidence_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            findings = evaluate_migrations(ROOT, Path(tmp), None)
        self.assertTrue(blocking(findings))
        self.assertEqual("migrations-evidence-missing", findings[0]["id"])

    def test_findings_are_deterministic(self):
        evidence = full_evidence()
        evidence["migration_set_identity"] = "sha256:" + "1" * 64
        evidence["staging_apply"] = {"ok": False}
        first = evaluate_migrations(ROOT, CLIENT, evidence)
        second = evaluate_migrations(ROOT, CLIENT, evidence)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first, key=lambda f: (f["area"], f["id"])))


if __name__ == "__main__":
    unittest.main()
