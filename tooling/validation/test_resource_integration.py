from __future__ import annotations

import json
import unittest
from pathlib import Path

import yaml

from tooling.prototype.build_prototype import compose_prototype
from tooling.resources.validate_resources import validate_resource_artifacts


ROOT = Path(__file__).resolve().parents[2]


class ResourceIntegrationTests(unittest.TestCase):
    def test_reference_client_has_b1c_resource_artifacts(self):
        client = ROOT / "client-projects" / "examples" / "prototype-demo"
        required = [
            client / "derived" / "resource-requirements.yaml",
            client / "resources" / "candidates.yaml",
            client / "resources" / "selection.yaml",
            client / "resources" / "provenance.yaml",
        ]
        for path in required:
            self.assertTrue(path.exists(), f"missing B.1C reference artifact: {path}")

    def test_reference_client_preserves_authoritative_logo_and_comparative_hero(self):
        client = ROOT / "client-projects" / "examples" / "prototype-demo"
        requirements_path = client / "derived" / "resource-requirements.yaml"
        self.assertTrue(requirements_path.exists())
        data = yaml.safe_load(requirements_path.read_text(encoding="utf-8"))
        by_role = {item["role"]: item for item in data["resources"]}
        self.assertEqual("authoritative", by_role["brand.logo"]["sourcing"]["mode"])
        self.assertEqual("comparative", by_role["home.hero"]["sourcing"]["mode"])

    def test_reference_resource_artifacts_validate(self):
        client = ROOT / "client-projects" / "examples" / "prototype-demo"
        self.assertEqual([], validate_resource_artifacts(ROOT, client))

    def test_prototype_manifest_contains_canonical_resource_bindings(self):
        client = ROOT / "client-projects" / "examples" / "prototype-demo"
        manifest_path = compose_prototype(ROOT, client)
        manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
        resources = manifest.get("resources") or {}
        self.assertIn("asset.brand.logo", resources)
        self.assertIn("asset.home.hero", resources)
        self.assertIn("icon.commerce.cart", resources)
        self.assertEqual("pexels-fixture-1001", resources["asset.home.hero"]["candidate_id"])
        self.assertTrue(all(not key.startswith("http") for key in resources))

    def test_composition_generates_deterministic_flutter_runtime_bundle(self):
        client = ROOT / "client-projects" / "examples" / "prototype-demo"
        bundle_path = (
            ROOT / "apps" / "prototype_app" / "assets" / "generated" / "prototype-demo.json"
        )

        compose_prototype(ROOT, client)
        first = bundle_path.read_bytes()
        compose_prototype(ROOT, client)
        second = bundle_path.read_bytes()

        self.assertEqual(first, second)
        bundle = json.loads(first.decode("utf-8"))
        manifest = yaml.safe_load(
            (client / "prototype" / "prototype-manifest.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual("prototype-demo", bundle["client_id"])
        self.assertEqual("a", bundle["default_direction"])
        self.assertEqual(["a", "b", "c"], bundle["review"]["allowed_directions"])
        self.assertEqual(manifest["resources"], bundle["resources"])


if __name__ == "__main__":
    unittest.main()
