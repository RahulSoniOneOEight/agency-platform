from __future__ import annotations

import unittest
from pathlib import Path

from tooling.knowledge.direction_engine import generate_directions
from tooling.knowledge.index_design_contract import build_indexes
from tooling.knowledge.preset_resolver import resolve_presets
from tooling.knowledge.validate_knowledge import validate_all


ROOT = Path(__file__).resolve().parents[2]


class KnowledgePlatformContractTests(unittest.TestCase):
    def test_knowledge_platform_validates(self):
        errors = validate_all(ROOT)
        self.assertEqual([], errors)

    def test_design_contract_indexes_are_deterministic(self):
        first = build_indexes(ROOT)
        second = build_indexes(ROOT)
        self.assertEqual(first, second)
        self.assertIn("commerce.product-card", first["components"])
        self.assertIn("commerce.plp", first["patterns"])
        self.assertIn("commerce.standard-purchase", first["journeys"])

    def test_b2b_electronics_preset_resolution(self):
        resolved = resolve_presets(
            ROOT,
            business_model="b2b",
            industry="electronics-appliances",
            use_cases=["bulk-procurement", "rfq"],
        )
        self.assertEqual(
            ["b2b", "electronics-appliances", "bulk-procurement", "rfq"],
            resolved["active_presets"],
        )
        self.assertIn("search-sku-first", resolved["candidate_archetypes"])
        self.assertIn("rfq-first", resolved["candidate_archetypes"])

    def test_direction_engine_returns_three_distinct_strategies(self):
        client = {
            "id": "fixture-b2b-electronics",
            "business_model": "b2b",
            "industry": "electronics-appliances",
            "use_cases": ["bulk-procurement", "rfq", "repeat-order"],
            "objectives": ["reduce-time-to-order", "increase-repeat-purchase", "grow-rfq"],
            "personas": ["procurement-manager", "trade-buyer"],
            "jobs": ["find-exact-product", "reorder", "request-quote"],
            "platforms": ["mobile", "web"],
        }
        result = generate_directions(ROOT, client, limit=3)
        self.assertEqual(3, len(result["directions"]))
        ids = [item["archetype"] for item in result["directions"]]
        self.assertEqual(3, len(set(ids)))
        families = [item["strategy_family"] for item in result["directions"]]
        self.assertEqual(3, len(set(families)))
        for item in result["directions"]:
            self.assertIn("rationale", item)
            self.assertIn("score", item)
            self.assertIn("primary_journey", item)


if __name__ == "__main__":
    unittest.main()
