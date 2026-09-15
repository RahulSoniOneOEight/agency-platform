from __future__ import annotations

import json
import tempfile
import unittest
from datetime import date
from pathlib import Path

import yaml

from tooling.knowledge.index_design_contract import build_indexes
from tooling.prototype.build_runtime_bundle import build_runtime_bundle
from tooling.prototype.validate_runtime_bundle import validate_runtime_bundle


ROOT = Path(__file__).resolve().parents[2]


def _direction(direction_id: str, *, density: str = "compact") -> dict:
    return {
        "id": direction_id,
        "name": f"Direction {direction_id.upper()}",
        "strategic_goal": "reduce known-item order time",
        "navigation_model": "search-led",
        "primary_journey": "search-to-order",
        "discovery_model": "sku-search",
        "merchandising_model": "availability-and-price",
        "density": density,
        "transaction_model": "checkout-plus-rfq",
        "patterns": ["commerce.search", "commerce.pdp"],
        "components": ["commerce.product-card"],
        "component_variants": [
            {"component": "commerce.product-card", "variant": "b2b"}
        ],
        "required_resources": ["asset.home.hero"],
    }


def _fixtures() -> dict:
    return {
        "industry": "electronics-appliances",
        "seed": 108,
        "products": [
            {
                "id": "prd-01",
                "sku": "SKU-ELE-1000",
                "name": "USB-C Hub",
                "price": 674,
                "compare_at": 674,
                "rating": 4.1,
                "stock": 18,
                "category": "category-1",
            }
        ],
        "services": [],
    }


def _resource_binding(candidate_id: str = "hero") -> dict:
    return {
        "candidate_id": candidate_id,
        "source": "client",
        "type": "image",
        "asset": {},
    }


def _bundle(direction_ids: tuple[str, ...] = ("a", "b")) -> dict:
    directions = {direction_id: _direction(direction_id) for direction_id in direction_ids}
    return {
        "version": 1,
        "client_id": "acme-client",
        "default_direction": "a",
        "directions": directions,
        "fixtures": _fixtures(),
        "theme": {"seed_color": "#6750A4"},
        "resources": {"asset.home.hero": _resource_binding()},
        "review": {
            "query_parameter": "direction",
            "allowed_directions": list(direction_ids),
        },
    }


def _write_client(client_dir: Path, direction_ids: tuple[str, ...] = ("a", "b")) -> None:
    runtime_dir = client_dir / "prototype" / "runtime"
    fixture_dir = client_dir / "prototype" / "fixtures"
    runtime_dir.mkdir(parents=True)
    fixture_dir.mkdir(parents=True)

    direction_paths = {}
    for direction_id in direction_ids:
        relative_path = f"prototype/runtime/direction-{direction_id}.json"
        (client_dir / relative_path).write_text(
            json.dumps(_direction(direction_id), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        direction_paths[direction_id] = relative_path

    (fixture_dir / "demo.yaml").write_text(
        yaml.safe_dump(_fixtures(), sort_keys=False), encoding="utf-8"
    )
    manifest = {
        "version": 1,
        "client_id": "acme-client",
        "runtime": "apps/prototype_app",
        "default_direction": "a",
        "directions": direction_paths,
        "fixture_pack": "prototype/fixtures/demo.yaml",
        "theme": {"seed_color": "#6750A4"},
        "resources": {
            "asset.home.hero": {
                "candidate_id": "pexels-42",
                "source": "pexels",
                "type": "image",
                "asset": {
                    "url": "https://images.pexels.com/photos/42/large.jpeg",
                    "width": 2400,
                    "provider_metadata": {"photographer": "Example"},
                },
                "provider_extension": {"license": "Pexels"},
            },
            "direction_overrides": {
                "b": {
                    "asset.home.hero": {
                        "candidate_id": "client-hero",
                        "source": "client",
                        "type": "image",
                        "asset": {"path": "input/assets/banners/hero.jpg"},
                    }
                }
            },
        },
        "review": {
            "query_parameter": "direction",
            "allowed_values": list(direction_ids),
            "show_comparison": True,
        },
    }
    (client_dir / "prototype" / "prototype-manifest.yaml").write_text(
        yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8"
    )


class RuntimeBundleTests(unittest.TestCase):
    def test_builds_canonical_client_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client, ("a", "b", "c"))
            output = build_runtime_bundle(root, client, root / "output")
            bundle = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual("acme-client", bundle["client_id"])
        self.assertEqual("a", bundle["default_direction"])
        self.assertEqual({"a", "b", "c"}, set(bundle["directions"]))
        self.assertEqual(
            "search-led", bundle["directions"]["a"]["navigation_model"]
        )
        self.assertEqual("compact", bundle["directions"]["a"]["density"])
        self.assertIn("fixtures", bundle)
        self.assertIn("theme", bundle)
        self.assertIn("resources", bundle)
        self.assertEqual(["a", "b", "c"], bundle["review"]["allowed_directions"])
        self.assertNotIn("allowed_values", bundle["review"])
        self.assertEqual([], validate_runtime_bundle(bundle))

    def test_builds_two_direction_bundle_deterministically_and_preserves_resources(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)
            first_dir = root / "first"
            second_dir = root / "second"

            first = build_runtime_bundle(root, client, first_dir)
            second = build_runtime_bundle(root, client, second_dir)

            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertTrue(first.read_bytes().endswith(b"\n"))
            bundle = json.loads(first.read_text(encoding="utf-8"))
            self.assertEqual(["a", "b"], list(bundle["directions"]))
            self.assertEqual(["a", "b"], bundle["review"]["allowed_directions"])
            self.assertTrue(bundle["review"]["show_comparison"])
            expected_resources = yaml.safe_load(
                (client / "prototype" / "prototype-manifest.yaml").read_text(encoding="utf-8")
            )["resources"]
            self.assertEqual(expected_resources, bundle["resources"])

    def test_validator_accepts_three_directions_and_fixture_shapes(self):
        bundle = _bundle(("a", "b", "c"))
        bundle["directions"]["b"]["density"] = "normal"
        bundle["directions"]["c"]["density"] = "spacious"
        bundle["fixtures"] = {
            "industry": "services-booking",
            "seed": 108,
            "products": [],
            "services": [
                {
                    "id": "svc-01",
                    "name": "Initial Consultation",
                    "price": 499,
                    "duration_minutes": 30,
                    "rating": 4.5,
                }
            ],
        }
        self.assertEqual([], validate_runtime_bundle(bundle))

    def test_validator_reports_bundle_and_direction_contract_errors(self):
        cases = {
            "version": ({**_bundle(), "version": 2}, "version"),
            "unsafe client id": ({**_bundle(), "client_id": "../acme"}, "client_id"),
            "direction count": (_bundle(("a",)), "2 or 3"),
            "missing b": (_bundle(("a", "c")), "include a and b"),
            "default": ({**_bundle(), "default_direction": "c"}, "default_direction"),
        }
        mismatch = _bundle()
        mismatch["directions"]["b"]["id"] = "c"
        cases["direction id"] = (mismatch, "direction key")
        bad_density = _bundle()
        bad_density["directions"]["a"]["density"] = "dense"
        cases["density"] = (bad_density, "density")
        missing_field = _bundle()
        del missing_field["directions"]["a"]["navigation_model"]
        cases["canonical field"] = (missing_field, "navigation_model")
        review_order = _bundle()
        review_order["review"]["allowed_directions"] = ["b", "a"]
        cases["review order"] = (review_order, "allowed_directions")

        for label, (bundle, expected) in cases.items():
            with self.subTest(label=label):
                errors = validate_runtime_bundle(bundle)
                self.assertTrue(any(expected in error for error in errors), errors)

    def test_validator_enforces_design_contract_pattern_ids(self):
        canonical_pattern_ids = sorted(build_indexes(ROOT)["patterns"])
        bundle = _bundle()
        bundle["directions"]["a"]["patterns"] = canonical_pattern_ids
        self.assertEqual([], validate_runtime_bundle(bundle))

        bundle["directions"]["a"]["patterns"] = ["cart"]
        self.assertEqual(
            [
                "directions.a.patterns.0 references unknown canonical pattern "
                "'cart'"
            ],
            validate_runtime_bundle(bundle),
        )

    def test_validator_reports_malformed_fixture_fields(self):
        cases = {}
        for collection, field in (
            ("products", "sku"),
            ("services", "duration_minutes"),
        ):
            bundle = _bundle()
            if collection == "services":
                bundle["fixtures"]["services"] = [
                    {
                        "id": "svc-01",
                        "name": "Consultation",
                        "price": 499,
                        "duration_minutes": 30,
                        "rating": 4.5,
                    }
                ]
            del bundle["fixtures"][collection][0][field]
            cases[f"{collection}.{field}"] = (bundle, field)

        wrong_root = _bundle()
        wrong_root["fixtures"] = []
        cases["fixture root"] = (wrong_root, "fixtures")

        for label, (bundle, expected) in cases.items():
            with self.subTest(label=label):
                errors = validate_runtime_bundle(bundle)
                self.assertTrue(any(expected in error for error in errors), errors)

    def test_validator_reports_invalid_theme_and_resource_bindings(self):
        cases = {}
        bad_theme = _bundle()
        bad_theme["theme"]["seed_color"] = "6750A4"
        cases["theme"] = (bad_theme, "seed_color")

        unknown_id = _bundle()
        unknown_id["resources"] = {
            "home.hero": {
                "candidate_id": "hero",
                "source": "client",
                "type": "image",
                "asset": {},
            }
        }
        cases["canonical id"] = (unknown_id, "canonical resource id")

        malformed_binding = _bundle()
        malformed_binding["resources"] = {"asset.home.hero": {"type": "image"}}
        cases["binding"] = (malformed_binding, "candidate_id")

        bad_override_direction = _bundle()
        bad_override_direction["resources"] = {"direction_overrides": {"c": {}}}
        cases["override direction"] = (bad_override_direction, "unknown direction")

        malformed_override = _bundle()
        malformed_override["resources"] = {"direction_overrides": {"b": []}}
        cases["override group"] = (malformed_override, "must be an object")

        for label, (bundle, expected) in cases.items():
            with self.subTest(label=label):
                errors = validate_runtime_bundle(bundle)
                self.assertTrue(any(expected in error for error in errors), errors)

    def test_validator_reports_non_string_resource_types_without_raising(self):
        for resource_type in ([], {}):
            with self.subTest(resource_type=resource_type):
                bundle = _bundle()
                bundle["resources"]["asset.home.hero"]["type"] = resource_type

                self.assertEqual(
                    ["resources.asset.home.hero.type must be a non-empty string"],
                    validate_runtime_bundle(bundle),
                )

    def test_validator_error_order_is_independent_of_map_insertion_order(self):
        bundle = _bundle()
        bundle["directions"]["a"]["patterns"] = ["cart", "unknown-pattern"]
        bundle["resources"] = {
            "bad.second": {"type": "image"},
            "bad.first": {"type": "icon"},
            "direction_overrides": {
                "z": {"bad.override": {"type": "motion"}},
                "b": {"bad.nested": {"type": "image"}},
            },
        }

        def reverse_maps(value):
            if isinstance(value, dict):
                return {
                    key: reverse_maps(item)
                    for key, item in reversed(list(value.items()))
                }
            if isinstance(value, list):
                return [reverse_maps(item) for item in value]
            return value

        errors = validate_runtime_bundle(bundle)
        self.assertTrue(errors)
        self.assertEqual(errors, validate_runtime_bundle(reverse_maps(bundle)))

    def test_validator_resolves_required_resources_per_direction(self):
        bundle = _bundle()
        bundle["resources"] = {
            "direction_overrides": {
                "a": {"asset.home.hero": _resource_binding("hero-a")},
                "b": {"asset.home.hero": _resource_binding("hero-b")},
            }
        }
        self.assertEqual([], validate_runtime_bundle(bundle))

    def test_validator_reports_required_resource_missing_from_own_bindings(self):
        bundle = _bundle()
        bundle["resources"] = {
            "direction_overrides": {
                "b": {"asset.home.hero": _resource_binding("hero-b")}
            }
        }

        self.assertEqual(
            [
                "directions.a.required_resources.0 references unresolved resource "
                "'asset.home.hero'"
            ],
            validate_runtime_bundle(bundle),
        )

    def test_validator_accepts_candidate_reuse_across_canonical_ids(self):
        bundle = _bundle()
        bundle["resources"]["asset.category.hero"] = _resource_binding("hero")

        self.assertEqual([], validate_runtime_bundle(bundle))

    def test_validator_rejects_bool_and_non_finite_fixture_numbers(self):
        cases = {
            "bool price": ("price", True),
            "nan price": ("price", float("nan")),
            "positive infinity rating": ("rating", float("inf")),
            "negative infinity compare_at": ("compare_at", float("-inf")),
        }

        for label, (field, value) in cases.items():
            with self.subTest(label=label):
                bundle = _bundle()
                bundle["fixtures"]["products"][0][field] = value
                errors = validate_runtime_bundle(bundle)
                self.assertTrue(
                    any(f"fixtures.products.0.{field} must be a number" in error for error in errors),
                    errors,
                )

    def test_validator_rejects_values_outside_json_data_model(self):
        cases = {
            "yaml date": ("fixtures.generated_on", date(2026, 9, 15)),
            "yaml set": ("resources.asset.home.hero.asset.tags", {"featured"}),
            "unsupported map key": ("theme.<key 1>", {1: "invalid"}),
        }

        for label, (expected_path, value) in cases.items():
            with self.subTest(label=label):
                bundle = _bundle()
                if label == "yaml date":
                    bundle["fixtures"]["generated_on"] = value
                elif label == "yaml set":
                    bundle["resources"]["asset.home.hero"]["asset"]["tags"] = value
                else:
                    bundle["theme"].update(value)
                errors = validate_runtime_bundle(bundle)
                self.assertTrue(
                    any(
                        expected_path in error and "JSON-compatible" in error
                        for error in errors
                    ),
                    errors,
                )

    def test_validator_rejects_cyclic_json_containers_deterministically(self):
        cyclic_list = []
        cyclic_list.append(cyclic_list)
        cyclic_map = {}
        cyclic_map["self"] = cyclic_map

        cases = {
            "list": (
                cyclic_list,
                "runtime bundle.fixtures.cycle.0 must be JSON-compatible "
                "(cyclic reference)",
            ),
            "map": (
                cyclic_map,
                "runtime bundle.fixtures.cycle.self must be JSON-compatible "
                "(cyclic reference)",
            ),
        }
        for label, (cycle, expected) in cases.items():
            with self.subTest(label=label):
                bundle = _bundle()
                bundle["fixtures"]["cycle"] = cycle

                self.assertEqual([expected], validate_runtime_bundle(bundle))

    def test_validator_accepts_shared_acyclic_json_containers(self):
        shared = {"labels": ["featured"]}
        bundle = _bundle()
        bundle["fixtures"]["first"] = shared
        bundle["fixtures"]["second"] = shared

        self.assertEqual([], validate_runtime_bundle(bundle))

    def test_builder_rejects_non_json_yaml_values_with_governed_error(self):
        cases = {
            "non-finite number": lambda manifest, fixtures: fixtures["products"][0].update(
                {"price": float("nan")}
            ),
            "yaml date": lambda manifest, fixtures: manifest["theme"].update(
                {"generated_on": date(2026, 9, 15)}
            ),
            "yaml set": lambda manifest, fixtures: manifest["resources"][
                "asset.home.hero"
            ]["asset"].update({"tags": {"featured"}}),
            "unsupported map key": lambda manifest, fixtures: manifest["resources"][
                "asset.home.hero"
            ].update({1: "invalid"}),
        }

        for label, mutate in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                client = root / "client-projects" / "acme-client"
                _write_client(client)
                manifest_path = client / "prototype" / "prototype-manifest.yaml"
                fixture_path = client / "prototype" / "fixtures" / "demo.yaml"
                manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
                fixtures = yaml.safe_load(fixture_path.read_text(encoding="utf-8"))
                mutate(manifest, fixtures)
                manifest_path.write_text(
                    yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8"
                )
                fixture_path.write_text(
                    yaml.safe_dump(fixtures, sort_keys=False), encoding="utf-8"
                )

                with self.assertRaisesRegex(
                    ValueError, "^invalid runtime bundle: .*JSON-compatible"
                ):
                    build_runtime_bundle(root, client, root / "output")

    def test_builder_rejects_cyclic_yaml_alias_with_governed_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)
            fixture_path = client / "prototype" / "fixtures" / "demo.yaml"
            fixtures = yaml.safe_load(fixture_path.read_text(encoding="utf-8"))
            cyclic_list = []
            cyclic_list.append(cyclic_list)
            fixtures["cycle"] = cyclic_list
            fixture_path.write_text(
                yaml.safe_dump(fixtures, sort_keys=False), encoding="utf-8"
            )

            with self.assertRaisesRegex(
                ValueError,
                "^invalid runtime bundle: .*JSON-compatible .*cyclic reference",
            ):
                build_runtime_bundle(root, client, root / "output")

    def test_builder_governs_invalid_utf8_input_errors(self):
        cases = {
            "manifest YAML": lambda client: client
            / "prototype"
            / "prototype-manifest.yaml",
            "direction JSON": lambda client: client
            / "prototype"
            / "runtime"
            / "direction-a.json",
            "fixture YAML": lambda client: client
            / "prototype"
            / "fixtures"
            / "demo.yaml",
        }

        for label, input_path in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                client = root / "client-projects" / "acme-client"
                _write_client(client)
                input_path(client).write_bytes(b"\xff")

                with self.assertRaises(ValueError) as caught:
                    build_runtime_bundle(root, client, root / "output")

                self.assertEqual(ValueError, type(caught.exception))
                self.assertTrue(
                    str(caught.exception).startswith(
                        "invalid runtime bundle: cannot load "
                    ),
                    caught.exception,
                )

    def test_builder_rejects_invalid_manifest_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)
            manifest_path = client / "prototype" / "prototype-manifest.yaml"
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            manifest["review"]["allowed_values"] = ["a"]
            manifest_path.write_text(
                yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8"
            )

            with self.assertRaisesRegex(
                ValueError, "^invalid runtime bundle: .*allowed_directions"
            ):
                build_runtime_bundle(root, client, root / "output")


if __name__ == "__main__":
    unittest.main()
