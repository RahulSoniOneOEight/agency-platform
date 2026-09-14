from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.workflow.client_paths import ClientPaths
from tooling.workflow.initialize_client import initialize_client
from tooling.workflow.router import next_stage
from tooling.workflow.state import initial_state


PROFILE = {
    "id": "acme",
    "business_model": "b2b",
    "industry": "electronics-appliances",
    "use_cases": ["rfq"],
    "objectives": ["reduce-order-time"],
    "personas": ["trade-buyer"],
    "jobs": ["request-quote"],
    "platforms": ["web"],
}


class ClientInformationArchitectureTests(unittest.TestCase):
    def test_initializer_creates_canonical_input_and_derived_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            client = initialize_client(root, "acme", "Acme Electronics")
            expected = {
                "brief.md",
                "workflow-state.yaml",
                "input/client-input.yaml",
                "input/brand/.gitkeep",
                "input/references/.gitkeep",
                "input/assets/.gitkeep",
                "input/source-documents/.gitkeep",
                "derived/client-profile.yaml",
                "derived/resolved-presets.yaml",
                "derived/intelligence-map.yaml",
                "derived/capability-map.yaml",
                "derived/gaps.yaml",
                "derived/resource-requirements.yaml",
                "resources/.gitkeep",
                "directions/.gitkeep",
            }
            actual = {
                str(path.relative_to(client)).replace("\\", "/")
                for path in client.rglob("*")
                if path.is_file()
            }
            self.assertEqual(expected, actual)
            self.assertFalse((client / "client-profile.yaml").exists())
            self.assertFalse((client / "resolved-intelligence.yaml").exists())

    def test_client_paths_exposes_canonical_paths(self):
        client = Path("client-projects/acme")
        paths = ClientPaths.for_client(client)
        self.assertEqual(client / "input" / "client-input.yaml", paths.client_input)
        self.assertEqual(client / "derived" / "client-profile.yaml", paths.client_profile)
        self.assertEqual(client / "derived" / "resolved-presets.yaml", paths.resolved_presets)
        self.assertEqual(client / "derived" / "capability-map.yaml", paths.capability_map)
        self.assertEqual(client / "derived" / "resource-requirements.yaml", paths.resource_requirements)

    def test_client_paths_can_read_legacy_profile_during_migration(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            client.mkdir()
            legacy = client / "client-profile.yaml"
            legacy.write_text("id: acme\n", encoding="utf-8")
            paths = ClientPaths.for_client(client)
            self.assertEqual(legacy, paths.read_client_profile())

    def test_completed_intake_requires_canonical_input_and_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            client.mkdir(parents=True)
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("client-input-missing", result["reason"])

    def test_completed_resolve_intelligence_requires_explicit_derived_maps(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            paths = ClientPaths.for_client(client)
            paths.client_input.parent.mkdir(parents=True)
            paths.client_input.write_text("client_id: acme\n", encoding="utf-8")
            paths.client_profile.parent.mkdir(parents=True)
            paths.client_profile.write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence"]
            result = next_stage(root, client, state)
            self.assertEqual("resolve-intelligence", result["stage"])
            self.assertEqual("derived-intelligence-incomplete", result["reason"])

    def test_completed_resource_research_requires_resource_requirements_and_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            paths = ClientPaths.for_client(client)
            paths.client_input.parent.mkdir(parents=True)
            paths.client_input.write_text("client_id: acme\n", encoding="utf-8")
            paths.client_profile.parent.mkdir(parents=True)
            paths.client_profile.write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
            for path, content in (
                (paths.resolved_presets, "business_model: b2b\nindustry: electronics-appliances\nuse_cases: [rfq]\n"),
                (paths.intelligence_map, "components: []\npatterns: []\njourneys: []\n"),
                (paths.capability_map, "capabilities: []\n"),
                (paths.gaps, "gaps: []\n"),
            ):
                path.write_text(content, encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "resource-research"]
            result = next_stage(root, client, state)
            self.assertEqual("resource-research", result["stage"])
            self.assertEqual("resource-requirements-missing", result["reason"])


if __name__ == "__main__":
    unittest.main()
