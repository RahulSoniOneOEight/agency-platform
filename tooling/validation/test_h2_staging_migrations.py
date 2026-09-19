from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tooling.hardening.candidate import canonical_identity
from tooling.hardening.staging_migrations import (
    build_success_evidence,
    migration_plan,
    verify_candidate_migration_files,
)


class StagingMigrationEvidenceTests(unittest.TestCase):
    def _fixture(self, root: Path) -> Path:
        client = root / "client-projects" / "reference-commerce"
        release = client / "production" / "release"
        release.mkdir(parents=True)
        migrations = root / "supabase" / "migrations"
        migrations.mkdir(parents=True)
        first = migrations / "202609180001_one.sql"
        second = migrations / "202609180002_two.sql"
        first.write_text("-- migration-class: additive\nselect 1;\n", encoding="utf-8")
        second.write_text("-- migration-class: additive\nselect 2;\n", encoding="utf-8")

        import hashlib
        def digest(path: Path) -> str:
            data = path.read_bytes().replace(b"\r\n", b"\n")
            return "sha256:" + hashlib.sha256(data).hexdigest()

        entries = [
            {"path": first.relative_to(root).as_posix(), "sha256": digest(first)},
            {"path": second.relative_to(root).as_posix(), "sha256": digest(second)},
        ]
        candidate = {
            "migration_set": [entry["path"] for entry in entries],
            "migration_set_entries": entries,
            "migration_set_identity": canonical_identity(entries),
        }
        (release / "candidate.json").write_text(
            json.dumps(candidate), encoding="utf-8"
        )
        return client

    def test_plan_uses_only_candidate_bound_migrations(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = self._fixture(root)
            self.assertEqual(
                [
                    "supabase/migrations/202609180001_one.sql",
                    "supabase/migrations/202609180002_two.sql",
                ],
                migration_plan(root, client),
            )

    def test_modified_migration_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = self._fixture(root)
            path = root / "supabase" / "migrations" / "202609180001_one.sql"
            path.write_text("-- migration-class: additive\nselect 999;\n", encoding="utf-8")
            errors = verify_candidate_migration_files(root, client)
            self.assertTrue(any("sha256 does not match candidate" in e for e in errors))

    def test_success_evidence_binds_candidate_and_post_apply_checks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = self._fixture(root)
            evidence = build_success_evidence(
                root,
                client,
                verification_checks=["required tables exist", "RLS enabled"],
            )
            self.assertTrue(evidence["staging_apply"]["ok"])
            self.assertTrue(evidence["post_apply_verification"]["ok"])
            self.assertEqual(
                ["required tables exist", "RLS enabled"],
                evidence["post_apply_verification"]["checks"],
            )
            self.assertEqual(
                canonical_identity(evidence["migration_set_entries"]),
                evidence["migration_set_identity"],
            )


if __name__ == "__main__":
    unittest.main()
