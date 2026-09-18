"""Static no-rebuild / authority-boundary tests for the H.2 production workflow.

Milestone H.2, Task 11. These tests are deterministic, Flutter-free, and
network-free: they parse the committed workflow YAML/text and assert the release
pipeline's structural invariants without executing a single live step.

They prove:

- the production workflow contains no build/rebuild command of any kind;
- it contains no command that could create or mutate a ``ProductionAuthorization``;
- the G release-gate verification and the artifact-digest verification both occur
  before the deploy step;
- production smoke and the telemetry health window both occur after the deploy;
- the governed recovery step runs only on a failed outcome;
- live secrets are referenced only through GitHub secret contexts, never as
  literal values, and the ``production`` environment is declared;
- ``validate.yml`` runs every new H.2 test module and validator;
- ``validate.yml`` and ``flutter-ci.yml`` stay credential-free and never invoke a
  live deployment.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path
from typing import Any, Callable

import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
PRODUCTION_WORKFLOW = WORKFLOWS / "production-release.yml"
VALIDATE_WORKFLOW = WORKFLOWS / "validate.yml"
FLUTTER_WORKFLOW = WORKFLOWS / "flutter-ci.yml"

PRODUCTION_JOB = "production-release"

# The new H.2 unittest modules that credential-free PR CI must run.
H2_TEST_MODULES: tuple[str, ...] = (
    "test_h2_hardening_policies",
    "test_h2_candidate",
    "test_h2_security_gate",
    "test_h2_performance_gate",
    "test_h2_accessibility_gate",
    "test_h2_analytics_gate",
    "test_h2_observability_gate",
    "test_h2_migration_gate",
    "test_h2_staging_smoke",
    "test_h2_hardening_report",
    "test_h2_authorization_bridge",
    "test_h2_production_release",
    "test_h2_release_record",
    "test_h2_recovery",
    "test_h2_release_workflow",
)

# H.2 validators that exist today and must run in PR CI.
H2_VALIDATOR_COMMANDS: tuple[str, ...] = (
    "python -m tooling.hardening.policies",
    "python -m tooling.hardening.candidate",
    "python -m tooling.hardening.validate",
    "python -m tooling.release.release_record",
    "python -m tooling.release.recovery",
)

SECRET_CONTEXT = re.compile(r"\$\{\{\s*secrets\.[A-Za-z0-9_]+\s*\}\}")

# Substrings that identify the ordered production steps by step name.
DOWNLOAD = "download the exact candidate artifact"
VERIFY_CANDIDATE = "verify h.2 release candidate"
VERIFY_AUTHORIZATION = "verify g production authorization"
VERIFY_DIGEST = "verify artifact digest"
VERIFY_MIGRATIONS = "verify migration-set identity"
APPLY_MIGRATIONS = "apply the authorized migration set"
DEPLOY = "deploy the exact artifact"
PRODUCTION_SMOKE = "run production smoke"
TELEMETRY = "5-sample telemetry health window"
FINALIZE = "finalize releaserecord"
RECOVERY = "governed recovery path"


def _load_yaml(path: Path) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _steps() -> list[dict[str, Any]]:
    document = _load_yaml(PRODUCTION_WORKFLOW)
    return document["jobs"][PRODUCTION_JOB]["steps"]


def _find_step(
    steps: list[dict[str, Any]],
    token: str,
    *,
    where: Callable[[dict[str, Any]], bool] | None = None,
) -> tuple[int, dict[str, Any]]:
    for index, step in enumerate(steps):
        name = str(step.get("name", "")).lower()
        if token in name and (where is None or where(step)):
            return index, step
    raise AssertionError(f"no step matching {token!r}")


def _index(token: str) -> int:
    index, _ = _find_step(_steps(), token)
    return index


class ProductionWorkflowNoRebuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = PRODUCTION_WORKFLOW.read_text(encoding="utf-8")
        self.lowered = self.text.lower()
        self.steps = _steps()

    def test_no_build_or_rebuild_command_anywhere(self):
        for forbidden in (
            "flutter",
            "flutter build",
            "flutter build web",
            "build web",
            "dart build",
            "npm run build",
            "subosito/flutter-action",
        ):
            self.assertNotIn(forbidden, self.lowered)

    def test_downloads_exact_artifact_instead_of_building(self):
        index, step = _find_step(self.steps, DOWNLOAD)
        self.assertIn("actions/download-artifact@v4", step["uses"])
        self.assertLess(index, _index(DEPLOY))

    def test_no_authorization_creation_command(self):
        for forbidden in (
            "tooling.production_authorization.coordinator",
            "production_authorization.repository",
            "filereleaseauthorization",
            "create_authorization",
            ".authorize(",
            "repository.create",
            "--authorize",
        ):
            self.assertNotIn(forbidden, self.lowered)
        for line in self.text.splitlines():
            if "production_authorization" in line:
                self.assertNotIn("--write", line)
                self.assertNotIn("--create", line)

    def test_invokes_existing_g_release_gate(self):
        self.assertIn(
            "python -m tooling.production_authorization.validate", self.text
        )

    def test_uses_cloudflare_pages_reference_deploy(self):
        _, step = _find_step(self.steps, DEPLOY)
        self.assertIn("wrangler", step["run"].lower())
        self.assertIn("pages deploy", step["run"].lower())


class ProductionWorkflowOrderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.steps = _steps()

    def test_release_gate_verification_precedes_deploy(self):
        self.assertLess(_index(VERIFY_AUTHORIZATION), _index(DEPLOY))

    def test_artifact_digest_verification_precedes_deploy(self):
        self.assertLess(_index(VERIFY_DIGEST), _index(DEPLOY))

    def test_candidate_and_migration_verification_precede_deploy(self):
        deploy = _index(DEPLOY)
        self.assertLess(_index(VERIFY_CANDIDATE), deploy)
        self.assertLess(_index(VERIFY_MIGRATIONS), deploy)

    def test_authorized_migrations_apply_before_deploy(self):
        self.assertLess(_index(APPLY_MIGRATIONS), _index(DEPLOY))

    def test_production_smoke_runs_after_deploy(self):
        self.assertGreater(_index(PRODUCTION_SMOKE), _index(DEPLOY))

    def test_telemetry_health_runs_after_deploy(self):
        self.assertGreater(_index(TELEMETRY), _index(DEPLOY))

    def test_release_record_finalized_after_health(self):
        self.assertGreater(_index(FINALIZE), _index(TELEMETRY))
        self.assertGreater(_index(FINALIZE), _index(DEPLOY))

    def test_full_required_step_order(self):
        ordered = [
            _index(DOWNLOAD),
            _index(VERIFY_CANDIDATE),
            _index(VERIFY_AUTHORIZATION),
            _index(VERIFY_DIGEST),
            _index(VERIFY_MIGRATIONS),
            _index(APPLY_MIGRATIONS),
            _index(DEPLOY),
            _index(PRODUCTION_SMOKE),
            _index(TELEMETRY),
            _index(FINALIZE),
            _index(RECOVERY),
        ]
        self.assertEqual(ordered, sorted(ordered))
        self.assertEqual(len(set(ordered)), len(ordered))


class ProductionWorkflowRecoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.steps = _steps()

    def test_recovery_is_conditional_on_failed_outcome(self):
        _, step = _find_step(self.steps, RECOVERY)
        self.assertIn("if", step)
        self.assertIn(
            "steps.finalize.outputs.outcome == 'failed'", step["if"]
        )

    def test_recovery_never_runs_unconditionally(self):
        for step in self.steps:
            name = str(step.get("name", "")).lower()
            if RECOVERY in name:
                self.assertIn("if", step)

    def test_recovery_runs_after_finalize(self):
        self.assertGreater(_index(RECOVERY), _index(FINALIZE))

    def test_recovery_uses_governed_recovery_module(self):
        _, step = _find_step(self.steps, RECOVERY)
        self.assertIn("tooling.release.recovery", step["run"])


class ProductionWorkflowSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = PRODUCTION_WORKFLOW.read_text(encoding="utf-8")
        self.lowered = self.text.lower()
        self.document = _load_yaml(PRODUCTION_WORKFLOW)

    def test_declares_production_environment(self):
        self.assertIn("environment: production", self.text)

    def test_is_dispatch_only_so_pr_ci_never_runs_live_steps(self):
        self.assertIn("workflow_dispatch", self.text)
        self.assertNotIn("pull_request", self.lowered)

    def test_secrets_referenced_only_through_secret_context(self):
        stripped = SECRET_CONTEXT.sub("", self.text)
        self.assertNotIn("secrets.", stripped)

    def test_references_expected_live_secrets_through_context(self):
        for name in (
            "CLOUDFLARE_API_TOKEN",
            "CLOUDFLARE_ACCOUNT_ID",
            "CLOUDFLARE_PAGES_PROJECT",
            "PRODUCTION_DEPLOYMENT_URL",
            "SUPABASE_DB_URL",
            "TELEMETRY_HEALTH_URL",
            "TELEMETRY_HEALTH_TOKEN",
        ):
            self.assertIn(f"secrets.{name}", self.text)

    def test_contains_no_literal_secret_values(self):
        for marker in (
            "-----BEGIN",
            "ghp_",
            "sk-",
            "Bearer ey",
            "AKIA",
        ):
            self.assertNotIn(marker, self.text)

    def test_environment_is_a_safeguard_not_an_authority_substitute(self):
        # The workflow must explicitly document that environment protection does
        # not replace the G authorization and must still invoke the release gate.
        self.assertIn("not a replacement", self.lowered)
        self.assertIn(
            "tooling.production_authorization.validate", self.text
        )


class CredentialFreeCiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validate_text = VALIDATE_WORKFLOW.read_text(encoding="utf-8")
        self.validate_lowered = self.validate_text.lower()
        self.flutter_text = FLUTTER_WORKFLOW.read_text(encoding="utf-8")
        self.flutter_lowered = self.flutter_text.lower()

    def test_validate_runs_new_h2_test_modules(self):
        for module in H2_TEST_MODULES:
            self.assertIn(module, self.validate_text)

    def test_validate_runs_new_h2_validators(self):
        for command in H2_VALIDATOR_COMMANDS:
            self.assertIn(command, self.validate_text)

    def test_validate_and_flutter_ci_have_no_secret_usage(self):
        for text in (self.validate_text, self.flutter_text):
            self.assertNotIn("secrets.", text)

    def test_validate_and_flutter_ci_never_deploy(self):
        for text in (self.validate_text, self.flutter_text):
            lowered = text.lower()
            for forbidden in (
                "wrangler",
                "pages deploy",
                "environment: production",
                "cloudflare_api_token",
                "supabase_db_url",
            ):
                self.assertNotIn(forbidden, lowered)

    def test_validate_never_invokes_live_hardening(self):
        self.assertNotIn("--live", self.validate_text)


if __name__ == "__main__":
    unittest.main()
