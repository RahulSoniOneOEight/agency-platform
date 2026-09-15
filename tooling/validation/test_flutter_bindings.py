from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.design_contract.flutter_bindings import (
    load_flutter_bindings,
    runtime_binding_errors,
    validate_flutter_bindings,
)
from tooling.design_contract.generate_flutter_bindings import (
    check_flutter_bindings_fresh,
    render_flutter_bindings,
    write_flutter_bindings,
)
from tooling.knowledge.index_design_contract import build_indexes


ROOT = Path(__file__).resolve().parents[2]
FLUTTER_LIB = ROOT / "packages" / "agency_flutter_ui" / "lib"


def _flutter_source() -> str:
    return "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(FLUTTER_LIB.rglob("*.dart"))
    )

_TEMP_DIRECTORIES: list[tempfile.TemporaryDirectory] = []


def tearDownModule():
    for handle in _TEMP_DIRECTORIES:
        handle.cleanup()
    _TEMP_DIRECTORIES.clear()


def _contract_root() -> Path:
    handle = tempfile.TemporaryDirectory()
    _TEMP_DIRECTORIES.append(handle)
    return Path(handle.name)


def _write_component(
    root: Path,
    contract_id: str = "commerce.product-card",
    *,
    status: str = "approved",
    variants: tuple[str, ...] = ("standard",),
    states: tuple[str, ...] = ("normal",),
    density: tuple[str, ...] = ("compact", "normal"),
    requires: tuple[str, ...] = (),
) -> None:
    directory = root / "design-contract" / "components"
    directory.mkdir(parents=True, exist_ok=True)
    record = {
        "id": contract_id,
        "name": contract_id,
        "category": "commerce.test",
        "purpose": "Test component.",
        "business_models": ["b2c"],
        "use_cases": ["test"],
        "variants": list(variants),
        "states": list(states),
        "density": list(density),
        "requires": list(requires),
        "status": status,
    }
    (directory / f"{contract_id.replace('.', '-')}.yaml").write_text(
        yaml.safe_dump(record, sort_keys=False), encoding="utf-8"
    )


def _write_pattern(
    root: Path,
    contract_id: str = "commerce.cart",
    *,
    status: str = "approved",
) -> None:
    directory = root / "design-contract" / "patterns"
    directory.mkdir(parents=True, exist_ok=True)
    record = {
        "id": contract_id,
        "name": contract_id,
        "purpose": "Test pattern.",
        "status": status,
        "compatible_components": [],
    }
    (directory / f"{contract_id.replace('.', '-')}.yaml").write_text(
        yaml.safe_dump(record, sort_keys=False), encoding="utf-8"
    )


def _write_binding(root: Path, binding: dict) -> None:
    directory = root / "design-contract" / "bindings" / "flutter"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{binding['id'].replace('.', '-')}.yaml").write_text(
        yaml.safe_dump(binding, sort_keys=False), encoding="utf-8"
    )


def component_binding(contract_id: str = "commerce.product-card", **overrides) -> dict:
    binding = {
        "id": contract_id,
        "kind": "component",
        "status": "approved",
        "implementation": {
            "package": "agency_flutter_ui",
            "registry_key": "product-card",
            "symbol": "ProductCard",
        },
        "variants": {"standard": "standard"},
        "states": {"normal": "supported"},
        "density": {"compact": "dense", "normal": "balanced"},
    }
    binding.update(overrides)
    return binding


def pattern_binding(contract_id: str = "commerce.cart", **overrides) -> dict:
    binding = {
        "id": contract_id,
        "kind": "pattern",
        "status": "approved",
        "implementation": {
            "package": "agency_flutter_ui",
            "registry_key": "cart",
            "symbol": "CartPattern",
        },
        "variants": {},
        "states": {},
        "density": {"compact": "dense", "normal": "balanced", "spacious": "airy"},
    }
    binding.update(overrides)
    return binding


class FlutterBindingTests(unittest.TestCase):
    def test_missing_contract_is_rejected(self):
        root = _contract_root()
        _write_binding(
            root,
            {
                "id": "commerce.unknown",
                "kind": "component",
                "status": "approved",
                "implementation": {
                    "package": "agency_flutter_ui",
                    "registry_key": "unknown",
                    "symbol": "UnknownWidget",
                },
                "variants": {"standard": "standard"},
                "states": {"normal": "supported"},
                "density": {"normal": "normal"},
            },
        )
        self.assertIn(
            "binding commerce.unknown: canonical component contract not found",
            validate_flutter_bindings(root),
        )

    def test_binding_metadata_must_be_subset_of_contract(self):
        root = _contract_root()
        _write_component(root, variants=("standard",), states=("normal",), density=("normal",))
        _write_binding(root, component_binding(variants={"premium": "premium"}))

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.product-card: variant premium is not declared by canonical contract",
            errors,
        )

    def test_state_and_density_must_be_subset_of_contract(self):
        root = _contract_root()
        _write_component(
            root,
            variants=("standard",),
            states=("normal",),
            density=("normal",),
        )
        _write_binding(
            root,
            component_binding(
                states={"blocked": "supported"},
                density={"spacious": "airy"},
            ),
        )

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.product-card: state blocked is not declared by canonical contract",
            errors,
        )
        self.assertIn(
            "binding commerce.product-card: density spacious is not declared by canonical contract",
            errors,
        )

    def test_approved_binding_requires_approved_contract(self):
        root = _contract_root()
        _write_component(root, status="experimental")
        _write_binding(root, component_binding())

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.product-card: approved binding requires an approved canonical "
            "component contract",
            errors,
        )

    def test_binding_kind_must_match_catalog(self):
        root = _contract_root()
        _write_component(root)
        _write_binding(root, component_binding(kind="pattern"))

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.product-card: kind 'pattern' does not match canonical "
            "component catalog",
            errors,
        )

    def test_duplicate_canonical_ids_are_rejected(self):
        root = _contract_root()
        _write_component(root)
        _write_binding(root, component_binding())
        directory = root / "design-contract" / "bindings" / "flutter"
        (directory / "duplicate.yaml").write_text(
            yaml.safe_dump(component_binding()), encoding="utf-8"
        )

        errors = validate_flutter_bindings(root)

        self.assertTrue(any("duplicate binding id 'commerce.product-card'" in e for e in errors))

    def test_duplicate_pattern_registry_targets_are_rejected(self):
        root = _contract_root()
        _write_pattern(root, "commerce.cart")
        _write_pattern(root, "commerce.reorder")
        _write_binding(root, pattern_binding("commerce.cart"))
        reorder = pattern_binding("commerce.reorder")
        reorder["implementation"]["registry_key"] = "cart"
        _write_binding(root, reorder)

        errors = validate_flutter_bindings(root)

        self.assertTrue(
            any("collides with binding commerce.cart" in e for e in errors), errors
        )

    def test_duplicate_component_registry_targets_are_rejected(self):
        root = _contract_root()
        _write_component(root, "commerce.product-card")
        _write_component(root, "commerce.quote-card")
        _write_binding(root, component_binding("commerce.product-card"))
        quote = component_binding("commerce.quote-card")
        quote["implementation"]["registry_key"] = "product-card"
        quote["implementation"]["symbol"] = "QuoteCard"
        _write_binding(root, quote)

        errors = validate_flutter_bindings(root)

        self.assertTrue(
            any("collides with binding commerce.product-card" in e for e in errors), errors
        )

    def test_pattern_bindings_must_not_declare_variants_or_states(self):
        root = _contract_root()
        _write_pattern(root, "commerce.cart")
        _write_binding(
            root,
            pattern_binding("commerce.cart", variants={"x": "y"}, states={"z": "supported"}),
        )

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.cart: pattern bindings must not declare variants", errors
        )
        self.assertIn(
            "binding commerce.cart: pattern bindings must not declare states", errors
        )

    def test_requires_unknown_component_is_rejected(self):
        root = _contract_root()
        _write_component(root, requires=("commerce.missing",))
        _write_binding(root, component_binding())

        errors = validate_flutter_bindings(root)

        self.assertTrue(
            any(
                "binding commerce.product-card: required component "
                "'commerce.missing' has no approved canonical contract" in e
                for e in errors
            ),
            errors,
        )

    def test_errors_are_stably_sorted(self):
        root = _contract_root()
        _write_binding(root, component_binding("commerce.zzz"))
        _write_binding(root, component_binding("commerce.aaa"))

        errors = validate_flutter_bindings(root)

        self.assertEqual(sorted(errors), errors)
        self.assertTrue(errors)

    def test_cross_catalog_duplicate_id_is_rejected(self):
        root = _contract_root()
        _write_component(root, "commerce.duplicated")
        _write_pattern(root, "commerce.duplicated")
        _write_binding(root, component_binding("commerce.duplicated"))

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.duplicated: canonical id is declared in both component "
            "and pattern catalogs",
            errors,
        )

    def test_malformed_canonical_list_is_treated_as_empty(self):
        root = _contract_root()
        directory = root / "design-contract" / "components"
        directory.mkdir(parents=True)
        (directory / "commerce-product-card.yaml").write_text(
            yaml.safe_dump(
                {
                    "id": "commerce.product-card",
                    "name": "ProductCard",
                    "status": "approved",
                    "variants": "standard",
                    "states": [],
                    "density": [],
                },
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        _write_binding(root, component_binding(variants={"standard": "standard"}))

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.product-card: variant standard is not declared by "
            "canonical contract",
            errors,
        )

    def test_malformed_canonical_yaml_returns_error_without_raising(self):
        root = _contract_root()
        directory = root / "design-contract" / "components"
        directory.mkdir(parents=True)
        (directory / "broken.yaml").write_text("{ invalid: [", encoding="utf-8")

        errors = validate_flutter_bindings(root)

        self.assertTrue(
            any(error.startswith("cannot load design contract under") for error in errors),
            errors,
        )

    def test_structural_schema_rejects_missing_implementation(self):
        root = _contract_root()
        _write_component(root)
        binding = component_binding()
        del binding["implementation"]
        _write_binding(root, binding)

        errors = validate_flutter_bindings(root)

        self.assertTrue(any("implementation" in error for error in errors), errors)

    def test_load_flutter_bindings_returns_records_by_id(self):
        root = _contract_root()
        _write_component(root)
        _write_binding(root, component_binding())

        bindings = load_flutter_bindings(root)

        self.assertIn("commerce.product-card", bindings)
        self.assertEqual("component", bindings["commerce.product-card"]["kind"])

    def test_component_density_map_must_be_total(self):
        root = _contract_root()
        _write_component(
            root,
            variants=("standard",),
            states=("normal",),
            density=("compact", "normal", "spacious"),
        )
        _write_binding(
            root,
            component_binding(density={"compact": "dense", "normal": "balanced"}),
        )

        errors = validate_flutter_bindings(root)

        self.assertIn(
            "binding commerce.product-card: density map must cover all canonical "
            "densities; missing spacious",
            errors,
        )

    def test_repository_binding_catalog_is_valid(self):
        self.assertEqual([], validate_flutter_bindings(ROOT))

    def test_every_repository_pattern_has_an_approved_binding(self):
        bindings = load_flutter_bindings(ROOT)
        canonical_patterns = set(build_indexes(ROOT)["patterns"])
        bound_patterns = {
            binding_id
            for binding_id, binding in bindings.items()
            if binding.get("kind") == "pattern" and binding.get("status") == "approved"
        }

        self.assertTrue(canonical_patterns)
        self.assertEqual(sorted(canonical_patterns - bound_patterns), [])

    def test_binding_symbols_exist_in_flutter_source(self):
        source = _flutter_source()
        for binding_id, binding in sorted(load_flutter_bindings(ROOT).items()):
            symbol = binding["implementation"]["symbol"]
            with self.subTest(binding=binding_id):
                self.assertIn(f"class {symbol}", source)

    def test_pattern_binding_registry_keys_exist_in_pattern_registry(self):
        registry_source = (
            FLUTTER_LIB / "patterns" / "pattern_registry.dart"
        ).read_text(encoding="utf-8")
        for binding_id, binding in sorted(load_flutter_bindings(ROOT).items()):
            if binding.get("kind") != "pattern":
                continue
            registry_key = binding["implementation"]["registry_key"]
            with self.subTest(binding=binding_id):
                self.assertIn(f"'{registry_key}':", registry_source)

    def test_current_runtime_directions_have_complete_approved_bindings(self):
        bindings = load_flutter_bindings(ROOT)
        runtime_dir = (
            ROOT
            / "client-projects"
            / "examples"
            / "prototype-demo"
            / "prototype"
            / "runtime"
        )
        paths = sorted(runtime_dir.glob("direction-*.json"))
        self.assertTrue(paths)

        errors = []
        for path in paths:
            direction = json.loads(path.read_text(encoding="utf-8"))
            errors.extend(runtime_binding_errors(ROOT, direction, bindings))

        self.assertEqual([], sorted(errors))


class RuntimeBindingErrorTests(unittest.TestCase):
    def _approved_component_root(self) -> Path:
        root = _contract_root()
        _write_component(
            root,
            "commerce.product-card",
            variants=("standard", "b2b"),
            states=("normal",),
            density=("compact", "normal"),
        )
        _write_binding(
            root,
            component_binding(
                variants={"standard": "standard", "b2b": "b2b"},
                density={"compact": "dense", "normal": "balanced"},
            ),
        )
        return root

    def _direction(self, **overrides) -> dict:
        direction = {
            "patterns": [],
            "components": ["commerce.product-card"],
            "component_variants": [],
            "density": "normal",
        }
        direction.update(overrides)
        return direction

    def test_runtime_direction_without_binding_is_rejected(self):
        root = _contract_root()
        _write_component(root, "commerce.product-card")

        errors = runtime_binding_errors(root, self._direction())

        self.assertTrue(
            any(
                "components.0 references canonical component 'commerce.product-card' "
                "without an approved Flutter binding" in error
                for error in errors
            ),
            errors,
        )

    def test_runtime_direction_with_approved_binding_passes(self):
        root = self._approved_component_root()

        self.assertEqual([], runtime_binding_errors(root, self._direction()))

    def test_runtime_direction_unsupported_variant_is_rejected(self):
        root = self._approved_component_root()
        direction = self._direction(
            component_variants=[
                {"component": "commerce.product-card", "variant": "premium"}
            ]
        )

        errors = runtime_binding_errors(root, direction)

        self.assertTrue(
            any(
                "component_variants.0 variant 'premium' for 'commerce.product-card' "
                "is not supported by the Flutter binding" in error
                for error in errors
            ),
            errors,
        )

    def test_runtime_direction_unsupported_density_is_rejected(self):
        root = self._approved_component_root()
        direction = self._direction(density="spacious")

        errors = runtime_binding_errors(root, direction)

        self.assertTrue(
            any(
                "components.0 canonical component 'commerce.product-card' binding does "
                "not support density 'spacious'" in error
                for error in errors
            ),
            errors,
        )

    def test_runtime_component_variant_requires_component_binding(self):
        root = _contract_root()
        _write_pattern(root, "commerce.cart")
        _write_binding(root, pattern_binding("commerce.cart"))
        direction = self._direction(
            components=[],
            component_variants=[{"component": "commerce.cart", "variant": "standard"}],
        )

        errors = runtime_binding_errors(root, direction)

        self.assertTrue(
            any(
                "component_variants.0 canonical id 'commerce.cart' is bound as "
                "'pattern', not a component" in error
                for error in errors
            ),
            errors,
        )

    def test_runtime_direction_unknown_pattern_is_rejected(self):
        root = _contract_root()
        _write_pattern(root, "commerce.cart")
        direction = self._direction(patterns=["commerce.cart"], components=[])

        errors = runtime_binding_errors(root, direction)

        self.assertTrue(
            any(
                "patterns.0 references canonical pattern 'commerce.cart' without an "
                "approved Flutter binding" in error
                for error in errors
            ),
            errors,
        )


class GeneratedProjectionTests(unittest.TestCase):
    def test_generated_dart_projection_is_deterministic(self):
        first = render_flutter_bindings(ROOT)
        second = render_flutter_bindings(ROOT)

        self.assertEqual(first, second)
        self.assertTrue(first.endswith("\n"))

    def test_generated_dart_projection_has_required_header(self):
        source = render_flutter_bindings(ROOT)

        self.assertTrue(source.startswith("// GENERATED FILE. DO NOT EDIT."))
        self.assertIn("// Source: design-contract/bindings/flutter/*.yaml", source)

    def test_generated_dart_projection_is_sorted_and_complete(self):
        source = render_flutter_bindings(ROOT)
        approved = sorted(
            binding_id
            for binding_id, binding in load_flutter_bindings(ROOT).items()
            if binding.get("status") == "approved"
        )

        positions = [source.index(f"'{binding_id}': DesignBinding(") for binding_id in approved]

        self.assertEqual(positions, sorted(positions))
        self.assertEqual(len(positions), len(approved))

    def test_checked_projection_matches_fresh_generation(self):
        self.assertEqual([], check_flutter_bindings_fresh(ROOT))

    def test_stale_projection_is_reported(self):
        root = _contract_root()
        _write_component(root)
        _write_binding(root, component_binding())
        generated = write_flutter_bindings(root)
        generated.write_text("// stale\n", encoding="utf-8")

        errors = check_flutter_bindings_fresh(root)

        self.assertTrue(any("stale" in error for error in errors), errors)

    def test_missing_projection_is_reported(self):
        root = _contract_root()
        _write_component(root)
        _write_binding(root, component_binding())

        errors = check_flutter_bindings_fresh(root)

        self.assertTrue(any("missing" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
