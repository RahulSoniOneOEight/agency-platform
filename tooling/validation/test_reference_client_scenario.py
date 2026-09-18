from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

from tooling.reference_client.assertions import (
    evaluate_assertions,
    load_assertions,
    validate_assertions,
)
from tooling.reference_client.scenario import (
    load_scenario,
    scenario_ids,
    validate_scenario,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SCENARIO_PATH = CLIENT / "reference-e2e" / "scenario.yaml"
ASSERTIONS_PATH = CLIENT / "reference-e2e" / "assertions.yaml"
SCHEMA_PATH = (
    ROOT / "client-projects" / "schema" / "reference-client-scenario.schema.json"
)
BUNDLE_PATH = (
    ROOT
    / "apps"
    / "prototype_app"
    / "assets"
    / "generated"
    / "reference-commerce.json"
)

REQUIRED_SCENARIO_IDS = [
    "normal-happy-path",
    "contract-change-reapproval",
    "implementation-only-change",
    "resume-after-interruption",
]


def _copy_client(destination: Path) -> Path:
    client = destination / "reference-commerce"
    shutil.copytree(CLIENT, client)
    return client


class ReferenceScenarioTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = load_scenario(SCENARIO_PATH)

    def test_scenario_ids_are_ordered_and_stable(self):
        self.assertEqual(REQUIRED_SCENARIO_IDS, scenario_ids(self.scenario))

    def test_scenario_declares_direction_identities(self):
        self.assertEqual(
            {
                "a": "efficient-commerce",
                "b": "premium-discovery",
                "c": "trade-first",
            },
            self.scenario["direction_identities"],
        )
        self.assertEqual("reference-commerce", self.scenario["client_id"])
        self.assertEqual(1, self.scenario["version"])
        self.assertEqual(1, self.scenario["fixture_version"])

    def test_validate_scenario_accepts_real_client(self):
        self.assertEqual([], validate_scenario(ROOT, CLIENT))

    def test_tampered_scenario_order_is_reported(self):
        tampered = copy.deepcopy(self.scenario)
        first, second = tampered["scenarios"][0], tampered["scenarios"][1]
        tampered["scenarios"][0], tampered["scenarios"][1] = second, first
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "reference-commerce"
            e2e = client / "reference-e2e"
            e2e.mkdir(parents=True)
            (e2e / "scenario.yaml").write_text(
                yaml.safe_dump(tampered, sort_keys=False), encoding="utf-8"
            )
            errors = validate_scenario(ROOT, client)
        self.assertTrue(
            any("scenario ids must be" in error for error in errors), errors
        )

    def test_json_schema_accepts_real_scenario(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        errors = list(Draft202012Validator(schema).iter_errors(self.scenario))
        self.assertEqual([], errors)

    def test_json_schema_rejects_unknown_top_level_key(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        tampered = copy.deepcopy(self.scenario)
        tampered["unexpected_top_level_key"] = True
        errors = list(Draft202012Validator(schema).iter_errors(tampered))
        self.assertTrue(errors)


class ReferenceAssertionTests(unittest.TestCase):
    def test_assertions_document_is_a_list(self):
        raw = yaml.safe_load(ASSERTIONS_PATH.read_text(encoding="utf-8"))
        self.assertIsInstance(raw, dict)
        self.assertEqual(1, raw["version"])
        self.assertEqual("reference-commerce", raw["client_id"])
        document = load_assertions(ASSERTIONS_PATH)
        self.assertIsInstance(document["assertions"], list)
        self.assertTrue(document["assertions"])

    def test_validate_assertions_accepts_real_client(self):
        self.assertEqual([], validate_assertions(ROOT, CLIENT))

    def test_every_assertion_passes_for_real_repository(self):
        results = evaluate_assertions(ROOT, CLIENT)
        self.assertTrue(results)
        failed = [result for result in results if not result.passed]
        self.assertEqual([], failed, [result.detail for result in failed])
        kinds = {
            "fixture_coverage",
            "fixture_integrity",
            "direction_ids",
            "direction_identity",
            "journey_contains",
            "artifact_exists",
            "workflow_state",
            "bundle_client_id",
            "bundle_fresh",
            "no_duplicate_authority",
        }
        document = load_assertions(ASSERTIONS_PATH)
        self.assertEqual(kinds, {entry["kind"] for entry in document["assertions"]})

    def test_tampered_fixture_fails_coverage_assertion(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = _copy_client(Path(tmp))
            fixture_path = client / "reference-e2e" / "fixture.yaml"
            fixture = yaml.safe_load(fixture_path.read_text(encoding="utf-8"))
            fixture["coverage"]["b2b"] = False
            fixture_path.write_text(
                yaml.safe_dump(fixture, sort_keys=False), encoding="utf-8"
            )

            results = {
                result.id: result
                for result in evaluate_assertions(ROOT, client)
            }
        coverage = results["fixture-covers-b2c-and-b2b"]
        self.assertFalse(coverage.passed)
        self.assertIsNotNone(coverage.detail)

    def test_bundle_fresh_fails_when_committed_bundle_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            temp_root = Path(tmp) / "root"
            temp_client = temp_root / "client-projects" / "reference-commerce"
            shutil.copytree(CLIENT, temp_client)
            shutil.copytree(ROOT / "design-contract", temp_root / "design-contract")
            bundle_dir = (
                temp_root / "apps" / "prototype_app" / "assets" / "generated"
            )
            bundle_dir.mkdir(parents=True)
            tampered = BUNDLE_PATH.read_bytes() + b"\n"
            (bundle_dir / "reference-commerce.json").write_bytes(tampered)

            results = {
                result.id: result
                for result in evaluate_assertions(temp_root, temp_client)
            }
        fresh = results["bundle-byte-fresh"]
        self.assertFalse(fresh.passed)
        self.assertIsNotNone(fresh.detail)

    def test_no_duplicate_authority_fails_when_approval_added(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = _copy_client(Path(tmp))
            review_dir = client / "reference-e2e" / "review"
            review_dir.mkdir(parents=True)
            (review_dir / "approval-v1.json").write_text("{}", encoding="utf-8")

            results = {
                result.id: result
                for result in evaluate_assertions(ROOT, client)
            }
        authority = results["no-duplicated-authority"]
        self.assertFalse(authority.passed)
        self.assertIn("approval-v1.json", authority.detail or "")


if __name__ == "__main__":
    unittest.main()
