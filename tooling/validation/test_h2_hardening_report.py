"""Deterministic H.2 hardening report tests (Milestone H.2, Task 7).

Flutter-free and network-free. These tests prove the eligibility rule (blocking
findings and staging critical journeys), that advisories are retained, that a
candidate/deployment mismatch fails validation, that the committed reference
evidence validates cleanly, and that the release workflows cannot rebuild or
deploy the production environment.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tooling.hardening.findings import make_finding
from tooling.hardening.report import (
    build_hardening_report,
    hardening_report_identity,
    hardening_report_path,
)
from tooling.hardening.staging_smoke import (
    deployment_path,
    load_candidate,
    run_staging_smoke,
    smoke_report_path,
)
from tooling.hardening.validate import (
    _load_live_deployment,
    build_live_deployment,
    evaluate_fixture_gates,
    regenerate_live_reports,
    validate_hardening,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
DEPLOYMENT = CLIENT / "production" / "release" / "staging-deployment.json"
STAGING_WORKFLOW = ROOT / ".github" / "workflows" / "staging-deploy.yml"
HARDENING_WORKFLOW = ROOT / ".github" / "workflows" / "h2-hardening.yml"

CLIENT_TREE = (
    "production/config",
    "production/evidence",
    "production/release",
    "production/hardening",
)


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


def _materialize_client(root: Path) -> Path:
    client = root / "client-projects" / "reference-commerce"
    for relative in CLIENT_TREE:
        shutil.copytree(CLIENT / relative, client / relative)
    shutil.copytree(
        ROOT / "client-projects" / "schema",
        root / "client-projects" / "schema",
    )
    return client


def _base_report(**overrides: object) -> dict:
    candidate = load_candidate(CLIENT)
    smoke = run_staging_smoke(ROOT, CLIENT, _load(DEPLOYMENT))
    gates = evaluate_fixture_gates(ROOT, CLIENT)
    report = build_hardening_report(ROOT, CLIENT, candidate, gates, smoke)
    report.update(overrides)
    return report


class EligibilityTests(unittest.TestCase):
    def test_blocking_finding_makes_candidate_ineligible(self):
        candidate = load_candidate(CLIENT)
        smoke = run_staging_smoke(ROOT, CLIENT, _load(DEPLOYMENT))
        gates = evaluate_fixture_gates(ROOT, CLIENT)
        gates["security"] = list(gates["security"]) + [
            make_finding(
                "security-test-blocker",
                "security",
                "high",
                "blocking",
                "open",
                "injected blocking finding",
            )
        ]
        report = build_hardening_report(ROOT, CLIENT, candidate, gates, smoke)
        self.assertFalse(report["eligible_for_authorization"])
        self.assertIn(
            "security-test-blocker",
            [finding["id"] for finding in report["blocking_findings"]],
        )

    def test_advisory_only_report_is_eligible_and_retains_advisories(self):
        report = _base_report()
        self.assertEqual([], report["blocking_findings"])
        self.assertTrue(report["advisory_findings"])
        self.assertTrue(report["eligible_for_authorization"])
        self.assertTrue(
            all(
                finding["disposition"] == "advisory"
                for finding in report["advisory_findings"]
            )
        )

    def test_failed_smoke_journey_makes_candidate_ineligible(self):
        def runner(journey, context):
            if journey["name"] == "b2c-order":
                return {"passed": False, "error_class": "staging_smoke_failed"}
            return {"passed": True, "error_class": None}

        candidate = load_candidate(CLIENT)
        smoke = run_staging_smoke(ROOT, CLIENT, _load(DEPLOYMENT), http=runner)
        gates = evaluate_fixture_gates(ROOT, CLIENT)
        report = build_hardening_report(ROOT, CLIENT, candidate, gates, smoke)
        self.assertEqual([], report["blocking_findings"])
        self.assertFalse(report["staging_smoke_ref"]["critical_journeys_passed"])
        self.assertFalse(report["eligible_for_authorization"])

    def test_report_identity_self_verifies(self):
        report = _base_report()
        self.assertEqual(
            report["report_identity"], hardening_report_identity(report)
        )

    def test_gate_results_cover_every_area_and_are_sorted(self):
        report = _base_report()
        areas = [gate["area"] for gate in report["gate_results"]]
        self.assertEqual(sorted(areas), areas)
        self.assertEqual(
            {
                "accessibility",
                "analytics",
                "migrations",
                "observability",
                "performance",
                "security",
            },
            set(areas),
        )

    def test_missing_gate_area_becomes_blocking_evidence_finding(self):
        candidate = load_candidate(CLIENT)
        smoke = run_staging_smoke(ROOT, CLIENT, _load(DEPLOYMENT))
        gates = evaluate_fixture_gates(ROOT, CLIENT)
        del gates["performance"]
        report = build_hardening_report(ROOT, CLIENT, candidate, gates, smoke)
        self.assertIn(
            "performance-evidence-missing",
            [finding["id"] for finding in report["blocking_findings"]],
        )
        self.assertFalse(report["eligible_for_authorization"])
        performance = next(
            gate for gate in report["gate_results"] if gate["area"] == "performance"
        )
        self.assertFalse(performance["passed"])


class ValidationTests(unittest.TestCase):
    def test_reference_reports_validate_cleanly(self):
        self.assertEqual([], validate_hardening(ROOT, CLIENT))

    def test_candidate_identity_mismatch_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = hardening_report_path(client)
            report = _load(path)
            report["candidate_identity"] = "sha256:" + "0" * 64
            _write(path, report)
            errors = validate_hardening(root, client)
        self.assertTrue(errors)
        self.assertEqual(errors, sorted(errors))
        self.assertTrue(
            any(
                "candidate_identity does not match the committed release candidate"
                in error
                for error in errors
            ),
            errors,
        )

    def test_staging_deployment_digest_mismatch_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            deployment = _load(deployment_path(client))
            deployment["artifact_digest"] = "sha256:" + "0" * 64
            _write(deployment_path(client), deployment)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any(
                "artifact_digest does not match the committed release candidate"
                in error
                for error in errors
            ),
            errors,
        )

    def test_dropped_advisory_list_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = hardening_report_path(client)
            report = _load(path)
            report["advisory_findings"] = "dropped"
            _write(path, report)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any("advisory_findings must be retained as a list" in error for error in errors),
            errors,
        )

    def test_eligible_inconsistency_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = hardening_report_path(client)
            report = _load(path)
            report["eligible_for_authorization"] = False
            report["report_identity"] = hardening_report_identity(report)
            _write(path, report)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any(
                "eligible_for_authorization is inconsistent" in error
                for error in errors
            ),
            errors,
        )

    def test_smoke_report_identity_is_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = smoke_report_path(client)
            smoke = _load(path)
            smoke["deployment_id"] = "tampered"
            _write(path, smoke)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any("report_identity does not verify" in error for error in errors),
            errors,
        )

    def test_dropped_advisory_union_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = hardening_report_path(client)
            report = _load(path)
            report["advisory_findings"] = []
            report["report_identity"] = hardening_report_identity(report)
            _write(path, report)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any(
                "advisory_findings does not equal the sorted union" in error
                for error in errors
            ),
            errors,
        )

    def test_hidden_gate_blocking_finding_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = hardening_report_path(client)
            report = _load(path)
            hidden = make_finding(
                "security-hidden-blocker",
                "security",
                "high",
                "blocking",
                "open",
                "hidden blocking finding",
            )
            security = next(
                gate for gate in report["gate_results"] if gate["area"] == "security"
            )
            security["findings"] = sorted(
                security["findings"] + [hidden],
                key=lambda finding: (finding["area"], finding["id"]),
            )
            security["blocking_findings"] = [hidden]
            security["passed"] = False
            report["report_identity"] = hardening_report_identity(report)
            _write(path, report)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any(
                "blocking_findings does not equal the sorted union" in error
                for error in errors
            ),
            errors,
        )

    def test_gate_area_set_is_exact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            path = hardening_report_path(client)
            report = _load(path)
            report["gate_results"] = report["gate_results"] + [
                dict(report["gate_results"][0])
            ]
            report["report_identity"] = hardening_report_identity(report)
            _write(path, report)
            errors = validate_hardening(root, client)
        self.assertTrue(
            any(
                "gate_results must contain exactly each gate area once" in error
                for error in errors
            ),
            errors,
        )

    def test_tampered_staging_smoke_ref_fails_validation(self):
        for field, value in (
            ("report_identity", "sha256:" + "0" * 64),
            ("deployment_id", "staging-deploy-9999"),
            ("artifact_digest", "sha256:" + "0" * 64),
            ("candidate_identity", "sha256:" + "0" * 64),
            ("critical_journeys_passed", False),
        ):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    client = _materialize_client(root)
                    path = hardening_report_path(client)
                    report = _load(path)
                    report["staging_smoke_ref"][field] = value
                    report["report_identity"] = hardening_report_identity(report)
                    _write(path, report)
                    errors = validate_hardening(root, client)
                self.assertTrue(
                    any("staging_smoke_ref" in error for error in errors), errors
                )

    def test_report_candidate_field_mismatches_fail_validation(self):
        for field in (
            "artifact_digest",
            "migration_set_identity",
            "release_config_identity",
        ):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    client = _materialize_client(root)
                    path = hardening_report_path(client)
                    report = _load(path)
                    report[field] = "sha256:" + "0" * 64
                    report["report_identity"] = hardening_report_identity(report)
                    _write(path, report)
                    errors = validate_hardening(root, client)
                self.assertTrue(
                    any(
                        f"{field} does not match the committed release candidate"
                        in error
                        for error in errors
                    ),
                    errors,
                )


class LiveDeploymentTests(unittest.TestCase):
    def test_build_live_deployment_uses_real_url_and_candidate_binding(self):
        candidate = load_candidate(CLIENT)
        deployment = build_live_deployment(
            candidate, url="https://real.staging.example"
        )
        self.assertEqual("https://real.staging.example", deployment["url"])
        self.assertEqual("staging", deployment["environment"])
        self.assertEqual("succeeded", deployment["status"])
        self.assertEqual(candidate["artifact_digest"], deployment["artifact_digest"])
        self.assertEqual(
            candidate["candidate_identity"], deployment["candidate_identity"]
        )
        self.assertTrue(deployment["deployment_id"])

    def test_live_deployment_artifact_overrides_placeholder(self):
        candidate = load_candidate(CLIENT)
        deployment = build_live_deployment(
            candidate,
            url="https://real.staging.example",
            deployment={
                "deployment_id": "staging-deploy-4242",
                "url": "https://placeholder.example",
            },
        )
        self.assertEqual("staging-deploy-4242", deployment["deployment_id"])
        self.assertEqual("https://real.staging.example", deployment["url"])

    def test_load_live_deployment_reads_environment_url(self):
        candidate = load_candidate(CLIENT)
        with mock.patch.dict(
            os.environ, {"STAGING_DEPLOYMENT_URL": "https://env.staging.example"}
        ):
            deployment = _load_live_deployment(ROOT, CLIENT, candidate, None, None)
        self.assertEqual("https://env.staging.example", deployment["url"])

    def test_load_live_deployment_requires_a_source(self):
        candidate = load_candidate(CLIENT)
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SystemExit):
                _load_live_deployment(ROOT, CLIENT, candidate, None, None)

    def test_regenerate_live_reports_probes_the_real_url(self):
        candidate = load_candidate(CLIENT)
        with mock.patch.dict(os.environ, {}, clear=True):
            deployment = build_live_deployment(
                candidate, url="https://real.staging.example"
            )
        probed: list[str] = []

        def runner(journey, context):
            probed.append(context.get("base_url"))
            return {"passed": True, "error_class": None}

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            regenerate_live_reports(
                root, client, deployment=deployment, runner=runner
            )
            smoke = _load(smoke_report_path(client))
        self.assertTrue(probed)
        self.assertTrue(
            all(url == "https://real.staging.example" for url in probed), probed
        )
        self.assertNotIn("placeholder", str(probed))
        self.assertEqual("staging-0.1.0+h2rc1", smoke["deployment_id"])


class WorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.staging = STAGING_WORKFLOW.read_text(encoding="utf-8")
        self.staging_lower = self.staging.lower()
        self.hardening = HARDENING_WORKFLOW.read_text(encoding="utf-8")
        self.hardening_lower = self.hardening.lower()

    def test_staging_deploy_never_rebuilds_flutter_web(self):
        self.assertNotIn("flutter build web", self.staging_lower)
        self.assertIn("wrangler", self.staging_lower)
        self.assertIn("download-artifact", self.staging_lower)

    def test_staging_deploy_never_targets_production(self):
        self.assertNotIn("--branch production", self.staging_lower)
        self.assertNotIn("--production", self.staging_lower)
        self.assertNotIn("environment: production", self.staging_lower)
        self.assertIn("--branch staging", self.staging_lower)

    def test_hardening_workflow_never_creates_authorization(self):
        self.assertNotIn("authorization", self.hardening_lower)
        self.assertNotIn("tooling.production_authorization", self.hardening_lower)

    def test_hardening_workflow_never_deploys_production(self):
        self.assertNotIn("wrangler", self.hardening_lower)
        self.assertNotIn("pages deploy", self.hardening_lower)
        self.assertNotIn("--production", self.hardening_lower)
        self.assertNotIn("environment: production", self.hardening_lower)

    def test_hardening_workflow_has_credential_free_and_live_modes(self):
        self.assertIn("pull_request", self.hardening)
        self.assertIn("workflow_dispatch", self.hardening)
        self.assertIn("python -m tooling.hardening.validate", self.hardening)
        self.assertIn("--live", self.hardening)


if __name__ == "__main__":
    unittest.main()
