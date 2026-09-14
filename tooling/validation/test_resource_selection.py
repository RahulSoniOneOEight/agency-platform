from __future__ import annotations

import importlib
import json
import os
import tempfile
import unittest
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[2]


class ResourceSelectionTests(unittest.TestCase):
    def _load_schema(self, name: str) -> dict:
        path = ROOT / "resources" / "registry" / "schema" / name
        self.assertTrue(path.exists(), f"missing B.1C schema: {path}")
        return json.loads(path.read_text(encoding="utf-8"))

    def test_sourcing_policy_defines_four_modes_and_high_impact_defaults(self):
        path = ROOT / "resources" / "policies" / "sourcing-policy.yaml"
        self.assertTrue(path.exists(), "missing sourcing-policy.yaml")
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        self.assertEqual(
            {"authoritative", "prefer_client", "comparative", "discovery"},
            set(data["modes"]),
        )
        self.assertEqual("comparative", data["role_defaults"]["home.hero"])
        self.assertEqual("authoritative", data["role_defaults"]["brand.logo"])

    def test_resource_requirement_schema_rejects_invalid_mode(self):
        schema = self._load_schema("resource-requirements.schema.json")
        valid = {
            "version": 1,
            "resources": [{
                "id": "home-hero",
                "type": "image",
                "role": "home.hero",
                "impact": "critical",
                "sourcing": {"mode": "comparative", "allowed_sources": ["client", "agency", "pexels"]},
                "requirements": {"subject": "premium electronics", "aspect_ratio": "16:9"},
            }],
        }
        self.assertEqual([], list(Draft202012Validator(schema).iter_errors(valid)))
        invalid = json.loads(json.dumps(valid))
        invalid["resources"][0]["sourcing"]["mode"] = "client-first-stop"
        self.assertTrue(list(Draft202012Validator(schema).iter_errors(invalid)))

    def test_router_keeps_comparative_research_even_with_client_candidate(self):
        module_path = ROOT / "tooling" / "resources" / "provider_router.py"
        self.assertTrue(module_path.exists(), "missing provider_router.py")
        router = importlib.import_module("tooling.resources.provider_router")
        requirement = {
            "type": "image",
            "role": "home.hero",
            "sourcing": {"mode": "comparative", "allowed_sources": ["client", "agency", "pexels"]},
        }
        self.assertEqual(
            ["client", "agency", "pexels"],
            router.route_sources(requirement, client_candidates_exist=True),
        )

    def test_router_keeps_authoritative_assets_off_stock_providers(self):
        router = importlib.import_module("tooling.resources.provider_router")
        requirement = {
            "type": "image",
            "role": "brand.logo",
            "sourcing": {"mode": "authoritative", "allowed_sources": ["client", "official", "pexels"]},
        }
        self.assertEqual(["client", "official"], router.route_sources(requirement, client_candidates_exist=True))

    def test_pexels_adapter_uses_injected_transport_and_normalizes_results(self):
        pexels = importlib.import_module("tooling.resources.pexels_client")
        seen = {}

        def transport(url: str, headers: dict[str, str]) -> dict:
            seen["url"] = url
            seen["headers"] = headers
            return {
                "photos": [{
                    "id": 42,
                    "width": 2400,
                    "height": 1350,
                    "photographer": "Example",
                    "url": "https://www.pexels.com/photo/example-42/",
                    "src": {"large": "https://images.pexels.com/photos/42/large.jpeg"},
                }]
            }

        requirement = {
            "id": "home-hero",
            "type": "image",
            "role": "home.hero",
            "requirements": {"subject": "premium electronics retail", "orientation": "landscape"},
        }
        results = pexels.search_pexels(requirement, api_key="secret-for-test", transport=transport)
        self.assertEqual("pexels-42", results[0]["id"])
        self.assertEqual("pexels", results[0]["source"])
        self.assertEqual("home.hero", results[0]["role"])
        self.assertEqual("secret-for-test", seen["headers"]["Authorization"])
        self.assertIn("premium+electronics+retail", seen["url"])

    def test_pexels_missing_key_does_not_raise_or_call_transport(self):
        pexels = importlib.import_module("tooling.resources.pexels_client")
        called = False

        def transport(url: str, headers: dict[str, str]) -> dict:
            nonlocal called
            called = True
            return {}

        old = os.environ.pop("PEXELS_API_KEY", None)
        try:
            results = pexels.search_pexels(
                {"id": "hero", "type": "image", "role": "home.hero", "requirements": {"subject": "retail"}},
                api_key=None,
                transport=transport,
            )
        finally:
            if old is not None:
                os.environ["PEXELS_API_KEY"] = old
        self.assertEqual([], results)
        self.assertFalse(called)

    def test_semantic_icon_and_motion_resolvers(self):
        icons = importlib.import_module("tooling.resources.icon_resolver")
        motion = importlib.import_module("tooling.resources.motion_resolver")
        icon = icons.resolve_icon(ROOT, "icon.commerce.cart")
        self.assertIn(icon["provider"], {"iconoir", "lucide"})
        self.assertTrue(icon["name"])
        animation = motion.resolve_motion(ROOT, "motion.checkout.success")
        self.assertEqual("lottie", animation["type"])
        self.assertFalse(animation["loop"])

    def test_comparative_selection_can_choose_better_external_candidate(self):
        selector = importlib.import_module("tooling.resources.selector")
        requirements = {
            "version": 1,
            "resources": [{
                "id": "home-hero",
                "type": "image",
                "role": "home.hero",
                "impact": "critical",
                "sourcing": {"mode": "comparative", "allowed_sources": ["client", "pexels"]},
            }],
        }
        candidates = {
            "version": 1,
            "candidates": {
                "home-hero": [
                    {"id": "client-hero", "source": "client", "type": "image", "role": "home.hero", "scores": {"direction_fit": .75, "relevance": .8, "composition": .7, "brand_fit": .9, "technical_quality": .8, "provenance": 1.0, "consistency": .8}},
                    {"id": "pexels-42", "source": "pexels", "type": "image", "role": "home.hero", "scores": {"direction_fit": .95, "relevance": .95, "composition": .95, "brand_fit": .9, "technical_quality": .95, "provenance": 1.0, "consistency": .9}},
                ]
            },
        }
        selected = selector.select_candidates(requirements, candidates)
        self.assertEqual("pexels-42", selected["selections"]["home-hero"]["primary"])
        self.assertEqual("client-hero", selected["selections"]["home-hero"]["fallback"])

    def test_authoritative_selection_rejects_stock_candidate(self):
        selector = importlib.import_module("tooling.resources.selector")
        requirements = {"version": 1, "resources": [{
            "id": "brand-logo", "type": "image", "role": "brand.logo", "impact": "critical",
            "sourcing": {"mode": "authoritative", "allowed_sources": ["client", "official"]},
        }]}
        candidates = {"version": 1, "candidates": {"brand-logo": [
            {"id": "pexels-logo", "source": "pexels", "type": "image", "role": "brand.logo", "scores": {"direction_fit": 1, "relevance": 1, "composition": 1, "brand_fit": 1, "technical_quality": 1, "provenance": 1, "consistency": 1}},
        ]}}
        selected = selector.select_candidates(requirements, candidates)
        self.assertNotIn("brand-logo", selected["selections"])

    def test_normalizer_emits_canonical_semantic_ids(self):
        normalizer = importlib.import_module("tooling.resources.normalizer")
        selection = {"version": 1, "selections": {"home-hero": {"primary": "pexels-42"}}}
        candidates = {"version": 1, "candidates": {"home-hero": [{
            "id": "pexels-42", "source": "pexels", "type": "image", "role": "home.hero",
            "asset": {"url": "https://images.pexels.com/photos/42/large.jpeg"},
        }]}}
        bindings = normalizer.normalize_bindings(selection, candidates)
        self.assertIn("asset.home.hero", bindings)
        self.assertEqual("pexels-42", bindings["asset.home.hero"]["candidate_id"])


if __name__ == "__main__":
    unittest.main()
