from __future__ import annotations

import importlib
import json
import tempfile
import unittest
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[2]


class ResourceDirectionOverrideTests(unittest.TestCase):
    def test_selection_schema_accepts_direction_specific_overrides(self):
        schema = json.loads(
            (ROOT / "resources" / "registry" / "schema" / "resource-selection.schema.json").read_text(
                encoding="utf-8"
            )
        )
        payload = {
            "version": 1,
            "selections": {"home-hero": {"primary": "client-hero"}},
            "direction_overrides": {
                "b": {"home-hero": {"primary": "pexels-42", "fallback": "client-hero"}}
            },
        }
        self.assertEqual([], list(Draft202012Validator(schema).iter_errors(payload)))

    def test_normalizer_emits_direction_specific_canonical_bindings(self):
        normalizer = importlib.import_module("tooling.resources.normalizer")
        selection = {
            "version": 1,
            "selections": {"home-hero": {"primary": "client-hero"}},
            "direction_overrides": {"b": {"home-hero": {"primary": "pexels-42"}}},
        }
        candidates = {
            "version": 1,
            "candidates": {
                "home-hero": [
                    {
                        "id": "client-hero",
                        "source": "client",
                        "type": "image",
                        "role": "home.hero",
                        "asset": {"path": "input/assets/banners/hero.jpg"},
                    },
                    {
                        "id": "pexels-42",
                        "source": "pexels",
                        "type": "image",
                        "role": "home.hero",
                        "asset": {"url": "https://images.pexels.com/photos/42/large.jpeg"},
                    },
                ]
            },
        }
        bindings = normalizer.normalize_bindings(selection, candidates)
        self.assertEqual("client-hero", bindings["asset.home.hero"]["candidate_id"])
        self.assertEqual(
            "pexels-42",
            bindings["direction_overrides"]["b"]["asset.home.hero"]["candidate_id"],
        )

    def test_validator_rejects_default_canonical_id_collisions(self):
        validator = importlib.import_module("tooling.resources.validate_resources")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            schema_dir = root / "resources" / "registry" / "schema"
            schema_dir.mkdir(parents=True)
            for name in (
                "resource-requirements.schema.json",
                "resource-candidates.schema.json",
                "resource-selection.schema.json",
                "resource-provenance.schema.json",
            ):
                (schema_dir / name).write_text(
                    (ROOT / "resources" / "registry" / "schema" / name).read_text(encoding="utf-8"),
                    encoding="utf-8",
                )

            client = root / "client-projects" / "acme"
            (client / "derived").mkdir(parents=True)
            (client / "resources").mkdir(parents=True)
            requirements = {
                "version": 1,
                "resources": [
                    {
                        "id": "hero-a",
                        "type": "image",
                        "role": "home.hero",
                        "impact": "high",
                        "sourcing": {"mode": "authoritative", "allowed_sources": ["client"]},
                    },
                    {
                        "id": "hero-b",
                        "type": "image",
                        "role": "home.hero",
                        "impact": "high",
                        "sourcing": {"mode": "authoritative", "allowed_sources": ["client"]},
                    },
                ],
            }
            candidates = {
                "version": 1,
                "candidates": {
                    "hero-a": [{"id": "client-a", "source": "client", "type": "image", "role": "home.hero"}],
                    "hero-b": [{"id": "client-b", "source": "client", "type": "image", "role": "home.hero"}],
                },
            }
            selection = {
                "version": 1,
                "selections": {
                    "hero-a": {"primary": "client-a"},
                    "hero-b": {"primary": "client-b"},
                },
            }
            provenance = {"version": 1, "resources": {}}
            (client / "derived" / "resource-requirements.yaml").write_text(
                yaml.safe_dump(requirements), encoding="utf-8"
            )
            (client / "resources" / "candidates.yaml").write_text(
                yaml.safe_dump(candidates), encoding="utf-8"
            )
            (client / "resources" / "selection.yaml").write_text(
                yaml.safe_dump(selection), encoding="utf-8"
            )
            (client / "resources" / "provenance.yaml").write_text(
                yaml.safe_dump(provenance), encoding="utf-8"
            )
            errors = validator.validate_resource_artifacts(root, client)
            self.assertTrue(any("canonical resource id collision" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
