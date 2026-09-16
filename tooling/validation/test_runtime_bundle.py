from __future__ import annotations

import copy
import inspect
import json
import shutil
import tempfile
import unittest
from datetime import date
from pathlib import Path

import yaml

from tooling.design_contract.flutter_bindings import (
    load_flutter_bindings,
    runtime_binding_errors,
)
from tooling.design_contract.generate_resolved_themes import (
    check_default_theme_fresh,
    check_resolved_bundles_fresh,
    render_default_theme_dart,
    write_default_theme,
    write_resolved_bundles,
)
from tooling.design_contract.theme_contract import CANONICAL_GROUPS, resolve_theme
from tooling.knowledge.index_design_contract import build_indexes
from tooling.prototype.build_runtime_bundle import (
    build_runtime_bundle,
    compose_runtime_bundle,
)
from tooling.prototype import validate_runtime_bundle as runtime_bundle_validator
from tooling.prototype.project_direction import project_direction
from tooling.prototype.refinement_notes import validate_refinement_notes
from tooling.validation.validate_repo import refinement_note_errors


validate_runtime_bundle = runtime_bundle_validator.validate_runtime_bundle


ROOT = Path(__file__).resolve().parents[2]
_RESOLVED_THEME = resolve_theme(ROOT, "premium-modern")
_EXAMPLE_REFINEMENT_NOTES = (
    ROOT
    / "client-projects"
    / "examples"
    / "prototype-demo"
    / "prototype"
    / "refinement-notes.yaml"
)
def _compose_bundle_bytes(root: Path, client_dir: Path) -> tuple[dict, bytes]:
    """Compose a bundle and serialize it exactly as ``build_runtime_bundle`` does."""
    bundle = compose_runtime_bundle(root, client_dir)
    serialized = json.dumps(bundle, indent=2, sort_keys=True, allow_nan=False) + "\n"
    return bundle, serialized.encode("utf-8")


def _copy_theme_contract(root: Path) -> None:
    for catalog in ("tokens", "themes"):
        source = ROOT / "design-contract" / catalog
        destination = root / "design-contract" / catalog
        destination.mkdir(parents=True, exist_ok=True)
        for path in sorted(source.glob("*.yaml")):
            shutil.copyfile(path, destination / path.name)


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
        "theme": copy.deepcopy(_RESOLVED_THEME),
        "direction_themes": {
            direction_id: copy.deepcopy(_RESOLVED_THEME) for direction_id in direction_ids
        },
        "resources": {"asset.home.hero": _resource_binding()},
        "review": {
            "query_parameter": "direction",
            "allowed_directions": list(direction_ids),
        },
    }


def _write_design_contract(
    root: Path,
    *,
    patterns: dict[str, str] | None = None,
    components: dict[str, str] | None = None,
) -> None:
    catalogs = {
        "patterns": patterns
        or {"commerce.search": "approved", "commerce.pdp": "approved"},
        "components": components or {"commerce.product-card": "approved"},
    }
    for catalog, contracts in catalogs.items():
        catalog_dir = root / "design-contract" / catalog
        catalog_dir.mkdir(parents=True, exist_ok=True)
        for contract_id, status in contracts.items():
            (catalog_dir / f"{contract_id.replace('.', '-')}.yaml").write_text(
                yaml.safe_dump({"id": contract_id, "status": status}),
                encoding="utf-8",
            )


def _write_client(
    client_dir: Path,
    direction_ids: tuple[str, ...] = ("a", "b"),
    densities: dict[str, str] | None = None,
) -> None:
    root = client_dir.parents[1]
    _write_design_contract(root)
    _copy_theme_contract(root)
    brand_dir = client_dir / "input" / "brand"
    brand_dir.mkdir(parents=True)
    (brand_dir / "brand-input.yaml").write_text(
        yaml.safe_dump(
            {
                "version": 1,
                "provided": True,
                "facts": [],
                "visual": {"preset": "premium-modern"},
            },
            sort_keys=False,
        ),
        encoding="utf-8",
    )
    runtime_dir = client_dir / "prototype" / "runtime"
    fixture_dir = client_dir / "prototype" / "fixtures"
    runtime_dir.mkdir(parents=True)
    fixture_dir.mkdir(parents=True)

    direction_paths = {}
    for direction_id in direction_ids:
        relative_path = f"prototype/runtime/direction-{direction_id}.json"
        density = (densities or {}).get(direction_id, "compact")
        (client_dir / relative_path).write_text(
            json.dumps(
                _direction(direction_id, density=density), indent=2, sort_keys=True
            )
            + "\n",
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
        "theme": {"preset": "premium-modern"},
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
    def test_prototype_demo_runtime_directions_match_approved_canonical_sources(self):
        indexes = build_indexes(ROOT)
        legacy_short_ids = {"cart", "reorder", "trade-dashboard"}
        client_dir = ROOT / "client-projects" / "examples" / "prototype-demo"
        directions_dir = client_dir / "directions"
        manifest = yaml.safe_load(
            (client_dir / "prototype" / "prototype-manifest.yaml").read_text(
                encoding="utf-8"
            )
        )
        runtime_paths = manifest["directions"]
        strategic_paths = {
            path.stem.removeprefix("direction-"): path
            for path in sorted(directions_dir.glob("direction-*.yaml"))
        }
        generated_runtime_paths = {
            path.relative_to(client_dir).as_posix()
            for path in (client_dir / "prototype" / "runtime").glob("direction-*.json")
        }

        self.assertEqual(set(strategic_paths), set(runtime_paths))
        self.assertEqual(set(runtime_paths.values()), generated_runtime_paths)

        for direction_id, relative_runtime_path in sorted(runtime_paths.items()):
            strategic = yaml.safe_load(
                strategic_paths[direction_id].read_text(encoding="utf-8")
            )
            projected = project_direction(strategic)
            runtime_path = client_dir / relative_runtime_path
            runtime_text = runtime_path.read_text(encoding="utf-8")
            runtime = json.loads(runtime_text)

            with self.subTest(direction=direction_id, assertion="semantic projection"):
                self.assertEqual(projected, runtime)
            with self.subTest(direction=direction_id, assertion="deterministic JSON"):
                self.assertEqual(
                    json.dumps(project_direction(strategic), indent=2, sort_keys=True)
                    + "\n",
                    runtime_text,
                )

            for label, patterns in (
                ("strategic", strategic["patterns"]),
                ("projected", projected["patterns"]),
            ):
                with self.subTest(direction=direction_id, artifact=label):
                    self.assertTrue(legacy_short_ids.isdisjoint(patterns), patterns)

            references = (
                ("patterns", runtime["patterns"], indexes["patterns"]),
                ("components", runtime["components"], indexes["components"]),
                (
                    "component_variants",
                    [item["component"] for item in runtime["component_variants"]],
                    indexes["components"],
                ),
            )
            for field, contract_ids, contracts in references:
                for contract_id in contract_ids:
                    with self.subTest(
                        direction=direction_id, field=field, contract=contract_id
                    ):
                        contract = contracts.get(contract_id)
                        self.assertIsNotNone(contract, "canonical contract is missing")
                        if contract is not None:
                            self.assertEqual("approved", contract.get("status"))

    def test_generated_bundles_have_approved_flutter_bindings(self):
        bindings = load_flutter_bindings(ROOT)
        bundle_paths = sorted(
            (ROOT / "apps" / "prototype_app" / "assets" / "generated").glob("*.json")
        )
        self.assertTrue(bundle_paths)

        errors = []
        for bundle_path in bundle_paths:
            bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
            for direction_id, direction in sorted(bundle.get("directions", {}).items()):
                for error in runtime_binding_errors(ROOT, direction, bindings):
                    errors.append(f"{bundle_path.name}:{direction_id}: {error}")

        self.assertEqual([], sorted(errors))

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

    def test_builder_preserves_full_b1c_resource_binding_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)

            bundle = json.loads(
                build_runtime_bundle(root, client, root / "output").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(
            {
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
            bundle["resources"]["asset.home.hero"],
        )
        self.assertEqual(
            {
                "b": {
                    "asset.home.hero": {
                        "candidate_id": "client-hero",
                        "source": "client",
                        "type": "image",
                        "asset": {"path": "input/assets/banners/hero.jpg"},
                    }
                }
            },
            bundle["resources"]["direction_overrides"],
        )

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

    def test_intrinsic_validator_has_one_argument_and_does_not_consult_catalogs(self):
        self.assertEqual(
            ["bundle"], list(inspect.signature(validate_runtime_bundle).parameters)
        )
        bundle = _bundle()
        bundle["directions"]["a"]["patterns"] = ["not.in.any.catalog"]
        bundle["directions"]["a"]["components"] = ["also.not.in.catalog"]
        bundle["directions"]["a"]["component_variants"] = [
            {"component": "also.not.in.catalog", "variant": "test"}
        ]

        self.assertEqual([], validate_runtime_bundle(bundle))

    def test_root_aware_validator_resolves_patterns_components_and_variants(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_design_contract(root)
            bundle = _bundle()
            bundle["directions"]["a"]["patterns"] = ["missing.pattern"]
            bundle["directions"]["a"]["components"] = ["missing.component"]
            bundle["directions"]["a"]["component_variants"] = [
                {"component": "missing.variant-component", "variant": "test"}
            ]

            self.assertEqual(
                [
                    "directions.a.component_variants.0.component references unknown "
                    "canonical component 'missing.variant-component'",
                    "directions.a.components.0 references unknown canonical component "
                    "'missing.component'",
                    "directions.a.patterns.0 references unknown canonical pattern "
                    "'missing.pattern'",
                ],
                runtime_bundle_validator.validate_runtime_bundle_against_design_contract(
                    root, bundle
                ),
            )

    def test_component_variant_component_must_be_listed_in_direction_components(self):
        bundle = _bundle()
        bundle["directions"]["a"]["component_variants"] = [
            {"component": "commerce.search-field", "variant": "compact"}
        ]

        self.assertEqual(
            [
                "directions.a.component_variants.0.component 'commerce.search-field' "
                "must be listed in directions.a.components"
            ],
            validate_runtime_bundle(bundle),
        )

    def test_root_aware_validator_uses_each_explicit_root_without_cache_leakage(self):
        with (
            tempfile.TemporaryDirectory() as first_tmp,
            tempfile.TemporaryDirectory() as second_tmp,
        ):
            first_root = Path(first_tmp)
            second_root = Path(second_tmp)
            _write_design_contract(
                first_root,
                patterns={"first.pattern": "approved"},
                components={"first.component": "experimental"},
            )
            _write_design_contract(
                second_root,
                patterns={"second.pattern": "approved"},
                components={"second.component": "approved"},
            )
            bundle = _bundle()
            for direction in bundle["directions"].values():
                direction["patterns"] = ["first.pattern"]
                direction["components"] = ["first.component"]
                direction["component_variants"] = [
                    {"component": "first.component", "variant": "test"}
                ]

            self.assertEqual(
                [],
                runtime_bundle_validator.validate_runtime_bundle_against_design_contract(
                    first_root, bundle
                ),
            )
            second_errors = (
                runtime_bundle_validator.validate_runtime_bundle_against_design_contract(
                    second_root, bundle
                )
            )
            self.assertTrue(
                any(
                    "unknown canonical pattern 'first.pattern'" in error
                    for error in second_errors
                ),
                second_errors,
            )
            self.assertTrue(
                any(
                    "unknown canonical component 'first.component'" in error
                    for error in second_errors
                ),
                second_errors,
            )

    def test_root_aware_validator_rejects_deprecated_contracts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_design_contract(
                root,
                patterns={"commerce.search": "deprecated", "commerce.pdp": "approved"},
                components={"commerce.product-card": "deprecated"},
            )

            errors = runtime_bundle_validator.validate_runtime_bundle_against_design_contract(
                root, _bundle()
            )
            self.assertTrue(
                any(
                    "ineligible canonical pattern 'commerce.search'" in error
                    for error in errors
                ),
                errors,
            )
            self.assertTrue(
                any(
                    "directions.a.components.0 references ineligible canonical "
                    "component 'commerce.product-card'" == error
                    for error in errors
                ),
                errors,
            )
            self.assertTrue(
                any(
                    "directions.a.component_variants.0.component references "
                    "ineligible canonical component 'commerce.product-card'" == error
                    for error in errors
                ),
                errors,
            )

    def test_root_aware_validator_accepts_repository_contract_ids(self):
        canonical_pattern_ids = sorted(build_indexes(ROOT)["patterns"])
        bundle = _bundle()
        bundle["directions"]["a"]["patterns"] = canonical_pattern_ids
        self.assertEqual(
            [],
            runtime_bundle_validator.validate_runtime_bundle_against_design_contract(
                ROOT, bundle
            ),
        )

        bundle["directions"]["a"]["patterns"] = ["cart"]
        self.assertEqual(
            [
                "directions.a.patterns.0 references unknown canonical pattern "
                "'cart'"
            ],
            runtime_bundle_validator.validate_runtime_bundle_against_design_contract(
                ROOT, bundle
            ),
        )

    def test_no_hand_maintained_canonical_pattern_adapter_remains(self):
        app_lib_dir = ROOT / "apps" / "prototype_app" / "lib"
        lib_dirs = (
            app_lib_dir,
            ROOT / "packages" / "agency_flutter_ui" / "lib",
        )
        self.assertFalse(
            (app_lib_dir / "registry" / "canonical_pattern_adapter.dart").exists()
        )

        heuristic_patterns = (
            "canonicalToRegistry",
            "toRegistryKey",
            "replace('commerce.",
            'replace("commerce.',
            "replaceFirst('commerce.",
            'replaceFirst("commerce.',
            ".split('.').last",
            '.split(".").last',
            ".split('.').first",
            '.split(".").first',
        )
        for lib_dir in lib_dirs:
            for path in sorted(lib_dir.rglob("*.dart")):
                source = path.read_text(encoding="utf-8")
                for pattern in heuristic_patterns:
                    with self.subTest(
                        file=path.relative_to(ROOT).as_posix(), pattern=pattern
                    ):
                        self.assertNotIn(pattern, source)

        for path in sorted((app_lib_dir / "registry").glob("*.dart")):
            with self.subTest(file=path.name, pattern="substring"):
                self.assertNotIn("substring(", path.read_text(encoding="utf-8"))

    def test_builder_rejects_checkout_ids_absent_from_supplied_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)
            for path in (root / "design-contract").glob("**/*.yaml"):
                path.unlink()
            _write_design_contract(
                root,
                patterns={"other.pattern": "approved"},
                components={"other.component": "approved"},
            )
            _copy_theme_contract(root)

            with self.assertRaisesRegex(
                ValueError,
                "^invalid runtime bundle: .*unknown canonical component "
                "'commerce.product-card'.*unknown canonical pattern 'commerce.pdp'",
            ):
                build_runtime_bundle(root, client, root / "output")

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
        bad_theme["theme"]["color"]["primary"] = "6750A4"
        cases["theme"] = (bad_theme, "color.primary")

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
            "yaml date": lambda manifest, fixtures: manifest["review"].update(
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

    def test_refinement_notes_are_never_runtime_input(self):
        note_text = _EXAMPLE_REFINEMENT_NOTES.read_text(encoding="utf-8")
        note_path = None
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)
            note_path = client / "prototype" / "refinement-notes.yaml"

            _, before = _compose_bundle_bytes(root, client)

            note_path.write_text(note_text, encoding="utf-8")
            bundle, after = _compose_bundle_bytes(root, client)

            # A malformed note must also never block or alter runtime composition.
            note_path.write_text("version: 1\nchanges: {not: valid}\n", encoding="utf-8")
            _, invalid_after = _compose_bundle_bytes(root, client)

        self.assertEqual(before, after)
        self.assertEqual(before, invalid_after)
        self.assertNotIn("refinement_notes", bundle)
        self.assertNotIn("refinement-notes", bundle)
        self.assertFalse(
            [value for value in _walk_strings(bundle) if "refinement" in value]
        )

    def test_example_refinement_notes_validate_clean(self):
        self.assertTrue(_EXAMPLE_REFINEMENT_NOTES.is_file())
        self.assertEqual(
            [], validate_refinement_notes(ROOT, _EXAMPLE_REFINEMENT_NOTES)
        )

    def test_complete_client_without_refinement_notes_passes_runtime_and_note_validation(
        self,
    ):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)

            note_path = client / "prototype" / "refinement-notes.yaml"
            self.assertFalse(note_path.exists())
            self.assertEqual([], refinement_note_errors(root))

            output = build_runtime_bundle(root, client, root / "output")
            bundle = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual("acme-client", bundle["client_id"])
        self.assertEqual([], validate_runtime_bundle(bundle))


def _walk_strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from _walk_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _walk_strings(item)
    elif isinstance(value, str):
        yield value


class ResolvedThemeBundleTests(unittest.TestCase):
    def test_bundle_theme_is_compiled_and_reference_free(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)

            bundle = json.loads(
                build_runtime_bundle(root, client, root / "output").read_text(
                    encoding="utf-8"
                )
            )
            manifest = yaml.safe_load(
                (client / "prototype" / "prototype-manifest.yaml").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual({"preset": "premium-modern"}, manifest["theme"])
        self.assertEqual(1, bundle["theme"]["version"])
        self.assertEqual(
            sorted(CANONICAL_GROUPS),
            sorted(key for key in bundle["theme"] if key != "version"),
        )
        self.assertFalse(
            [value for value in _walk_strings(bundle["theme"]) if "{foundation." in value]
        )
        self.assertFalse(
            [
                value
                for value in _walk_strings(bundle["direction_themes"])
                if "{foundation." in value
            ]
        )

    def test_direction_themes_use_canonical_direction_density(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(
                client,
                ("a", "b", "c"),
                densities={"a": "compact", "b": "normal", "c": "spacious"},
            )

            bundle = json.loads(
                build_runtime_bundle(root, client, root / "output").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual("compact", bundle["direction_themes"]["a"]["density"]["default"])
        self.assertEqual("normal", bundle["direction_themes"]["b"]["density"]["default"])
        self.assertEqual(
            "spacious", bundle["direction_themes"]["c"]["density"]["default"]
        )

    def test_refinement_note_target_cannot_redefine_runtime_theme_authority(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)

            baseline_bundle, baseline_bytes = _compose_bundle_bytes(root, client)
            baseline_theme = copy.deepcopy(baseline_bundle["theme"])
            baseline_direction_themes = copy.deepcopy(
                baseline_bundle["direction_themes"]
            )

            note_path = client / "prototype" / "refinement-notes.yaml"
            note_path.write_text(
                """version: 1
changes:
  - id: repaint-primary
    change: make the primary brand colour hotter in Nowa
    classification: client_override
    status: observed
    target: theme.color.primary
""",
                encoding="utf-8",
            )

            after_bundle, after_bytes = _compose_bundle_bytes(root, client)
            fresh_theme = resolve_theme(
                root, "premium-modern", {"preset": "premium-modern"}, None
            )

        self.assertEqual(baseline_bytes, after_bytes)
        self.assertEqual(baseline_theme, after_bundle["theme"])
        self.assertEqual(fresh_theme, after_bundle["theme"])
        self.assertEqual(baseline_direction_themes, after_bundle["direction_themes"])

    def test_bundle_theme_matches_fresh_resolve(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)

            bundle = json.loads(
                build_runtime_bundle(root, client, root / "output").read_text(
                    encoding="utf-8"
                )
            )

            expected = resolve_theme(root, "premium-modern", {"preset": "premium-modern"}, None)

        self.assertEqual(expected, bundle["theme"])

    def test_validator_rejects_unresolved_theme_reference(self):
        bundle = _bundle()
        bundle["theme"]["color"]["primary"] = "{foundation.color.blue.600}"

        errors = validate_runtime_bundle(bundle)

        self.assertTrue(any("theme.color.primary" in error for error in errors), errors)

    def test_validator_rejects_missing_theme_group(self):
        bundle = _bundle()
        del bundle["theme"]["motion"]

        errors = validate_runtime_bundle(bundle)

        self.assertTrue(any("motion" in error for error in errors), errors)

    def test_validator_rejects_unknown_direction_theme(self):
        bundle = _bundle()
        bundle["direction_themes"]["z"] = copy.deepcopy(_RESOLVED_THEME)

        errors = validate_runtime_bundle(bundle)

        self.assertTrue(any("direction_themes.z" in error for error in errors), errors)

    def test_default_theme_projection_is_deterministic_and_fresh(self):
        first = render_default_theme_dart(ROOT)
        second = render_default_theme_dart(ROOT)

        self.assertEqual(first, second)
        self.assertNotIn("\r", first)
        self.assertTrue(first.endswith("\n"))
        self.assertFalse(first.endswith("\n\n"))
        self.assertEqual([], check_default_theme_fresh(ROOT))

    def test_stale_default_theme_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _copy_theme_contract(root)
            generated = write_default_theme(root)
            self.assertEqual([], check_default_theme_fresh(root))

            generated.write_bytes(generated.read_bytes() + b"\n")

            self.assertTrue(check_default_theme_fresh(root))

    def test_resolved_bundle_freshness_detects_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme-client"
            _write_client(client)

            write_resolved_bundles(root)
            self.assertEqual([], check_resolved_bundles_fresh(root))

            bundle_path = (
                root
                / "apps"
                / "prototype_app"
                / "assets"
                / "generated"
                / "acme-client.json"
            )
            data = json.loads(bundle_path.read_text(encoding="utf-8"))
            data["theme"]["color"]["primary"] = "#000000"
            bundle_path.write_text(
                json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )

            self.assertTrue(check_resolved_bundles_fresh(root))


if __name__ == "__main__":
    unittest.main()
