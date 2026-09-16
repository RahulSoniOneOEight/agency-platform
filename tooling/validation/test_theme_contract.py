from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.design_contract.theme_contract import (
    CANONICAL_GROUPS,
    brand_to_semantic_overrides,
    load_foundation_tokens,
    load_semantic_tokens,
    load_theme_presets,
    resolve_theme,
    validate_client_brand_visual,
    validate_direction_theme_overrides,
    validate_theme_presets,
    validate_token_catalogs,
)


ROOT = Path(__file__).resolve().parents[2]
_TOKENS = ROOT / "design-contract" / "tokens"
_THEMES = ROOT / "design-contract" / "themes"

_TEMP_DIRECTORIES: list[tempfile.TemporaryDirectory] = []


def tearDownModule() -> None:
    for handle in _TEMP_DIRECTORIES:
        handle.cleanup()
    _TEMP_DIRECTORIES.clear()


def _real_catalog(name: str) -> dict:
    return yaml.safe_load((_TOKENS / name).read_text(encoding="utf-8"))


def _fixture_root() -> Path:
    handle = tempfile.TemporaryDirectory()
    _TEMP_DIRECTORIES.append(handle)
    return Path(handle.name)


def _write(root: Path, name: str, document) -> None:
    directory = root / "design-contract" / "tokens"
    directory.mkdir(parents=True, exist_ok=True)
    if isinstance(document, str):
        (directory / name).write_text(document, encoding="utf-8")
    else:
        (directory / name).write_text(
            yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
        )


def _root_with(foundation=None, semantic=None) -> Path:
    root = _fixture_root()
    foundation = (
        copy.deepcopy(_real_catalog("foundation.yaml")) if foundation is None else foundation
    )
    semantic = (
        copy.deepcopy(_real_catalog("semantic.yaml")) if semantic is None else semantic
    )
    _write(root, "foundation.yaml", foundation)
    _write(root, "semantic.yaml", semantic)
    return root


def _write_preset(root: Path, name: str, document) -> None:
    directory = root / "design-contract" / "themes"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / name).write_text(
        yaml.safe_dump(document, sort_keys=False), encoding="utf-8"
    )


def _has_error(errors: list[str], needle: str) -> bool:
    return any(needle in error for error in errors)


def _real_preset(name: str) -> dict:
    return yaml.safe_load((_THEMES / name).read_text(encoding="utf-8"))


def _write_preset(root: Path, name: str, document) -> None:
    directory = root / "design-contract" / "themes"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / name
    if isinstance(document, str):
        path.write_text(document, encoding="utf-8")
    else:
        path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")


def _root_with_presets(presets, foundation=None, semantic=None) -> Path:
    root = _root_with(foundation=foundation, semantic=semantic)
    for name, document in presets.items():
        _write_preset(root, name, document)
    return root


def _approved_preset(preset_id: str = "test-preset", overrides=None) -> dict:
    return {
        "id": preset_id,
        "status": "approved",
        "semantic_overrides": {} if overrides is None else overrides,
    }


def _reverse(value):
    if isinstance(value, dict):
        return {key: _reverse(value[key]) for key in reversed(list(value))}
    if isinstance(value, list):
        return [_reverse(item) for item in value]
    return value


def _walk_strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from _walk_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _walk_strings(item)
    elif isinstance(value, str):
        yield value


class CatalogLoadingTests(unittest.TestCase):
    def test_valid_foundation_and_semantic_catalogs_load(self):
        foundation = load_foundation_tokens(ROOT)
        semantic = load_semantic_tokens(ROOT)

        self.assertEqual(foundation["version"], 1)
        self.assertIn("color", semantic)
        self.assertEqual(validate_token_catalogs(ROOT), [])

    def test_numeric_yaml_keys_are_normalized_to_strings(self):
        root = _fixture_root()
        _write(root, "foundation.yaml", "version: 1\nspacing:\n  1: 4\n  2: 8\n")
        _write(root, "semantic.yaml", "version: 1\n")

        foundation = load_foundation_tokens(root)

        self.assertIn("1", foundation["spacing"])
        self.assertNotIn(1, foundation["spacing"])
        self.assertEqual(foundation["spacing"]["2"], 8)

    def test_missing_catalog_raises_value_error(self):
        root = _fixture_root()

        with self.assertRaises(ValueError):
            load_foundation_tokens(root)
        with self.assertRaises(ValueError):
            load_semantic_tokens(root)

    def test_non_mapping_catalog_raises_value_error(self):
        root = _fixture_root()
        _write(root, "foundation.yaml", "- 1\n- 2\n")
        _write(root, "semantic.yaml", "version: 1\n")

        with self.assertRaises(ValueError):
            load_foundation_tokens(root)

    def test_invalid_yaml_raises_value_error(self):
        root = _fixture_root()
        _write(root, "foundation.yaml", "{ invalid: [")
        _write(root, "semantic.yaml", "version: 1\n")

        with self.assertRaises(ValueError):
            load_foundation_tokens(root)

    def test_validate_never_raises_on_garbage_catalogs(self):
        root = _fixture_root()
        _write(root, "foundation.yaml", "{ invalid: [")
        _write(root, "semantic.yaml", "- not-a-mapping\n")

        errors = validate_token_catalogs(root)

        self.assertIsInstance(errors, list)
        self.assertTrue(errors)


class FoundationValidationTests(unittest.TestCase):
    def test_valid_fixture_root_has_no_errors(self):
        self.assertEqual(validate_token_catalogs(_root_with()), [])

    def test_version_must_equal_one(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["version"] = 2

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.version"), errors)

    def test_unknown_top_level_group_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["mystery"] = {}

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation: unknown top-level group 'mystery'"), errors)

    def test_missing_top_level_group_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        del foundation["breakpoints"]

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(
            _has_error(errors, "foundation: missing required top-level group 'breakpoints'"),
            errors,
        )

    def test_malformed_group_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["spacing"] = 4

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.spacing: expected a mapping"), errors)

    def test_invalid_color_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["color"]["neutral"]["500"] = "#GG0000"

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.color.neutral.500"), errors)

    def test_non_finite_number_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["spacing"]["1"] = float("inf")

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.spacing.1"), errors)

    def test_negative_dimension_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["radius"]["md"] = -1

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.radius.md"), errors)

    def test_non_positive_density_multiplier_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["density"]["multiplier"]["compact"] = 0

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.density.multiplier.compact"), errors)

    def test_unknown_density_multiplier_key_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["density"]["multiplier"]["huge"] = 2.0

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.density.multiplier.huge"), errors)


class SemanticValidationTests(unittest.TestCase):
    def test_unknown_semantic_key_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["mystery"] = "{foundation.color.blue.600}"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.color"), errors)
        self.assertTrue(_has_error(errors, "mystery"), errors)

    def test_missing_required_semantic_key_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        del semantic["color"]["border"]

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.color: missing required key 'border'"), errors)

    def test_missing_required_semantic_group_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        del semantic["breakpoints"]

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(
            _has_error(errors, "semantic: missing required top-level group 'breakpoints'"),
            errors,
        )

    def test_unknown_semantic_group_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["mystery"] = {}

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic: unknown top-level group 'mystery'"), errors)

    def test_complete_reference_syntax_is_accepted(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "{foundation.color.blue.600}"
        semantic["spacing"]["inline"] = "{foundation.spacing.2}"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertEqual(errors, [])

    def test_partial_reference_syntax_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "{foundation.color.blue.600"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.color.primary"), errors)

    def test_interpolated_reference_syntax_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "brand {foundation.color.blue.600}"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.color.primary"), errors)

    def test_density_default_outside_canonical_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["density"]["default"] = "huge"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.density.default"), errors)

    def test_literal_non_reference_strings_are_allowed(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["typography"]["font_family"] = "Inter"
        semantic["motion"]["easing"] = "ease-out"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertEqual(errors, [])

    def test_invalid_semantic_literal_color_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "not-a-color"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.color.primary"), errors)


class StrictnessTests(unittest.TestCase):
    def test_boolean_version_is_rejected(self):
        foundation = {**_real_catalog("foundation.yaml"), "version": True}

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.version: must equal 1"), errors)

    def test_empty_foundation_group_is_rejected(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["spacing"] = {}

        errors = validate_token_catalogs(_root_with(foundation=foundation))

        self.assertTrue(_has_error(errors, "foundation.spacing: must not be empty"), errors)

    def test_empty_semantic_group_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["radius"] = {}

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.radius: must not be empty"), errors)

    def test_plain_string_in_numeric_semantic_group_is_rejected(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["spacing"]["inline"] = "hello"

        errors = validate_token_catalogs(_root_with(semantic=semantic))

        self.assertTrue(_has_error(errors, "semantic.spacing.inline"), errors)


class TypeStrictnessTests(unittest.TestCase):
    def test_preset_type_changing_numeric_leaf_is_rejected(self):
        root = _root_with()
        _write_preset(
            root,
            "bad.yaml",
            {
                "id": "bad",
                "status": "approved",
                "semantic_overrides": {"typography": {"display": "big"}},
            },
        )

        with self.assertRaises(ValueError):
            resolve_theme(root, "bad")

    def test_direction_type_changing_motion_leaf_is_rejected(self):
        root = _root_with()
        _write_preset(
            root,
            "ok.yaml",
            {"id": "ok", "status": "approved", "semantic_overrides": {}},
        )

        with self.assertRaises(ValueError):
            resolve_theme(root, "ok", None, {"motion": {"fast_ms": "soon"}})

    def test_brand_font_family_must_be_a_string(self):
        root = _root_with()
        _write_preset(
            root,
            "ok.yaml",
            {"id": "ok", "status": "approved", "semantic_overrides": {}},
        )

        with self.assertRaises(ValueError):
            resolve_theme(root, "ok", {"font_family": 8})

    def test_preset_unknown_top_level_key_is_rejected(self):
        root = _root_with()
        _write_preset(
            root,
            "bad.yaml",
            {
                "id": "bad",
                "status": "approved",
                "semantic_overrides": {},
                "extra": 1,
            },
        )

        errors = validate_theme_presets(root)

        self.assertTrue(_has_error(errors, "unknown key 'extra'"), errors)

    def test_duplicate_preset_id_is_rejected(self):
        root = _root_with()
        _write_preset(
            root,
            "a.yaml",
            {"id": "dup", "status": "approved", "semantic_overrides": {}},
        )
        _write_preset(
            root,
            "b.yaml",
            {"id": "dup", "status": "approved", "semantic_overrides": {}},
        )

        with self.assertRaises(ValueError):
            load_theme_presets(root)
        self.assertTrue(
            _has_error(validate_theme_presets(root), "duplicate id"), 
            validate_theme_presets(root),
        )


class DirectionAndBrandOverrideTests(unittest.TestCase):
    def _root_with_preset(self, name: str = "premium-modern") -> Path:
        root = _root_with()
        _write_preset(
            root,
            f"{name}.yaml",
            {"id": name, "status": "approved", "semantic_overrides": {}},
        )
        return root

    def test_allowed_direction_overrides_apply(self):
        root = self._root_with_preset()

        theme = resolve_theme(
            root,
            "premium-modern",
            None,
            {
                "spacing": {"section": "{foundation.spacing.6}"},
                "radius": {"card": "{foundation.radius.md}"},
                "typography": {"heading_emphasis": "strong"},
            },
        )

        self.assertEqual(24, theme["spacing"]["section"])
        self.assertEqual(12, theme["radius"]["card"])
        self.assertEqual("strong", theme["typography"]["heading_emphasis"])

    def test_disallowed_direction_paths_are_rejected(self):
        root = self._root_with_preset()
        cases = (
            {"color": {"primary": "#000000"}},
            {"ProductCard": {"padding": 8}},
            {"widgets": {"search": {"radius": 4}}},
            {"density": {"default": "compact"}},
            {"motion": {"fast_ms": 100}},
        )

        for overrides in cases:
            with self.subTest(overrides=overrides):
                with self.assertRaises(ValueError):
                    resolve_theme(root, "premium-modern", None, overrides)

    def test_direction_override_validator_reports_allowlist(self):
        group_errors = validate_direction_theme_overrides(
            {"color": {"primary": "#000000"}}
        )
        self.assertTrue(
            _has_error(group_errors, "not an approved override group"), group_errors
        )

        key_errors = validate_direction_theme_overrides({"spacing": {"nope": 1}})
        self.assertTrue(
            _has_error(key_errors, "not an approved override path"), key_errors
        )
        self.assertEqual(sorted(key_errors), key_errors)

    def test_brand_visual_validation(self):
        self.assertEqual(
            [],
            validate_client_brand_visual(
                {
                    "primary_color": "#1155CC",
                    "font_family": "Inter",
                    "visual_character": "soft",
                }
            ),
        )
        self.assertTrue(
            _has_error(validate_client_brand_visual({"nope": 1}), "unknown key")
        )
        self.assertTrue(
            _has_error(
                validate_client_brand_visual({"primary_color": "red"}), "invalid color"
            )
        )
        self.assertTrue(
            _has_error(
                validate_client_brand_visual({"visual_character": "loud"}),
                "visual_character",
            )
        )

    def test_validators_never_raise_on_mixed_keys(self):
        self.assertIsInstance(validate_client_brand_visual({1: "a", "b": 2}), list)
        self.assertIsInstance(
            validate_direction_theme_overrides({1: {}, "spacing": {}}), list
        )

    def test_empty_disallowed_direction_group_is_rejected(self):
        for group in ("color", "motion", "density", "ProductCard"):
            with self.subTest(group=group):
                self.assertTrue(validate_direction_theme_overrides({group: {}}), group)

    def test_brand_visual_preset_is_tolerated(self):
        self.assertEqual(
            [],
            validate_client_brand_visual(
                {"preset": "premium-modern", "primary_color": "#1155CC"}
            ),
        )

    def test_unknown_brand_key_is_rejected_by_resolve_theme(self):
        root = self._root_with_preset()

        with self.assertRaises(ValueError):
            resolve_theme(root, "premium-modern", {"primary-colour": "#000000"})

    def test_brand_beats_preset_and_direction_beats_brand(self):
        root = _root_with()
        _write_preset(
            root,
            "preset.yaml",
            {
                "id": "preset",
                "status": "approved",
                "semantic_overrides": {"spacing": {"section": "{foundation.spacing.10}"}},
            },
        )

        brand = resolve_theme(root, "preset", {"primary_color": "#1155CC"})
        self.assertEqual("#1155CC", brand["color"]["primary"])

        with_direction = resolve_theme(
            root,
            "preset",
            {"primary_color": "#1155CC"},
            {"spacing": {"section": "{foundation.spacing.4}"}},
        )
        self.assertEqual(16, with_direction["spacing"]["section"])


class DeterminismTests(unittest.TestCase):
    def test_errors_are_sorted_and_unique(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["spacing"]["1"] = -4
        foundation["radius"]["md"] = float("nan")
        foundation["mystery"] = {}
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "{foundation.color.blue.600"
        del semantic["motion"]["easing"]

        errors = validate_token_catalogs(_root_with(foundation=foundation, semantic=semantic))

        self.assertTrue(errors)
        self.assertEqual(errors, sorted(errors))
        self.assertEqual(errors, sorted(set(errors)))

    def test_error_ordering_is_stable_under_insertion_order(self):
        def build(reverse: bool) -> list[str]:
            foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
            foundation["spacing"]["1"] = -4
            foundation["radius"]["md"] = -1
            if reverse:
                foundation = {
                    key: (
                        dict(reversed(list(value.items())))
                        if isinstance(value, dict)
                        else value
                    )
                    for key, value in reversed(list(foundation.items()))
                }
            return validate_token_catalogs(_root_with(foundation=foundation))

        self.assertEqual(build(False), build(True))


class ThemePresetLoadingTests(unittest.TestCase):
    def test_repo_presets_load_and_validate(self):
        presets = load_theme_presets(ROOT)

        self.assertEqual(
            sorted(presets),
            ["compact-commerce", "editorial-commerce", "premium-modern"],
        )
        self.assertEqual(presets["premium-modern"]["status"], "approved")
        self.assertEqual(validate_theme_presets(ROOT), [])

    def test_validate_reports_non_mapping_document(self):
        root = _root_with_presets({"broken.yaml": "- 1\n"})

        errors = validate_theme_presets(root)

        self.assertTrue(_has_error(errors, "expected a mapping"), errors)

    def test_validate_reports_missing_id(self):
        root = _root_with_presets(
            {"missing.yaml": {"status": "approved", "semantic_overrides": {}}}
        )

        errors = validate_theme_presets(root)

        self.assertTrue(_has_error(errors, "missing or empty id"), errors)

    def test_validate_reports_duplicate_id(self):
        root = _root_with_presets(
            {"a.yaml": _approved_preset("dup"), "b.yaml": _approved_preset("dup")}
        )

        errors = validate_theme_presets(root)

        self.assertTrue(_has_error(errors, "duplicate id 'dup'"), errors)

    def test_validate_reports_invalid_status(self):
        preset = _approved_preset()
        preset["status"] = "blessed"
        root = _root_with_presets({"p.yaml": preset})

        errors = validate_theme_presets(root)

        self.assertTrue(_has_error(errors, "invalid status"), errors)

    def test_validate_reports_missing_semantic_overrides(self):
        root = _root_with_presets({"p.yaml": {"id": "p", "status": "approved"}})

        errors = validate_theme_presets(root)

        self.assertTrue(_has_error(errors, "missing semantic_overrides"), errors)

    def test_validate_reports_invalid_override_paths(self):
        preset = _approved_preset("p", {"ProductCard": {"padding": 8}})
        root = _root_with_presets({"p.yaml": preset})

        errors = validate_theme_presets(root)

        self.assertTrue(
            _has_error(errors, "unknown override group 'ProductCard'"), errors
        )

    def test_preset_errors_are_sorted_and_unique(self):
        preset = _approved_preset("p", {"color": {"nope": "#fff"}, "ProductCard": {}})
        preset["status"] = "nope"
        root = _root_with_presets({"p.yaml": preset})

        errors = validate_theme_presets(root)

        self.assertTrue(errors)
        self.assertEqual(errors, sorted(errors))
        self.assertEqual(errors, sorted(set(errors)))


class ThemeResolutionTests(unittest.TestCase):
    def test_resolves_brand_and_eliminates_references(self):
        theme = resolve_theme(ROOT, "premium-modern", {"primary_color": "#1155CC"}, None)

        self.assertEqual(theme["version"], 1)
        self.assertEqual(theme["color"]["primary"], "#1155CC")
        self.assertEqual(sorted(theme), sorted(("version",) + CANONICAL_GROUPS))
        for group in CANONICAL_GROUPS:
            self.assertIn(group, theme)
        self.assertFalse(
            [value for value in _walk_strings(theme) if "{foundation." in value]
        )

    def test_precedence_preset_brand_direction(self):
        overrides = {
            "color": {"primary": "{foundation.color.blue.500}"},
            "spacing": {"section": "{foundation.spacing.6}"},
        }
        root = _root_with_presets(
            {"test-preset.yaml": _approved_preset("test-preset", overrides)}
        )

        preset_only = resolve_theme(root, "test-preset")
        self.assertEqual(preset_only["color"]["primary"], "#3B6BFF")
        self.assertEqual(preset_only["spacing"]["section"], 24)

        brand = resolve_theme(root, "test-preset", {"primary_color": "#1155CC"})
        self.assertEqual(brand["color"]["primary"], "#1155CC")
        self.assertEqual(brand["spacing"]["section"], 24)

        direction = resolve_theme(
            root,
            "test-preset",
            {"primary_color": "#1155CC"},
            {"spacing": {"section": "{foundation.spacing.4}"}},
        )
        self.assertEqual(direction["color"]["primary"], "#1155CC")
        self.assertEqual(direction["spacing"]["section"], 16)

    def test_brand_to_semantic_overrides_maps_only_known_keys(self):
        self.assertEqual(
            brand_to_semantic_overrides(
                {
                    "primary_color": "#1155CC",
                    "secondary_color": "#EF8A23",
                    "font_family": "Inter",
                    "font_fallback": "Roboto",
                    "visual_character": "soft",
                }
            ),
            {
                "color": {"primary": "#1155CC", "secondary": "#EF8A23"},
                "typography": {"font_family": "Inter", "font_fallback": "Roboto"},
            },
        )
        self.assertEqual(brand_to_semantic_overrides({}), {})
        self.assertEqual(brand_to_semantic_overrides({"unknown": 1}), {})

    def test_unknown_reference_raises(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "{foundation.color.missing.500}"
        root = _root_with_presets({"p.yaml": _approved_preset("p")}, semantic=semantic)

        with self.assertRaises(ValueError) as ctx:
            resolve_theme(root, "p")

        self.assertIn("unknown token reference", str(ctx.exception))
        self.assertIn("{foundation.color.missing.500}", str(ctx.exception))

    def test_cyclic_reference_raises(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        foundation["motion"]["easing"] = "{foundation.motion.easing}"
        root = _root_with_presets(
            {"p.yaml": _approved_preset("p")}, foundation=foundation
        )

        with self.assertRaises(ValueError) as ctx:
            resolve_theme(root, "p")

        self.assertIn("cyclic token reference", str(ctx.exception))

    def test_unknown_preset_raises(self):
        with self.assertRaises(ValueError) as ctx:
            resolve_theme(ROOT, "does-not-exist")

        self.assertIn("unknown theme preset: does-not-exist", str(ctx.exception))

    def test_unapproved_preset_raises(self):
        preset = _approved_preset("draft")
        preset["status"] = "experimental"
        root = _root_with_presets({"draft.yaml": preset})

        with self.assertRaises(ValueError) as ctx:
            resolve_theme(root, "draft")

        self.assertIn("theme preset 'draft' is not approved", str(ctx.exception))

    def test_disallowed_override_paths_raise(self):
        with self.assertRaises(ValueError) as ctx:
            resolve_theme(ROOT, "premium-modern", None, {"ProductCard": {"padding": 8}})
        self.assertIn("ProductCard", str(ctx.exception))

        with self.assertRaises(ValueError) as ctx2:
            resolve_theme(ROOT, "premium-modern", None, {"color": {"nope": "#fff"}})
        self.assertIn("color", str(ctx2.exception))

        with self.assertRaises(ValueError) as ctx3:
            resolve_theme(ROOT, "premium-modern", None, {"spacing": "#fff"})
        self.assertIn("must be a mapping", str(ctx3.exception))

    def test_invalid_token_catalogs_raise(self):
        foundation = copy.deepcopy(_real_catalog("foundation.yaml"))
        del foundation["breakpoints"]
        root = _root_with_presets(
            {"p.yaml": _approved_preset("p")}, foundation=foundation
        )

        with self.assertRaises(ValueError) as ctx:
            resolve_theme(root, "p")

        self.assertIn("invalid token catalogs:", str(ctx.exception))

    def test_resolved_theme_is_revalidated(self):
        semantic = copy.deepcopy(_real_catalog("semantic.yaml"))
        semantic["color"]["primary"] = "{foundation.typography.size.body}"
        root = _root_with_presets({"p.yaml": _approved_preset("p")}, semantic=semantic)

        with self.assertRaises(ValueError) as ctx:
            resolve_theme(root, "p")

        self.assertIn("semantic.color.primary", str(ctx.exception))

    def test_output_is_independent_of_mapping_insertion_order(self):
        forward_root = _root_with_presets(
            {"premium-modern.yaml": _real_preset("premium-modern.yaml")}
        )
        reversed_root = _root_with_presets(
            {"premium-modern.yaml": _reverse(_real_preset("premium-modern.yaml"))},
            foundation=_reverse(_real_catalog("foundation.yaml")),
            semantic=_reverse(_real_catalog("semantic.yaml")),
        )

        forward = resolve_theme(
            forward_root, "premium-modern", {"primary_color": "#1155CC"}, None
        )
        reversed_result = resolve_theme(
            reversed_root, "premium-modern", {"primary_color": "#1155CC"}, None
        )

        self.assertEqual(forward, reversed_result)


if __name__ == "__main__":
    unittest.main()
