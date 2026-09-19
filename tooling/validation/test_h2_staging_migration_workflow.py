from __future__ import annotations

import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / ".github" / "workflows" / "staging-deploy.yml"
HARDENING = ROOT / ".github" / "workflows" / "h2-hardening.yml"


class StagingMigrationWorkflowTests(unittest.TestCase):
    def test_staging_requires_database_secret_and_applies_candidate_bound_migrations(self):
        text = STAGING.read_text(encoding="utf-8")
        self.assertIn("SUPABASE_DB_URL: ${{ secrets.SUPABASE_DB_URL }}", text)
        self.assertIn("tooling.hardening.staging_migrations", text)
        self.assertIn("--print-plan", text)
        self.assertIn('psql "$SUPABASE_DB_URL"', text)
        self.assertIn("--write-success-evidence", text)
        self.assertIn("migration-evidence.json", text)

    def test_migrations_happen_before_cloudflare_deploy(self):
        text = STAGING.read_text(encoding="utf-8")
        self.assertLess(
            text.index("Apply candidate-bound staging migrations"),
            text.index("Deploy the exact artifact to staging"),
        )
        self.assertLess(
            text.index("Post-apply staging schema verification"),
            text.index("Deploy the exact artifact to staging"),
        )

    def test_live_hardening_downloads_real_staging_evidence(self):
        text = HARDENING.read_text(encoding="utf-8")
        self.assertIn("staging_run_id", text)
        self.assertIn("actions/download-artifact@v4", text)
        self.assertIn("h2-staging-deployment-${{ inputs.candidate_sha", text)
        self.assertIn("STAGING_DEPLOYMENT_FILE", text)
        self.assertIn("migration-evidence.json", text)

    def test_no_production_environment_is_introduced(self):
        staging = yaml.safe_load(STAGING.read_text(encoding="utf-8"))
        hardening = yaml.safe_load(HARDENING.read_text(encoding="utf-8"))
        self.assertEqual("staging", staging["jobs"]["staging-deploy"]["environment"])
        self.assertEqual("staging", hardening["jobs"]["live-hardening"]["environment"])


if __name__ == "__main__":
    unittest.main()
