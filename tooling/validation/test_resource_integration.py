from __future__ import annotations

import unittest
from pathlib import Path

import yaml


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


if __name__ == "__main__":
    unittest.main()
