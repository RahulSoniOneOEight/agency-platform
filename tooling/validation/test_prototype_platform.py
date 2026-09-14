from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.prototype.fixture_generator import generate_fixture_pack
from tooling.prototype.screenshot_manifest import build_screenshot_manifest
from tooling.prototype.validate_direction import validate_direction
from tooling.prototype.validate_prototype import validate_prototype_platform
from tooling.prototype.validate_visual_qa import validate_visual_findings


class PrototypePlatformTests(unittest.TestCase):
    def test_direction_requires_strategic_structure(self):
        errors = validate_direction({"id": "a", "name": "A"})
        self.assertTrue(errors)
        self.assertTrue(any("strategic_goal" in e for e in errors))

    def test_direction_with_required_strategy_fields_validates(self):
        direction = {
            "id": "a",
            "name": "Trade Search",
            "strategic_goal": "reduce order time",
            "navigation": "search-led",
            "primary_journey": "search-to-order",
            "discovery_model": "sku-search",
            "merchandising": "availability-and-price",
            "density": "dense",
            "transaction_model": "checkout-plus-rfq",
            "patterns": ["search", "plp", "pdp", "rfq"],
            "components": ["product-card", "price-display", "quote-card"],
            "strengths": ["fast known-item ordering"],
            "tradeoffs": ["less editorial discovery"],
        }
        self.assertEqual([], validate_direction(direction))

    def test_fixture_generation_is_deterministic(self):
        one = generate_fixture_pack("electronics-appliances", seed=108)
        two = generate_fixture_pack("electronics-appliances", seed=108)
        self.assertEqual(one, two)
        self.assertGreaterEqual(len(one["products"]), 8)

    def test_supported_industry_fixture_packs(self):
        for industry in ("electronics-appliances", "furniture-home", "grocery-fmcg", "services-booking"):
            data = generate_fixture_pack(industry, seed=108)
            self.assertEqual(industry, data["industry"])
            self.assertTrue(data["products"] or data["services"])

    def test_screenshot_manifest_has_standard_viewports(self):
        manifest = build_screenshot_manifest("acme", ["a", "b", "c"])
        sizes = {(v["width"], v["height"]) for v in manifest["viewports"]}
        self.assertEqual({(360, 800), (390, 844), (430, 932), (768, 1024), (1440, 900)}, sizes)
        self.assertEqual(["a", "b", "c"], manifest["directions"])

    def test_visual_findings_contract(self):
        valid = {
            "client_id": "acme",
            "findings": [{
                "severity": "medium",
                "screen": "home",
                "direction": "a",
                "viewport": "390x844",
                "issue": "card spacing inconsistent",
                "status": "open",
            }],
        }
        self.assertEqual([], validate_visual_findings(valid))
        invalid = {"client_id": "acme", "findings": [{"screen": "home"}]}
        self.assertTrue(validate_visual_findings(invalid))

    def test_repository_prototype_contract_validates(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual([], validate_prototype_platform(root))


if __name__ == "__main__":
    unittest.main()
