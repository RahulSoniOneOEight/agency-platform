from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.prototype.approved_experience import validate_approved_experience
from tooling.prototype.build_prototype import compose_prototype
from tooling.prototype.fixture_generator import generate_fixture_pack
from tooling.prototype.screenshot_manifest import build_screenshot_manifest
from tooling.prototype.validate_direction import validate_direction
from tooling.prototype.validate_prototype import validate_prototype_platform
from tooling.prototype.validate_visual_qa import validate_visual_findings


def valid_direction(direction_id: str, navigation: str, journey: str) -> dict:
    return {
        "id": direction_id,
        "name": f"Direction {direction_id.upper()}",
        "strategic_goal": "improve conversion",
        "navigation": navigation,
        "primary_journey": journey,
        "discovery_model": "sku-search" if navigation == "search-led" else "guided",
        "merchandising": "availability-and-price",
        "density": "dense" if navigation == "search-led" else "balanced",
        "transaction_model": "checkout-plus-rfq",
        "patterns": ["home", "search", "plp", "pdp", "rfq"],
        "components": ["product-card", "price-display", "quote-card"],
        "strengths": ["clear primary task"],
        "tradeoffs": ["secondary discovery reduced"],
    }


class PrototypePlatformTests(unittest.TestCase):
    def test_direction_requires_strategic_structure(self):
        errors = validate_direction({"id": "a", "name": "A"})
        self.assertTrue(errors)
        self.assertTrue(any("strategic_goal" in e for e in errors))

    def test_direction_with_required_strategy_fields_validates(self):
        self.assertEqual([], validate_direction(valid_direction("a", "search-led", "search-to-order")))

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
                "severity": "medium", "screen": "home", "direction": "a",
                "viewport": "390x844", "issue": "card spacing inconsistent", "status": "open",
            }],
        }
        self.assertEqual([], validate_visual_findings(valid))
        invalid = {"client_id": "acme", "findings": [{"screen": "home"}]}
        self.assertTrue(validate_visual_findings(invalid))

    def test_composer_writes_shared_runtime_manifest_and_fixtures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            directions = client / "directions"
            directions.mkdir(parents=True)
            profile = {
                "id": "acme", "business_model": "b2b", "industry": "electronics-appliances",
                "use_cases": ["rfq"], "objectives": ["reduce-order-time"],
                "personas": ["trade-buyer"], "jobs": ["request-quote"], "platforms": ["web"],
            }
            (client / "client-profile.yaml").write_text(yaml.safe_dump(profile), encoding="utf-8")
            for direction_id, navigation, journey in (
                ("a", "search-led", "search-to-order"),
                ("b", "dashboard", "reorder-to-order"),
                ("c", "rfq-led", "rfq-to-quote"),
            ):
                (directions / f"direction-{direction_id}.yaml").write_text(
                    yaml.safe_dump(valid_direction(direction_id, navigation, journey)), encoding="utf-8"
                )
            (directions / "comparison.yaml").write_text("recommended: a\n", encoding="utf-8")
            manifest_path = compose_prototype(root, client)
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual("apps/prototype_app", manifest["runtime"])
            self.assertEqual(["a", "b", "c"], sorted(manifest["directions"].keys()))
            self.assertTrue((client / "prototype" / "fixtures" / "demo.yaml").exists())

    def test_approved_experience_accepts_direction_or_mix(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            directions = client / "directions"
            directions.mkdir(parents=True)
            for direction_id in ("a", "b", "c"):
                (directions / f"direction-{direction_id}.yaml").write_text(
                    yaml.safe_dump(valid_direction(direction_id, "search-led", "search-to-order")), encoding="utf-8"
                )
            approved = {
                "version": 1,
                "client_id": "acme",
                "selection": {"mode": "mixed", "base_direction": "a"},
                "sections": {"home": {"source_direction": "b"}, "search": {"source_direction": "a"}},
            }
            (client / "approved-experience.yaml").write_text(yaml.safe_dump(approved), encoding="utf-8")
            self.assertEqual([], validate_approved_experience(root, client))

    def test_repository_prototype_contract_validates(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual([], validate_prototype_platform(root))


if __name__ == "__main__":
    unittest.main()
