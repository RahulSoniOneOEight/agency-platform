"""Deterministic H.1 production-foundation report tests (Milestone H.1, Task 9).

These tests are Flutter-free: they exercise ``build_h1_report`` and
``validate_h1_report`` against the committed reference client and against
controlled temp copies. The committed report is the aggregated, self-verifying
evidence artifact for the H.1 production foundation. It records ids, versions,
counts, statuses, and references and never copies an approval, QA finding, or
authorization body, and it contains no subjective score.
"""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tooling.production.report import (
    EVIDENCE_RELATIVE,
    REPORT_NAME,
    REPORT_VERSION,
    REQUIRED_REPORT_KEYS,
    build_h1_report,
    canonical_report,
    h1_report_identity,
    validate_h1_report,
    validate_production_foundation,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
REPORT_PATH = CLIENT / EVIDENCE_RELATIVE / REPORT_NAME
FIXTURE_PATH = CLIENT / "production" / "fixtures" / "integration-scenarios.json"

FORBIDDEN_SCORE_KEYS = {"overall_score", "score", "quality_score", "rating"}

EXPECTED_PORTS = {
    "AccountRepository",
    "AuthService",
    "CartRepository",
    "CatalogRepository",
    "CrmPort",
    "CustomerRepository",
    "ErpPort",
    "InventoryRepository",
    "OrderRepository",
    "PaymentPort",
    "QuoteRepository",
    "ShippingPort",
    "WhatsAppPort",
}

EXPECTED_SUPABASE_ADAPTERS = {
    "SupabaseAccountRepository",
    "SupabaseAuthAdapter",
    "SupabaseCartRepository",
    "SupabaseCatalogRepository",
    "SupabaseOrderRepository",
    "SupabaseQuoteRepository",
}

EXPECTED_FAKE_ADAPTERS = {
    "FakeCrmAdapter",
    "FakeErpAdapter",
    "FakePaymentAdapter",
    "FakeShippingAdapter",
    "FakeWhatsAppAdapter",
}

EXPECTED_ENVIRONMENTS = ("dev", "staging", "production")

REQUIRED_FAILURE_SCENARIO_IDS = {
    "expired-session-refresh",
    "forbidden-b2b-action",
    "inventory-unavailable",
    "stale-cart",
    "backend-unavailable",
    "timeout",
    "retryable-vs-non-retryable",
    "duplicate-order-protection",
    "malformed-environment-config",
}

AUTHORITY_KEYS = {
    "f_machine_report",
    "g_release_candidate",
    "g_production_authorization",
}


def _forbidden_paths(value, forbidden=FORBIDDEN_SCORE_KEYS, prefix=""):
    paths = []
    if isinstance(value, dict):
        for key, item in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            if key in forbidden:
                paths.append(path)
            paths.extend(_forbidden_paths(item, forbidden, path))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            paths.extend(_forbidden_paths(item, forbidden, f"{prefix}[{index}]"))
    return paths


def _stage_temp_repo(tmp: Path) -> tuple[Path, Path]:
    """Copy the minimal repository subset needed by the H.1 report into *tmp*."""
    root = tmp / "root"
    root.mkdir()
    source = ROOT / "client-projects" / "reference-commerce"
    client = root / "client-projects" / "reference-commerce"
    for name in ("production", "reference-e2e", "release"):
        shutil.copytree(source / name, client / name)
    shutil.copytree(ROOT / "supabase", root / "supabase")
    for relative in (
        "packages/agency_production_core/lib/src/ports",
        "packages/agency_supabase_adapter/lib/src",
        "packages/agency_integration_adapters/lib/src/fake",
    ):
        shutil.copytree(ROOT / relative, root / relative)
    return root, client


def _read_report(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_report(path: Path, report: dict) -> None:
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


class H1ReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.report = build_h1_report(ROOT, CLIENT)

    def test_report_has_required_keys(self):
        self.assertTrue(
            set(REQUIRED_REPORT_KEYS).issubset(self.report),
            set(REQUIRED_REPORT_KEYS) - set(self.report),
        )

    def test_report_has_no_subjective_score(self):
        self.assertEqual([], _forbidden_paths(self.report))

    def test_report_identity_fields(self):
        self.assertEqual(REPORT_VERSION, self.report["report_version"])
        self.assertEqual("reference-commerce", self.report["client_id"])

    def test_report_identity_verifies(self):
        self.assertTrue(self.report["report_identity"].startswith("sha256:"))
        self.assertEqual(
            self.report["report_identity"],
            h1_report_identity(self.report),
        )

    def test_report_covers_every_environment(self):
        environments = self.report["environments"]
        self.assertEqual(
            [entry["environment"] for entry in environments],
            list(EXPECTED_ENVIRONMENTS),
        )
        for entry in environments:
            self.assertTrue(
                entry["ref"].endswith(
                    f"production/config/{entry['environment']}.json"
                ),
                entry["ref"],
            )
            self.assertIsInstance(entry["api_base_url"], str)
            self.assertIsInstance(entry["supabase_configured"], bool)
            self.assertIsInstance(entry["analytics_enabled"], bool)
            self.assertIsInstance(entry["feature_flags"], dict)
            self.assertIsInstance(entry["integration_modes"], dict)
            self.assertTrue(entry["config_identity"].startswith("sha256:"))

    def test_report_never_copies_a_secret_value(self):
        serialized = json.dumps(self.report).lower()
        for forbidden in (
            "service_role",
            "private_key",
            "webhook_secret",
            "erp_password",
            "payment_secret",
            "whatsapp_token",
            "anon_key\"",
        ):
            self.assertNotIn(forbidden, serialized)

    def test_report_lists_provider_neutral_ports(self):
        names = {entry["name"] for entry in self.report["ports"]}
        self.assertEqual(EXPECTED_PORTS, names)
        for entry in self.report["ports"]:
            self.assertTrue(entry["ref"].startswith("packages/agency_production_core/"))

    def test_report_lists_supabase_and_fake_adapters(self):
        adapters = self.report["adapters"]
        self.assertEqual(
            EXPECTED_SUPABASE_ADAPTERS,
            {entry["name"] for entry in adapters["supabase"]},
        )
        self.assertEqual(
            EXPECTED_FAKE_ADAPTERS,
            {entry["name"] for entry in adapters["fake_integrations"]},
        )
        self.assertIn("deterministic", adapters)

    def test_report_records_versioned_migrations(self):
        migrations = self.report["migrations"]
        self.assertEqual(
            ["202609180001", "202609180002"],
            [entry["version"] for entry in migrations],
        )
        for entry in migrations:
            self.assertEqual("additive", entry["migration_class"])
            self.assertTrue(entry["ref"].startswith("supabase/migrations/"))
            self.assertTrue(entry["identity"].startswith("sha256:"))

    def test_report_restates_the_integration_fixture(self):
        fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(fixture["b2c_path"], self.report["b2c_path"])
        self.assertEqual(fixture["b2b_path"], self.report["b2b_path"])
        self.assertEqual(
            fixture["failure_scenarios"], self.report["failure_scenarios"]
        )
        self.assertEqual(
            REQUIRED_FAILURE_SCENARIO_IDS,
            {entry["id"] for entry in self.report["failure_scenarios"]},
        )

    def test_report_references_authorities_by_identity_and_ref(self):
        checks = self.report["authority_checks"]
        self.assertIs(False, checks["h1_creates_production_authorization"])
        self.assertIs(False, checks["h1_performs_production_deployment"])
        for key in AUTHORITY_KEYS:
            self.assertIn(key, checks, key)
            self.assertIn("ref", checks[key], key)
            self.assertTrue(
                (ROOT / checks[key]["ref"]).exists(), checks[key]["ref"]
            )
        self.assertTrue(
            checks["f_machine_report"]["report_identity"].startswith("sha256:")
        )
        self.assertTrue(
            checks["g_release_candidate"]["identity"].startswith("sha256:")
        )
        self.assertTrue(
            checks["g_production_authorization"]["identity"].startswith("sha256:")
        )

    def test_generation_is_byte_identical(self):
        first = canonical_report(build_h1_report(ROOT, CLIENT))
        second = canonical_report(build_h1_report(ROOT, CLIENT))
        self.assertEqual(first, second)

    def test_committed_report_matches_fresh_build(self):
        committed = REPORT_PATH.read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(
            canonical_report(build_h1_report(ROOT, CLIENT)).encode("utf-8"),
            committed,
        )

    def test_committed_report_is_valid(self):
        self.assertEqual([], validate_h1_report(ROOT, CLIENT))

    def test_committed_report_validates_production_foundation(self):
        self.assertEqual([], validate_production_foundation(ROOT, CLIENT))


class H1ReportFailureModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp(prefix="h1-report-")
        self.addCleanup(shutil.rmtree, self._tmp, True)
        self.root, self.client = _stage_temp_repo(Path(self._tmp))
        self.report_path = self.client / EVIDENCE_RELATIVE / REPORT_NAME

    def test_clean_temp_copy_is_valid(self):
        self.assertEqual([], validate_h1_report(self.root, self.client))

    def test_missing_report_is_rejected(self):
        self.report_path.unlink()
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(any("missing" in error for error in errors), errors)

    def test_stale_report_bytes_are_rejected(self):
        report = _read_report(self.report_path)
        self.report_path.write_text(
            json.dumps(report, indent=4, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(any("stale" in error for error in errors), errors)

    def test_tampered_report_identity_is_rejected(self):
        report = _read_report(self.report_path)
        report["report_identity"] = "sha256:" + "0" * 64
        _write_report(self.report_path, report)
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(any("report_identity" in error for error in errors), errors)

    def test_missing_required_key_is_rejected(self):
        report = _read_report(self.report_path)
        del report["ports"]
        _write_report(self.report_path, report)
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(any("ports" in error for error in errors), errors)

    def test_authorizing_self_claim_is_rejected(self):
        report = _read_report(self.report_path)
        report["authority_checks"]["h1_creates_production_authorization"] = True
        _write_report(self.report_path, report)
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(
            any("ProductionAuthorization" in error for error in errors), errors
        )

    def test_deploying_self_claim_is_rejected(self):
        report = _read_report(self.report_path)
        report["authority_checks"]["h1_performs_production_deployment"] = True
        _write_report(self.report_path, report)
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(any("deploy" in error.lower() for error in errors), errors)

    def test_report_identity_mismatch_after_edit_is_rejected(self):
        report = _read_report(self.report_path)
        report["client_id"] = "someone-else"
        _write_report(self.report_path, report)
        errors = validate_h1_report(self.root, self.client)
        self.assertTrue(any("client_id" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
