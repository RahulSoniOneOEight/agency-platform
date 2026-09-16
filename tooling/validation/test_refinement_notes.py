from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

from tooling.prototype.refinement_notes import (
    load_refinement_notes,
    validate_refinement_notes,
)


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "refinement-notes.schema.json"

ALL_CLASSIFICATIONS = (
    "semantic_token",
    "client_override",
    "direction_override",
    "reusable_candidate",
    "implementation_detail",
    "reject",
)
ALL_STATUSES = ("observed", "accepted", "reconciled", "proposed", "rejected")

VALID_NOTE = """version: 1
changes:
  - id: home-hero-height
    screen: home
    subject: hero
    change: reduce hero height
    classification: client_override
    status: reconciled
    target: theme.spacing.section
"""

_TEMP_DIRECTORIES: list[tempfile.TemporaryDirectory] = []


def tearDownModule():
    for handle in _TEMP_DIRECTORIES:
        handle.cleanup()
    _TEMP_DIRECTORIES.clear()


def _root() -> Path:
    handle = tempfile.TemporaryDirectory()
    _TEMP_DIRECTORIES.append(handle)
    return Path(handle.name)


def _write_note(root: Path, text: str) -> Path:
    path = root / "client-projects" / "demo" / "prototype" / "refinement-notes.yaml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def _write_component(root: Path, contract_id: str = "commerce.product-card") -> None:
    directory = root / "design-contract" / "components"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{contract_id.replace('.', '-')}.yaml").write_text(
        yaml.safe_dump({"id": contract_id, "name": contract_id, "status": "approved"}),
        encoding="utf-8",
    )


def _write_pattern(root: Path, contract_id: str = "commerce.cart") -> None:
    directory = root / "design-contract" / "patterns"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{contract_id.replace('.', '-')}.yaml").write_text(
        yaml.safe_dump({"id": contract_id, "name": contract_id, "status": "approved"}),
        encoding="utf-8",
    )


class SchemaContractTests(unittest.TestCase):
    def test_repository_schema_is_a_valid_draft_2020_12_schema(self):
        schema = yaml.safe_load(SCHEMA_PATH.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        self.assertFalse(schema["additionalProperties"])
        self.assertFalse(schema["properties"]["changes"]["items"]["additionalProperties"])


class ValidNotesTests(unittest.TestCase):
    def test_valid_notes_pass(self):
        root = _root()
        path = _write_note(root, VALID_NOTE)

        self.assertEqual([], validate_refinement_notes(root, path))

    def test_load_returns_mapping(self):
        root = _root()
        path = _write_note(root, VALID_NOTE)

        document = load_refinement_notes(path)

        self.assertIsInstance(document, dict)
        self.assertEqual(1, document["version"])

    def test_all_six_classifications_are_accepted(self):
        root = _root()
        changes = "\n".join(
            f"""  - id: change-{index}
    change: valid change {index}
    classification: {classification}
    status: observed"""
            for index, classification in enumerate(ALL_CLASSIFICATIONS)
        )
        path = _write_note(root, f"version: 1\nchanges:\n{changes}\n")

        self.assertEqual([], validate_refinement_notes(root, path))

    def test_all_five_statuses_are_accepted(self):
        root = _root()
        changes = "\n".join(
            f"""  - id: status-{index}
    change: valid change {index}
    classification: implementation_detail
    status: {status}"""
            for index, status in enumerate(ALL_STATUSES)
        )
        path = _write_note(root, f"version: 1\nchanges:\n{changes}\n")

        self.assertEqual([], validate_refinement_notes(root, path))

    def test_optional_metadata_fields_are_accepted(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: rich
    screen: home
    component: commerce.product-card
    pattern: commerce.cart
    subject: hero
    change: refine hero
    classification: reusable_candidate
    status: proposed
    target: design-contract
    notes: free-form note
""",
        )
        _write_component(root)
        _write_pattern(root)

        self.assertEqual([], validate_refinement_notes(root, path))


class EnumValidationTests(unittest.TestCase):
    def test_invalid_classification_and_status_are_rejected_in_deterministic_order(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: mixed
    change: adjust spacing
    classification: custom
    status: done
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertEqual(
            [
                "change 'mixed': classification: 'custom' is not one of "
                "['semantic_token', 'client_override', 'direction_override', "
                "'reusable_candidate', 'implementation_detail', 'reject']",
                "change 'mixed': status: 'done' is not one of "
                "['observed', 'accepted', 'reconciled', 'proposed', 'rejected']",
            ],
            errors,
        )


class DuplicateIdTests(unittest.TestCase):
    def test_duplicate_change_ids_report_one_error_per_duplicated_id(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: repeated
    change: first
    classification: implementation_detail
    status: observed
  - id: repeated
    change: second
    classification: implementation_detail
    status: accepted
  - id: repeated
    change: third
    classification: implementation_detail
    status: accepted
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertEqual(["change 'repeated': duplicate change id"], errors)


class CanonicalIdTests(unittest.TestCase):
    def test_unknown_component_id_is_rejected(self):
        root = _root()
        _write_component(root, "commerce.product-card")
        path = _write_note(
            root,
            """version: 1
changes:
  - id: component-change
    component: commerce.unknown
    change: tighten spacing
    classification: reusable_candidate
    status: proposed
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertIn(
            "change 'component-change': component: unknown canonical component id "
            "'commerce.unknown'",
            errors,
        )

    def test_unknown_pattern_id_is_rejected(self):
        root = _root()
        _write_pattern(root, "commerce.cart")
        path = _write_note(
            root,
            """version: 1
changes:
  - id: pattern-change
    pattern: commerce.unknown
    change: refine layout
    classification: reusable_candidate
    status: proposed
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertIn(
            "change 'pattern-change': pattern: unknown canonical pattern id "
            "'commerce.unknown'",
            errors,
        )

    def test_nowa_local_component_and_pattern_identities_are_rejected(self):
        root = _root()
        _write_component(root, "commerce.product-card")
        _write_pattern(root, "commerce.cart")
        path = _write_note(
            root,
            """version: 1
changes:
  - id: nowa-local
    component: nowa.heroCard
    pattern: nowa.heroRow
    change: rearrange only inside Nowa
    classification: reusable_candidate
    status: proposed
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertEqual(
            [
                "change 'nowa-local': component: unknown canonical component id "
                "'nowa.heroCard'",
                "change 'nowa-local': pattern: unknown canonical pattern id "
                "'nowa.heroRow'",
            ],
            errors,
        )

    def test_repository_canonical_ids_are_accepted(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: real-component
    component: commerce.product-card
    change: refine card
    classification: reusable_candidate
    status: proposed
  - id: real-pattern
    pattern: commerce.cart
    change: refine cart
    classification: reusable_candidate
    status: proposed
""",
        )

        self.assertEqual([], validate_refinement_notes(ROOT, path))


class LoadFailureTests(unittest.TestCase):
    def test_malformed_yaml_raises_value_error_and_validator_reports(self):
        root = _root()
        path = _write_note(root, "version: 1\nchanges: [")

        with self.assertRaises(ValueError) as context:
            load_refinement_notes(path)
        self.assertTrue(str(context.exception).startswith("invalid refinement notes:"))

        errors = validate_refinement_notes(root, path)

        self.assertEqual(1, len(errors))
        self.assertTrue(errors[0].startswith("invalid refinement notes:"))

    def test_non_object_top_level_is_rejected(self):
        root = _root()
        path = _write_note(root, "- just\n- a\n- list\n")

        with self.assertRaises(ValueError):
            load_refinement_notes(path)

        errors = validate_refinement_notes(root, path)

        self.assertEqual(1, len(errors))
        self.assertIn("top level must be a mapping", errors[0])

    def test_missing_file_is_reported_without_raising(self):
        root = _root()
        path = root / "client-projects" / "demo" / "prototype" / "refinement-notes.yaml"

        errors = validate_refinement_notes(root, path)

        self.assertEqual(1, len(errors))
        self.assertTrue(errors[0].startswith("invalid refinement notes:"))


class StructuralValidationTests(unittest.TestCase):
    def test_unknown_top_level_property_is_rejected(self):
        root = _root()
        path = _write_note(root, f"{VALID_NOTE}unexpected: true\n")

        errors = validate_refinement_notes(root, path)

        self.assertIn(
            "refinement notes: Additional properties are not allowed "
            "('unexpected' was unexpected)",
            errors,
        )

    def test_unknown_change_property_is_rejected(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: extra-field
    change: refine
    classification: implementation_detail
    status: observed
    unexpected: true
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertIn(
            "change 'extra-field': Additional properties are not allowed "
            "('unexpected' was unexpected)",
            errors,
        )

    def test_empty_id_is_rejected(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: ""
    change: refine
    classification: implementation_detail
    status: observed
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertTrue(
            any(error.startswith("change <unknown>: id:") for error in errors), errors
        )

    def test_missing_required_change_fields_are_rejected(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: missing-fields
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertEqual(
            [
                "change 'missing-fields': 'change' is a required property",
                "change 'missing-fields': 'classification' is a required property",
                "change 'missing-fields': 'status' is a required property",
            ],
            errors,
        )

    def test_unsupported_version_is_rejected(self):
        root = _root()
        path = _write_note(root, "version: 2\nchanges: []\n")

        errors = validate_refinement_notes(root, path)

        self.assertIn("refinement notes: version: 1 was expected", errors)


class DeterminismTests(unittest.TestCase):
    def test_error_list_is_sorted_and_unique(self):
        root = _root()
        path = _write_note(
            root,
            """version: 1
changes:
  - id: repeated
    change: first
    classification: custom
    status: done
  - id: repeated
    change: second
    classification: custom
    status: done
""",
        )

        errors = validate_refinement_notes(root, path)

        self.assertEqual(sorted(set(errors)), errors)

    def test_errors_are_insertion_order_independent(self):
        first_root = _root()
        first = _write_note(
            first_root,
            """version: 1
changes:
  - id: alpha
    change: a
    classification: custom
    status: observed
  - id: beta
    change: b
    classification: semantic_token
    status: done
""",
        )
        second_root = _root()
        second = _write_note(
            second_root,
            """changes:
  - status: done
    classification: semantic_token
    change: b
    id: beta
  - status: observed
    classification: custom
    change: a
    id: alpha
version: 1
""",
        )

        first_errors = validate_refinement_notes(first_root, first)
        second_errors = validate_refinement_notes(second_root, second)

        self.assertTrue(first_errors)
        self.assertEqual(first_errors, second_errors)
        self.assertEqual(sorted(first_errors), first_errors)
        self.assertEqual(sorted(second_errors), second_errors)

    def test_mapping_valued_type_error_is_insertion_order_independent(self):
        first_root = _root()
        first = _write_note(first_root, "version: 1\nchanges: {zzz: 1, aaa: 2}\n")
        second_root = _root()
        second = _write_note(second_root, "version: 1\nchanges: {aaa: 2, zzz: 1}\n")

        first_errors = validate_refinement_notes(first_root, first)
        second_errors = validate_refinement_notes(second_root, second)

        self.assertTrue(first_errors)
        self.assertEqual(first_errors, second_errors)


if __name__ == "__main__":
    unittest.main()
