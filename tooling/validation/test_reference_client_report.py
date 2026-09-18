"""Aggregated machine/human report and reference-client validator tests (F.3 Task 10).

These tests are Flutter-free (RF17): they exercise ``build_machine_report``,
``render_human_report`` and ``validate_reference_client`` against the committed
reference client and against controlled temp copies. The temp copies prove that
every required failure mode is rejected deterministically; the committed
reference client is never modified.
"""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tooling.reference_client.report import (
    build_machine_report,
    canonical_report,
    machine_report_identity,
    render_human_report,
)
from tooling.reference_client.validate_reference_client import (
    validate_reference_client,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
REPORT_DIR = CLIENT / "reference-e2e" / "report"
MACHINE_PATH = REPORT_DIR / "reference-report.json"
HUMAN_PATH = REPORT_DIR / "reference-report.md"
BUNDLE_PATH = (
    ROOT
    / "apps"
    / "prototype_app"
    / "assets"
    / "generated"
    / "reference-commerce.json"
)
EVIDENCE_NAMES = (
    "review-approval-evidence.json",
    "change-scenarios-evidence.json",
    "resume-evidence.json",
)

FORBIDDEN_SCORE_KEYS = {"overall_score", "score", "quality_score"}

REQUIRED_MACHINE_KEYS = {
    "report_version",
    "client_id",
    "fixture_version",
    "fixture_identity",
    "scenario_ids",
    "source_commit_sha",
    "workflow",
    "evidence_refs",
    "review",
    "approvals",
    "qa",
    "assertions",
    "known_limitations",
    "report_identity",
}

HUMAN_SECTIONS = (
    "Synthetic client profile",
    "B2C scope",
    "B2B scope",
    "Three directions",
    "Selected and mixed experience",
    "Blocking and non-blocking feedback",
    "Visual annotation",
    "Refinement batch",
    "Approval v1",
    "QA",
    "Contract-impacting change",
    "Approval v2",
    "Implementation-only",
    "Interruption and resume",
    "Known limitations",
    "Evidence references",
)


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
    """Copy the minimal repository subset needed by the validator into *tmp*."""
    root = tmp / "root"
    root.mkdir()
    shutil.copytree(ROOT / "design-contract", root / "design-contract")
    shutil.copytree(ROOT / "workflows", root / "workflows")
    shutil.copytree(ROOT / "client-projects", root / "client-projects")
    bundle_dir = root / "apps" / "prototype_app" / "assets" / "generated"
    bundle_dir.mkdir(parents=True)
    shutil.copy2(BUNDLE_PATH, bundle_dir / "reference-commerce.json")
    client = root / "client-projects" / "reference-commerce"
    return root, client


def _read_report(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_report(path: Path, report: dict) -> None:
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


class MachineReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.report = build_machine_report(ROOT, CLIENT)

    def test_machine_report_has_required_keys(self):
        self.assertTrue(
            REQUIRED_MACHINE_KEYS.issubset(self.report),
            REQUIRED_MACHINE_KEYS - set(self.report),
        )

    def test_machine_report_has_no_score_key(self):
        self.assertEqual([], _forbidden_paths(self.report))

    def test_machine_report_identity_fields(self):
        self.assertEqual(1, self.report["report_version"])
        self.assertEqual("reference-commerce", self.report["client_id"])
        self.assertEqual(1, self.report["fixture_version"])
        self.assertTrue(self.report["fixture_identity"].startswith("sha256:"))
        self.assertEqual(
            [
                "normal-happy-path",
                "contract-change-reapproval",
                "implementation-only-change",
                "resume-after-interruption",
            ],
            self.report["scenario_ids"],
        )

    def test_machine_report_aggregates_three_evidence_files(self):
        by_source = self.report["assertions"]["by_source"]
        for name in EVIDENCE_NAMES:
            matches = [ref for ref in by_source if ref.endswith(name)]
            self.assertEqual(1, len(matches), (name, list(by_source)))
        self.assertEqual(
            sum(entry["total"] for entry in by_source.values()),
            self.report["assertions"]["total"],
        )
        self.assertEqual(
            sum(entry["passed"] for entry in by_source.values()),
            self.report["assertions"]["passed"],
        )
        self.assertEqual(
            self.report["assertions"]["total"] - self.report["assertions"]["passed"],
            self.report["assertions"]["failed"],
        )
        self.assertEqual(0, self.report["assertions"]["failed"])

    def test_machine_report_approvals_are_ids_and_hashes_only(self):
        approvals = self.report["approvals"]
        self.assertEqual([1, 2], [entry["version"] for entry in approvals])
        for entry in approvals:
            self.assertEqual(
                {"version", "review_round", "review_state_hash", "source_commit_sha"},
                set(entry),
            )
            self.assertTrue(entry["review_state_hash"].startswith("sha256:"))
            self.assertRegex(entry["source_commit_sha"], r"^[0-9a-f]{40}$")
        authority_keys = {
            "history",
            "text",
            "reviewed_by",
            "approved_by",
            "unresolved_non_blocking",
        }
        self.assertEqual([], _forbidden_paths(self.report, authority_keys))

    def test_machine_report_identity_verifies(self):
        self.assertEqual(
            self.report["report_identity"],
            machine_report_identity(self.report),
        )

    def test_committed_machine_report_matches_fresh_build(self):
        self.assertEqual(
            canonical_report(build_machine_report(ROOT, CLIENT)),
            MACHINE_PATH.read_text(encoding="utf-8"),
        )

    def test_workflow_reports_resume_attempts_and_stage(self):
        workflow = self.report["workflow"]
        self.assertEqual("visual-qa", workflow["current_stage"])
        self.assertEqual(2, len(workflow["attempt_ids"]))
        self.assertIn("visual-qa", workflow["validators"])


class HumanReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.machine = build_machine_report(ROOT, CLIENT)
        self.markdown = render_human_report(self.machine)

    def test_human_report_contains_required_sections(self):
        for section in HUMAN_SECTIONS:
            self.assertIn(section, self.markdown, section)

    def test_human_report_names_checkout_limitation(self):
        self.assertIn("checkout", self.markdown.lower())

    def test_human_report_states_it_is_explanatory_evidence(self):
        lowered = self.markdown.lower()
        self.assertIn("explanatory evidence", lowered)
        self.assertIn("machine assertions", lowered)

    def test_human_report_has_no_score(self):
        self.assertNotIn("overall_score", self.markdown)
        self.assertNotIn("quality_score", self.markdown)
        self.assertNotIn("score", self.markdown.lower())

    def test_committed_human_report_matches_fresh_render(self):
        self.assertEqual(
            render_human_report(build_machine_report(ROOT, CLIENT)),
            HUMAN_PATH.read_text(encoding="utf-8"),
        )


class ValidatorRealRepositoryTests(unittest.TestCase):
    def test_validate_reference_client_returns_empty_for_real_repository(self):
        self.assertEqual([], validate_reference_client(ROOT, CLIENT))

    def test_committed_machine_report_validates_against_schema(self):
        schema_path = (
            ROOT
            / "client-projects"
            / "schema"
            / "reference-client-machine-report.schema.json"
        )
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        from jsonschema import Draft202012Validator

        errors = list(
            Draft202012Validator(schema).iter_errors(_read_report(MACHINE_PATH))
        )
        self.assertEqual([], errors)


class ValidatorFailureModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp(prefix="reference-report-")
        self.addCleanup(shutil.rmtree, self._tmp, True)
        self.root, self.client = _stage_temp_repo(Path(self._tmp))

    def _errors(self) -> list[str]:
        return validate_reference_client(self.root, self.client)

    def _joined(self, errors: list[str]) -> str:
        return "\n".join(errors)

    def test_clean_temp_copy_is_valid(self):
        self.assertEqual([], self._errors())

    def test_fixture_identity_mismatch_is_rejected(self):
        report = _read_report(self.client / "reference-e2e" / "report" / "reference-report.json")
        report["fixture_identity"] = "sha256:" + "0" * 64
        _write_report(
            self.client / "reference-e2e" / "report" / "reference-report.json", report
        )
        errors = self._errors()
        self.assertIn("fixture_identity", self._joined(errors), errors)

    def test_missing_scenario_id_is_rejected(self):
        import yaml

        scenario_path = self.client / "reference-e2e" / "scenario.yaml"
        scenario = yaml.safe_load(scenario_path.read_text(encoding="utf-8"))
        scenario["scenarios"] = scenario["scenarios"][:-1]
        scenario_path.write_text(
            yaml.safe_dump(scenario, sort_keys=False), encoding="utf-8"
        )
        errors = self._errors()
        self.assertIn("scenario", self._joined(errors).lower(), errors)

    def test_bad_approval_versions_are_rejected(self):
        report_path = self.client / "reference-e2e" / "report" / "reference-report.json"
        report = _read_report(report_path)
        report["approvals"] = [
            {**report["approvals"][0], "version": 2},
            {**report["approvals"][1], "version": 1},
        ]
        _write_report(report_path, report)
        errors = self._errors()
        self.assertIn("approval", self._joined(errors).lower(), errors)

    def test_missing_qa_evidence_is_rejected(self):
        (
            self.client
            / "reference-e2e"
            / "evidence"
            / "review-approval-evidence.json"
        ).unlink()
        errors = self._errors()
        self.assertIn("review-approval-evidence.json", self._joined(errors), errors)

    def test_missing_resume_evidence_is_rejected(self):
        (
            self.client / "reference-e2e" / "evidence" / "resume-evidence.json"
        ).unlink()
        errors = self._errors()
        self.assertIn("resume", self._joined(errors).lower(), errors)

    def test_source_mismatch_is_rejected(self):
        report_path = self.client / "reference-e2e" / "report" / "reference-report.json"
        report = _read_report(report_path)
        report["source_commit_sha"] = "f" * 40
        _write_report(report_path, report)
        errors = self._errors()
        self.assertIn("source_commit_sha", self._joined(errors), errors)

    def test_duplicate_authority_file_is_rejected(self):
        review_dir = self.client / "reference-e2e" / "review"
        review_dir.mkdir(parents=True)
        (review_dir / "approval-v1.json").write_text("{}", encoding="utf-8")
        errors = self._errors()
        self.assertIn("authority", self._joined(errors).lower(), errors)

    def test_failing_assertion_is_rejected(self):
        evidence_path = (
            self.client
            / "reference-e2e"
            / "evidence"
            / "review-approval-evidence.json"
        )
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
        evidence["assertions"][0]["passed"] = False
        evidence_path.write_text(
            json.dumps(evidence, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        errors = self._errors()
        self.assertIn("passed", self._joined(errors).lower(), errors)

    def test_stale_report_bytes_are_rejected(self):
        report_path = self.client / "reference-e2e" / "report" / "reference-report.json"
        report = _read_report(report_path)
        report_path.write_text(
            json.dumps(report, indent=4, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        errors = self._errors()
        self.assertIn("stale", self._joined(errors).lower(), errors)

    def test_tampered_report_identity_is_rejected(self):
        report_path = self.client / "reference-e2e" / "report" / "reference-report.json"
        report = _read_report(report_path)
        report["report_identity"] = "sha256:" + "0" * 64
        _write_report(report_path, report)
        errors = self._errors()
        self.assertIn("report_identity", self._joined(errors), errors)


if __name__ == "__main__":
    unittest.main()
