from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.prototype.approved_experience import validate_approved_experience
from tooling.prototype.build_prototype import compose_prototype
from tooling.prototype.fixture_generator import generate_fixture_pack
from tooling.prototype.project_direction import project_direction, validate_runtime_direction
from tooling.prototype.screenshot_manifest import build_screenshot_manifest
from tooling.prototype.validate_direction import validate_direction
from tooling.prototype.validate_prototype import validate_prototype_platform
from tooling.prototype.validate_visual_qa import validate_visual_findings


def valid_strategic_direction(direction_id: str) -> dict:
    return {
        "id": direction_id,
        "name": f"Direction {direction_id.upper()}",
        "archetype": "search-first",
        "strategy_family": "search",
        "thesis": "Reduce time from intent to transaction.",
        "strategic_goal": "reduce-order-time",
        "primary_personas": ["trade-buyer"],
        "primary_jobs": ["find-and-order-known-sku"],
        "rationale": "Known-SKU buyers benefit from direct search and dense decision support.",
        "information_architecture": ["home", "search", "plp", "pdp", "cart"],
        "navigation": {"model": "search-led"},
        "primary_journey": {"id": "search-to-order", "steps": ["search", "pdp", "cart", "checkout"]},
        "secondary_journeys": [{"id": "browse-to-order", "steps": ["home", "plp", "pdp", "cart"]}],
        "discovery_model": "sku-search",
        "search": {"prominence": "high"},
        "merchandising": {"emphasis": "availability-and-price"},
        "density": "compact",
        "transaction_model": "checkout-plus-rfq",
        "patterns": ["commerce.home", "commerce.search", "commerce.pdp"],
        "components": ["commerce.product-card", "commerce.price-display"],
        "component_variants": [{"component": "commerce.product-card", "variant": "b2b"}],
        "required_resources": [],
        "strengths": ["fast known-SKU ordering"],
        "tradeoffs": ["less editorial discovery"],
        "risks": ["depends on catalog data quality"],
        "success_metrics": ["time-to-cart"],
        "score": 0.9,
    }


def _write_client(root: Path, direction_ids: list[str]) -> Path:
    client = root / "client-projects" / "acme"
    directions = client / "directions"
    directions.mkdir(parents=True)
    profile = {
        "id": "acme", "business_model": "b2b", "industry": "electronics-appliances",
        "use_cases": ["rfq"], "objectives": ["reduce-order-time"],
        "personas": ["trade-buyer"], "jobs": ["request-quote"], "platforms": ["web"],
    }
    (client / "derived").mkdir(parents=True)
    (client / "derived" / "client-profile.yaml").write_text(yaml.safe_dump(profile), encoding="utf-8")
    for direction_id in direction_ids:
        (directions / f"direction-{direction_id}.yaml").write_text(
            yaml.safe_dump(valid_strategic_direction(direction_id)), encoding="utf-8"
        )
    (directions / "comparison.yaml").write_text("recommended: a\n", encoding="utf-8")
    return client


class PrototypePlatformTests(unittest.TestCase):
    def test_strategic_direction_requires_canonical_fields(self):
        errors = validate_direction({"id": "a", "name": "A"})
        self.assertTrue(any("strategic_goal" in error for error in errors))
        self.assertTrue(any("primary_journey" in error for error in errors))

    def test_strategic_direction_rejects_runtime_density_vocabulary(self):
        direction = valid_strategic_direction("a")
        direction["density"] = "balanced"
        errors = validate_direction(direction)
        self.assertTrue(any("density" in error for error in errors))

    def test_canonical_strategic_direction_validates(self):
        self.assertEqual([], validate_direction(valid_strategic_direction("a")))

    def test_direction_projection_is_deterministic(self):
        strategic = valid_strategic_direction("a")
        self.assertEqual(project_direction(strategic), project_direction(strategic))

    def test_direction_projection_preserves_canonical_ids(self):
        runtime = project_direction(valid_strategic_direction("a"))
        self.assertEqual(["commerce.home", "commerce.search", "commerce.pdp"], runtime["patterns"])
        self.assertEqual(["commerce.product-card", "commerce.price-display"], runtime["components"])
        self.assertEqual("compact", runtime["density"])

    def test_direction_projection_maps_structured_fields(self):
        runtime = project_direction(valid_strategic_direction("a"))
        self.assertEqual("search-led", runtime["navigation_model"])
        self.assertEqual("search-to-order", runtime["primary_journey"])
        self.assertEqual("availability-and-price", runtime["merchandising_model"])

    def test_direction_projection_rejects_invalid_strategic_input(self):
        strategic = valid_strategic_direction("a")
        del strategic["navigation"]["model"]
        with self.assertRaisesRegex(ValueError, "navigation"):
            project_direction(strategic)

    def test_runtime_direction_validates_against_runtime_contract(self):
        runtime = project_direction(valid_strategic_direction("a"))
        self.assertEqual([], validate_runtime_direction(runtime))
        missing_field = dict(runtime)
        del missing_field["navigation_model"]
        self.assertTrue(any("navigation_model" in e for e in validate_runtime_direction(missing_field)))
        bad_density = dict(runtime)
        bad_density["density"] = "dense"
        self.assertTrue(any("density" in e for e in validate_runtime_direction(bad_density)))

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
            client = _write_client(root, ["a", "b", "c"])
            manifest_path = compose_prototype(root, client)
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual("apps/prototype_app", manifest["runtime"])
            self.assertEqual(["a", "b", "c"], sorted(manifest["directions"].keys()))
            self.assertTrue((client / "prototype" / "fixtures" / "demo.yaml").exists())

    def test_composer_supports_two_directions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            manifest_path = compose_prototype(root, client)
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(["a", "b"], list(manifest["directions"].keys()))
            self.assertEqual(["a", "b"], manifest["review"]["allowed_values"])
            self.assertTrue((client / "prototype" / "runtime" / "direction-a.json").exists())
            self.assertTrue((client / "prototype" / "runtime" / "direction-b.json").exists())
            self.assertFalse((client / "prototype" / "runtime" / "direction-c.json").exists())

    def test_composer_supports_three_directions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b", "c"])
            manifest_path = compose_prototype(root, client)
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(["a", "b", "c"], list(manifest["directions"].keys()))
            self.assertEqual(["a", "b", "c"], manifest["review"]["allowed_values"])
            self.assertTrue((client / "prototype" / "runtime" / "direction-c.json").exists())

    def test_composer_rejects_single_direction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a"])
            with self.assertRaisesRegex(ValueError, "at least directions a and b"):
                compose_prototype(root, client)

    def test_composer_rejects_more_than_three_directions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b", "c", "d"])
            with self.assertRaisesRegex(ValueError, "at most 3 directions"):
                compose_prototype(root, client)

    def test_composer_rejects_root_only_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            directions = client / "directions"
            directions.mkdir(parents=True)
            (client / "client-profile.yaml").write_text(
                yaml.safe_dump({"id": "acme", "industry": "electronics-appliances"}), encoding="utf-8"
            )
            for direction_id in ("a", "b"):
                (directions / f"direction-{direction_id}.yaml").write_text(
                    yaml.safe_dump(valid_strategic_direction(direction_id)), encoding="utf-8"
                )
            (directions / "comparison.yaml").write_text("recommended: a\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "derived/client-profile.yaml"):
                compose_prototype(root, client)

    def test_recomposition_removes_stale_runtime_directions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b", "c"])
            compose_prototype(root, client)
            self.assertTrue((client / "prototype" / "runtime" / "direction-c.json").exists())
            (client / "directions" / "direction-c.yaml").unlink()
            compose_prototype(root, client)
            self.assertFalse((client / "prototype" / "runtime" / "direction-c.json").exists())

    def test_approved_experience_accepts_direction_or_mix(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            directions = client / "directions"
            directions.mkdir(parents=True)
            for direction_id in ("a", "b", "c"):
                (directions / f"direction-{direction_id}.yaml").write_text(
                    yaml.safe_dump(valid_strategic_direction(direction_id)), encoding="utf-8"
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

    def test_reference_example_directions_are_canonical(self):
        root = Path(__file__).resolve().parents[2]
        directions = root / "client-projects" / "examples" / "prototype-demo" / "directions"
        for direction_id in ("a", "b", "c"):
            data = yaml.safe_load((directions / f"direction-{direction_id}.yaml").read_text(encoding="utf-8"))
            self.assertEqual([], validate_direction(data), direction_id)

    def test_validation_detects_missing_runtime_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            compose_prototype(root, client)
            (client / "prototype" / "runtime" / "direction-b.json").unlink()
            errors = validate_prototype_platform(root)
            self.assertTrue(any("runtime" in error and "direction-b" in error for error in errors))

    def test_validation_detects_runtime_id_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            compose_prototype(root, client)
            runtime_b = client / "prototype" / "runtime" / "direction-b.json"
            data = json.loads(runtime_b.read_text(encoding="utf-8"))
            data["id"] = "c"
            runtime_b.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            errors = validate_prototype_platform(root)
            self.assertTrue(any("expected 'b'" in error for error in errors))

    def test_validation_detects_allowed_values_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            manifest_path = compose_prototype(root, client)
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            manifest["review"]["allowed_values"] = ["a"]
            manifest_path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
            errors = validate_prototype_platform(root)
            self.assertTrue(any("allowed_values" in error for error in errors))

    def test_validation_reports_non_object_runtime_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            compose_prototype(root, client)
            (client / "prototype" / "runtime" / "direction-b.json").write_text("[]", encoding="utf-8")
            errors = validate_prototype_platform(root)
            self.assertTrue(any("direction-b" in error for error in errors))

    def test_validation_reports_non_string_runtime_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            manifest_path = compose_prototype(root, client)
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            manifest["directions"]["b"] = None
            manifest_path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
            errors = validate_prototype_platform(root)
            self.assertTrue(any("direction b" in error or "must be a string" in error for error in errors))

    def test_validation_reports_unhashable_screenshot_directions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            compose_prototype(root, client)
            screenshot_path = client / "prototype" / "qa" / "screenshot-manifest.yaml"
            screenshot = yaml.safe_load(screenshot_path.read_text(encoding="utf-8"))
            screenshot["directions"] = [{"direction": "a"}]
            screenshot_path.write_text(yaml.safe_dump(screenshot, sort_keys=False), encoding="utf-8")
            errors = validate_prototype_platform(root)
            self.assertTrue(any("screenshot manifest directions" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
