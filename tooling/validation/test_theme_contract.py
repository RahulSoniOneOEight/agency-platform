from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.design_contract.theme_contract import (
    load_foundation_tokens,
    load_semantic_tokens,
    validate_token_catalogs,
)


ROOT = Path(__file__).resolve().parents[2]
_TOKENS = ROOT / "design-contract" / "tokens"

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


def _has_error(errors: list[str], needle: str) -> bool:
    return any(needle in error for error in errors)


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


if __name__ == "__main__":
    unittest.main()
