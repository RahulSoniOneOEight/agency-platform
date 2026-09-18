from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

from tooling.reference_client.fixture import (
    fixture_identity,
    load_fixture,
    validate_fixture,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
FIXTURE_PATH = CLIENT / "reference-e2e" / "fixture.yaml"
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "reference-client-fixture.schema.json"


def _write_fixture(client_dir: Path, fixture: dict) -> Path:
    e2e_dir = client_dir / "reference-e2e"
    e2e_dir.mkdir(parents=True, exist_ok=True)
    path = e2e_dir / "fixture.yaml"
    path.write_text(yaml.safe_dump(fixture, sort_keys=False), encoding="utf-8")
    return path


class ReferenceFixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = load_fixture(FIXTURE_PATH)

    def test_load_fixture_identity_fields(self):
        self.assertEqual("reference-commerce", self.fixture["client_id"])
        self.assertEqual(1, self.fixture["fixture_version"])
        self.assertEqual("reference-commerce-v1", self.fixture["seed"])
        self.assertIs(True, self.fixture["synthetic"])

    def test_load_fixture_rejects_non_mapping(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture.yaml"
            path.write_text("- not\n- a\n- mapping\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_fixture(path)

    def test_load_fixture_rejects_missing_client_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture.yaml"
            path.write_text("fixture_version: 1\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_fixture(path)

    def test_load_fixture_rejects_missing_fixture_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fixture.yaml"
            path.write_text("client_id: reference-commerce\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_fixture(path)

    def test_repository_fixture_is_valid(self):
        self.assertEqual([], validate_fixture(ROOT, CLIENT))

    def test_coverage_and_minimum_counts(self):
        coverage = self.fixture["coverage"]
        self.assertIs(True, coverage["b2c"])
        self.assertIs(True, coverage["b2b"])
        self.assertGreaterEqual(len(self.fixture["products"]), 12)
        self.assertGreaterEqual(len(self.fixture["accounts"]), 4)
        self.assertGreaterEqual(len(self.fixture["quotations"]), 2)
        self.assertGreaterEqual(len(self.fixture["rfqs"]), 2)

    def test_trade_accounts_carry_credit(self):
        trade = [a for a in self.fixture["accounts"] if a.get("type") == "trade"]
        self.assertGreaterEqual(len(trade), 2)
        with_credit = [
            a
            for a in trade
            if "credit_limit" in a and "available_credit" in a
        ]
        self.assertGreaterEqual(len(with_credit), 2)

    def test_product_references_resolve(self):
        category_ids = {c["id"] for c in self.fixture["categories"]}
        variant_ids = {v["id"] for v in self.fixture["variants"]}
        for product in self.fixture["products"]:
            self.assertIn(product["category"], category_ids, product["id"])
            for variant_id in product["variant_ids"]:
                self.assertIn(variant_id, variant_ids, product["id"])

    def test_duplicate_entity_ids_are_rejected(self):
        fixture = copy.deepcopy(self.fixture)
        fixture["products"].append(copy.deepcopy(fixture["products"][0]))
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(Path(tmp), fixture)
            errors = validate_fixture(ROOT, Path(tmp))
        self.assertTrue(any("duplicate" in error for error in errors), errors)

    def test_invalid_credit_is_rejected(self):
        fixture = copy.deepcopy(self.fixture)
        trade = next(a for a in fixture["accounts"] if a.get("type") == "trade")
        trade["available_credit"] = trade["credit_limit"] + 1
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(Path(tmp), fixture)
            errors = validate_fixture(ROOT, Path(tmp))
        self.assertTrue(any("credit" in error for error in errors), errors)

    def test_negative_credit_is_rejected(self):
        fixture = copy.deepcopy(self.fixture)
        trade = next(a for a in fixture["accounts"] if a.get("type") == "trade")
        trade["available_credit"] = -1
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(Path(tmp), fixture)
            errors = validate_fixture(ROOT, Path(tmp))
        self.assertTrue(any("credit" in error for error in errors), errors)

    def test_unknown_fixture_version_is_rejected(self):
        fixture = copy.deepcopy(self.fixture)
        fixture["fixture_version"] = 2
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(Path(tmp), fixture)
            errors = validate_fixture(ROOT, Path(tmp))
        self.assertTrue(any("fixture_version" in error for error in errors), errors)

    def test_missing_required_entity_is_rejected(self):
        fixture = copy.deepcopy(self.fixture)
        del fixture["quotations"]
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(Path(tmp), fixture)
            errors = validate_fixture(ROOT, Path(tmp))
        self.assertTrue(any("quotations" in error for error in errors), errors)

    def test_fixture_identity_is_stable_and_content_sensitive(self):
        first = fixture_identity(load_fixture(FIXTURE_PATH))
        second = fixture_identity(load_fixture(FIXTURE_PATH))
        self.assertEqual(first, second)
        self.assertTrue(first.startswith("sha256:"))

        changed = copy.deepcopy(self.fixture)
        changed["products"][0]["retail_price"] = changed["products"][0]["retail_price"] + 1
        self.assertNotEqual(first, fixture_identity(changed))

    def test_json_schema_accepts_real_fixture(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        errors = list(Draft202012Validator(schema).iter_errors(self.fixture))
        self.assertEqual([], errors)

    def test_json_schema_rejects_unknown_top_level_key(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        fixture = copy.deepcopy(self.fixture)
        fixture["unexpected_top_level_key"] = True
        errors = list(Draft202012Validator(schema).iter_errors(fixture))
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
