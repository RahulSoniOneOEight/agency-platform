"""Static no-rebuild / authority-boundary tests for the H.2 production workflow.

Milestone H.2, Task 11. These tests are deterministic, Flutter-free, and
network-free: they parse the committed workflow YAML/text and assert the release
pipeline's structural invariants without executing a single live step.

They prove:

- the production workflow contains no build/compile/bundle tooling anywhere,
  scanning **every** step's ``name``/``run``/``uses``/``with`` text rather than a
  single first-step name or a whole-file substring blocklist;
- no local composite action (``uses: ./...``) is referenced, since one could hide
  a build behind an opaque action;
- the only step that contains deploy tokens (``wrangler``, ``pages deploy``,
  ``cloudflare``, ``deploy``) is the named deploy step, and that step is ordered
  after the G release-gate verification and the artifact-digest verification, so
  a deploy command hidden in an earlier step fails;
- smoke/health tokens appear only in steps that run after the deploy step;
- no step writes or creates a ``ProductionAuthorization`` (including a
  ``python -c`` creation that only mentions the coordinator/repository module);
- the artifact is obtained through ``actions/download-artifact`` and the deploy
  step references that downloaded path, never a freshly built directory;
- the governed recovery step runs only on a failed outcome;
- live secrets are referenced only through GitHub secret contexts, never as
  literal values, and the ``production`` environment is declared;
- ``validate.yml`` runs every new H.2 test module and validator;
- ``validate.yml`` and ``flutter-ci.yml`` stay credential-free and never invoke a
  live deployment.

I3 adjudication (recorded; behavior intentionally unchanged): the
production-release workflow validates the committed deterministic reference
candidate fixture (ruling R10). ``tooling.hardening.candidate`` is invoked
without ``--artifact`` / ``--source-sha`` / ``--build-version`` overrides, so it
validates the pinned fixture (``FIXTURE_SOURCE_SHA`` /
``FIXTURE_BUILD_VERSION``). Live/general candidate support is a documented known
limitation: a real candidate would require a non-fixture validation mode, which
this workflow does not implement. See ``ReferenceCandidateFixtureScopeTests``.
"""

from __future__ import annotations

import copy
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

# The downloaded artifact directory must be exactly what the deploy step ships.
DOWNLOADED_ARTIFACT_PATH = "apps/production_app/build/web"

# Build/compile/bundle tooling that must never appear in ANY step. Matched
# case-insensitively against the normalized per-step blob.
FORBIDDEN_BUILD_TOKENS: tuple[str, ...] = (
    "flutter",
    "dart compile",
    "dart build",
    "dart pub",
    "build_runner",
    "npm run build",
    "yarn build",
    "pnpm build",
    "webpack",
    "vite build",
    "esbuild",
    "rollup",
    "gulp",
    "gradle",
    "xcodebuild",
    "cargo build",
)

# ``make`` needs a word boundary so it cannot be smuggled in as part of a benign
# identifier; it is still matched anywhere a build could hide.
FORBIDDEN_BUILD_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\bmake\b"),
)

# Deploy invocations. These are matched against a case-preserving blob so the
# proper-noun ``Cloudflare`` does not collide with ``CLOUDFLARE_*`` environment
# variable/secret names (which are not deploy commands).
DEPLOY_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\bwrangler\b", re.IGNORECASE),
    re.compile(r"\bpages\s+deploy\b", re.IGNORECASE),
    re.compile(r"\bCloudflare\b"),
    # A bare ``deploy`` verb, but not a hyphenated filename such as
    # ``production-deploy-output.txt`` nor an env identifier like
    # ``DEPLOY_STARTED_AT`` (both are output/telemetry plumbing, not a deploy).
    re.compile(r"(?<![-\w])deploy(?![-\w])", re.IGNORECASE),
)

# Smoke/health execution tokens. Deliberately specific so that secret/env names
# such as ``TELEMETRY_HEALTH_URL`` (which contain ``health``) are not mistaken
# for a smoke/health step.
SMOKE_HEALTH_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"tooling\.release\.smoke", re.IGNORECASE),
    re.compile(r"tooling\.release\.telemetry_health", re.IGNORECASE),
    re.compile(r"\bproduction\s+smoke\b", re.IGNORECASE),
    re.compile(r"\btelemetry\s+health\b", re.IGNORECASE),
)

# Authorization-mutating tokens. ``production_authorization.validate`` (the
# read-only G release gate) is intentionally NOT forbidden; only creation paths
# are. Tokens are matched case-insensitively on the normalized per-step blob.
FORBIDDEN_AUTHORIZATION_TOKENS: tuple[str, ...] = (
    "authorization-v",
    "production-authorization",
    "tooling.production_authorization.coordinator",
    "tooling.production_authorization.repository",
    "create_authorization",
    "filereleaseauthorization",
    ".authorize(",
    "repository.create",
    "--authorize",
)

# Case-sensitive camelCase authority symbol.
FORBIDDEN_AUTHORIZATION_SYMBOLS: tuple[str, ...] = ("ProductionAuthorization",)

AUTHORIZATION_WRITE_PATTERN = re.compile(r"--(?:write|create|authorize)\b")

REFERENCE_CANDIDATE_VALIDATOR = "python -m tooling.hardening.candidate"


def _load_yaml(path: Path) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _steps() -> list[dict[str, Any]]:
    document = _load_yaml(PRODUCTION_WORKFLOW)
    return document["jobs"][PRODUCTION_JOB]["steps"]


def _collect_strings(value: Any) -> list[str]:
    """Flatten any YAML value (scalars, mappings, sequences) into strings."""
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        collected: list[str] = []
        for key, item in value.items():
            collected.append(str(key))
            collected.extend(_collect_strings(item))
        return collected
    if isinstance(value, (list, tuple)):
        collected = []
        for item in value:
            collected.extend(_collect_strings(item))
        return collected
    return [str(value)]


def _step_text(step: dict[str, Any]) -> str:
    """Raw text of a step from its name/run/uses/with fields (and nothing else)."""
    parts: list[str] = []
    for key in ("name", "run", "uses", "with"):
        if key in step:
            parts.extend(_collect_strings(step[key]))
    return "\n".join(parts)


def _collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _normalized(step: dict[str, Any]) -> str:
    return _collapse(_step_text(step)).lower()


def _matches_any(text: str, patterns: tuple[re.Pattern[str], ...]) -> bool:
    return any(pattern.search(text) for pattern in patterns)


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


def _build_violations(steps: list[dict[str, Any]]) -> list[str]:
    """Every build/compile/bundle escape hatch found across all steps."""
    violations: list[str] = []
    for index, step in enumerate(steps):
        blob = _normalized(step)
        for token in FORBIDDEN_BUILD_TOKENS:
            if token in blob:
                violations.append(f"step {index}: forbidden build token {token!r}")
        for pattern in FORBIDDEN_BUILD_PATTERNS:
            if pattern.search(blob):
                violations.append(
                    f"step {index}: forbidden build tool {pattern.pattern!r}"
                )
        uses = str(step.get("uses", ""))
        if uses.startswith("."):
            violations.append(
                f"step {index}: local composite action {uses!r} could hide a build"
            )
    return violations


def _authorization_violations(steps: list[dict[str, Any]]) -> list[str]:
    """Every authorization-creation escape hatch found across all steps."""
    violations: list[str] = []
    for index, step in enumerate(steps):
        raw = _collapse(_step_text(step))
        lowered = raw.lower()
        for token in FORBIDDEN_AUTHORIZATION_TOKENS:
            if token in lowered:
                violations.append(
                    f"step {index}: forbidden authorization token {token!r}"
                )
        for symbol in FORBIDDEN_AUTHORIZATION_SYMBOLS:
            if symbol in raw:
                violations.append(
                    f"step {index}: forbidden authorization symbol {symbol!r}"
                )
        if "production_authorization" in lowered and AUTHORIZATION_WRITE_PATTERN.search(
            lowered
        ):
            violations.append(
                f"step {index}: production_authorization referenced with a write/create flag"
            )
    return violations


def _deploy_token_indices(steps: list[dict[str, Any]]) -> list[int]:
    return [
        index
        for index, step in enumerate(steps)
        if _matches_any(_collapse(_step_text(step)), DEPLOY_PATTERNS)
    ]


def _deploy_offenders(steps: list[dict[str, Any]]) -> list[int]:
    """Deploy-token steps other than the named deploy step."""
    named = next(
        (
            index
            for index, step in enumerate(steps)
            if DEPLOY in str(step.get("name", "")).lower()
        ),
        None,
    )
    return [index for index in _deploy_token_indices(steps) if index != named]


def _smoke_health_indices(steps: list[dict[str, Any]]) -> list[int]:
    return [
        index
        for index, step in enumerate(steps)
        if _matches_any(_collapse(_step_text(step)), SMOKE_HEALTH_PATTERNS)
    ]


class ProductionWorkflowNoRebuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = PRODUCTION_WORKFLOW.read_text(encoding="utf-8")
        self.lowered = self.text.lower()
        self.steps = _steps()

    def test_no_build_or_compile_tooling_in_any_step(self):
        # Whole-workflow, per-step scan. A ``dart compile js`` step or a build
        # hidden in a benignly named step must fail here.
        self.assertEqual(_build_violations(self.steps), [])

    def test_forbids_local_composite_actions(self):
        local = [
            step.get("uses")
            for step in self.steps
            if str(step.get("uses", "")).startswith(".")
        ]
        self.assertEqual(local, [])

    def test_downloads_exact_artifact_instead_of_building(self):
        index, step = _find_step(self.steps, DOWNLOAD)
        self.assertIn("actions/download-artifact", step["uses"])
        self.assertLess(index, _index(DEPLOY))

    def test_deploy_uses_the_downloaded_artifact_path(self):
        _, download_step = _find_step(self.steps, DOWNLOAD)
        download_path = download_step["with"]["path"]
        self.assertEqual(download_path, DOWNLOADED_ARTIFACT_PATH)
        _, deploy_step = _find_step(self.steps, DEPLOY)
        self.assertIn(download_path, deploy_step["run"])
        # And the path is only ever produced by the download, never a build.
        self.assertEqual(_build_violations(self.steps), [])

    def test_no_authorization_creation_command(self):
        # Whole-workflow, per-step scan including run/with text. A ``python -c``
        # creation must fail here.
        self.assertEqual(_authorization_violations(self.steps), [])

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

    def test_deploy_tokens_appear_only_in_the_named_deploy_step(self):
        # A deploy command hidden inside any earlier step fails this.
        self.assertEqual(_deploy_offenders(self.steps), [])

    def test_named_deploy_step_follows_gate_and_digest_verification(self):
        deploy_index, _ = _find_step(self.steps, DEPLOY)
        self.assertGreater(deploy_index, _index(VERIFY_AUTHORIZATION))
        self.assertGreater(deploy_index, _index(VERIFY_DIGEST))

    def test_smoke_and_health_run_only_after_deploy(self):
        deploy_index, _ = _find_step(self.steps, DEPLOY)
        offenders = [
            index
            for index in _smoke_health_indices(self.steps)
            if index <= deploy_index
        ]
        self.assertEqual(offenders, [])

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


class ProductionWorkflowAdversarialScanTests(unittest.TestCase):
    """Prove the hardened scanner rejects the previously-evading variants."""

    def setUp(self) -> None:
        self.steps = copy.deepcopy(_steps())

    def _with_leading_step(self, step: dict[str, Any]) -> list[dict[str, Any]]:
        self.steps.insert(0, step)
        return self.steps

    def test_dart_compile_js_build_step_is_rejected(self):
        steps = self._with_leading_step(
            {
                "name": "Build the web bundle",
                "run": (
                    "dart compile js -O4 "
                    "-o apps/production_app/build/web/main.dart.js web/main.dart"
                ),
            }
        )
        violations = _build_violations(steps)
        self.assertTrue(violations)
        self.assertTrue(any("dart compile" in violation for violation in violations))

    def test_local_composite_action_is_rejected(self):
        steps = self._with_leading_step(
            {"name": "Build the web bundle", "uses": "./.github/actions/build-web"}
        )
        violations = _build_violations(steps)
        self.assertTrue(violations)
        self.assertTrue(
            any("local composite" in violation for violation in violations)
        )

    def test_hidden_deploy_command_in_earlier_step_is_rejected(self):
        steps = self._with_leading_step(
            {
                "name": "Warm the CDN cache",
                "run": (
                    "npx --yes wrangler@3 pages deploy "
                    "apps/production_app/build/web --project-name demo "
                    "--branch production"
                ),
            }
        )
        self.assertTrue(_deploy_offenders(steps))

    def test_python_c_authorization_creation_is_rejected(self):
        steps = self._with_leading_step(
            {
                "name": "Prepare authorization",
                "run": (
                    'python -c "from tooling.production_authorization.coordinator '
                    'import create_authorization; create_authorization()"'
                ),
            }
        )
        violations = _authorization_violations(steps)
        self.assertTrue(violations)
        self.assertTrue(
            any("coordinator" in violation for violation in violations)
        )


class ReferenceCandidateFixtureScopeTests(unittest.TestCase):
    """I3 adjudication: the workflow proves the committed reference fixture.

    The production-release workflow validates the committed deterministic
    reference candidate (ruling R10), not an arbitrary live candidate. A real
    candidate would require a non-fixture validation mode; live/general candidate
    support is a documented known limitation and this workflow deliberately does
    not implement one.
    """

    def setUp(self) -> None:
        self.text = PRODUCTION_WORKFLOW.read_text(encoding="utf-8")

    def test_invokes_the_fixture_candidate_validator_without_overrides(self):
        self.assertIn(REFERENCE_CANDIDATE_VALIDATOR, self.text)
        for override in ("--artifact", "--source-sha", "--build-version"):
            self.assertNotIn(override, self.text)

    def test_reference_candidate_scope_is_documented(self):
        # The module docstring records the I3 ruling: fixture-only validation.
        docstring = _collapse(__doc__ or "")
        self.assertIn("reference candidate fixture", docstring)
        self.assertIn("non-fixture validation mode", docstring)


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
