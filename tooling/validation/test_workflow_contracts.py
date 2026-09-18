from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.workflow.contracts import (
    CONTRACTS_DIR_NAME,
    WORKFLOW_DIR_NAME,
    StageContract,
    StageContractError,
    load_all_stage_contracts,
    load_stage_contract,
    validate_stage_contracts,
)
from tooling.workflow.state import STAGES


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "workflow-stage-contract.schema.json"

REQUIRED_SECTIONS = ["PURPOSE", "READ", "PROCESS", "WRITE", "VALIDATE", "DO NOT", "NEXT"]


def _fixture(tmp: str) -> Path:
    root = Path(tmp)
    shutil.copytree(ROOT / WORKFLOW_DIR_NAME, root / WORKFLOW_DIR_NAME)
    return root


def _contract_path(root: Path, stage: str) -> Path:
    index = STAGES.index(stage) + 1
    return root / WORKFLOW_DIR_NAME / CONTRACTS_DIR_NAME / f"{index:02d}-{stage}.yaml"


def _edit_contract(root: Path, stage: str, mutate) -> None:
    path = _contract_path(root, stage)
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    mutate(data)
    path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def _schema_validator() -> "object":
    try:
        from jsonschema import Draft202012Validator
    except ImportError:  # pragma: no cover - jsonschema is an expected dependency
        raise unittest.SkipTest("jsonschema is not available")
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


class LoadStageContractTests(unittest.TestCase):
    def test_load_all_returns_the_nine_canonical_stages_in_order(self):
        contracts = load_all_stage_contracts(ROOT)
        self.assertEqual(STAGES, [contract.stage for contract in contracts])

    def test_load_stage_contract_reads_visual_qa_fields(self):
        contract = load_stage_contract(ROOT, "visual-qa")
        self.assertIsInstance(contract, StageContract)
        self.assertEqual("visual-qa", contract.stage)
        self.assertEqual(("build-prototype",), contract.requires_stages)
        self.assertEqual(("prototype/prototype-manifest.yaml",), contract.requires_artifacts)
        self.assertEqual(
            ("capture-complete", "findings-complete", "validation-complete"),
            contract.checkpoints,
        )
        self.assertEqual(("client-review",), contract.next_stages)

    def test_load_stage_contract_productionize_has_no_produces_and_points_to_release(self):
        contract = load_stage_contract(ROOT, "productionize")
        self.assertEqual(("release",), contract.next_stages)
        self.assertEqual((), contract.produces)

    def test_load_stage_contract_missing_file_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(StageContractError):
                load_stage_contract(Path(tmp), "client-intake")

    def test_contract_is_frozen(self):
        contract = load_stage_contract(ROOT, "client-intake")
        with self.assertRaises(Exception):
            contract.stage = "other"  # type: ignore[misc]


class ValidateStageContractsTests(unittest.TestCase):
    def test_real_repository_is_valid(self):
        self.assertEqual([], validate_stage_contracts(ROOT))

    def test_yaml_next_conflict_with_markdown_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _edit_contract(root, "client-intake", lambda data: data.update({"next": ["client-review"]}))
            errors = validate_stage_contracts(root)
        self.assertTrue(any("conflict" in error for error in errors), errors)

    def test_markdown_missing_validate_section_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            path = root / WORKFLOW_DIR_NAME / "05-build-prototype.md"
            text = path.read_text(encoding="utf-8").replace("## VALIDATE", "## REVIEW")
            path.write_text(text, encoding="utf-8")
            errors = validate_stage_contracts(root)
        self.assertTrue(any("VALIDATE" in error for error in errors), errors)

    def test_unknown_contract_key_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _edit_contract(root, "resource-research", lambda data: data.update({"extra_key": True}))
            errors = validate_stage_contracts(root)
        self.assertTrue(any("unknown key" in error for error in errors), errors)

    def test_requires_unknown_stage_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _edit_contract(
                root,
                "generate-directions",
                lambda data: data["requires"].update({"stages": ["bogus-stage"]}),
            )
            errors = validate_stage_contracts(root)
        self.assertTrue(any("bogus-stage" in error for error in errors), errors)

    def test_next_unknown_stage_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _edit_contract(root, "client-review", lambda data: data.update({"next": ["bogus-stage"]}))
            errors = validate_stage_contracts(root)
        self.assertTrue(any("bogus-stage" in error for error in errors), errors)

    def test_stage_field_mismatch_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _edit_contract(root, "client-review", lambda data: data.update({"stage": "productionize"}))
            errors = validate_stage_contracts(root)
        self.assertTrue(any("does not match" in error for error in errors), errors)

    def test_missing_contract_file_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _contract_path(root, "visual-qa").unlink()
            errors = validate_stage_contracts(root)
        self.assertTrue(any("missing stage contract" in error for error in errors), errors)

    def test_unexpected_contract_file_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            (root / WORKFLOW_DIR_NAME / CONTRACTS_DIR_NAME / "99-bogus.yaml").write_text(
                "stage: bogus\n", encoding="utf-8"
            )
            errors = validate_stage_contracts(root)
        self.assertTrue(any("99-bogus.yaml" in error for error in errors), errors)

    def test_errors_are_sorted_and_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _fixture(tmp)
            _edit_contract(root, "client-intake", lambda data: data.update({"next": ["client-review"]}))
            _edit_contract(root, "resource-research", lambda data: data.update({"extra_key": True}))
            _contract_path(root, "visual-qa").unlink()
            first = validate_stage_contracts(root)
            second = validate_stage_contracts(root)
        self.assertEqual(sorted(first), first)
        self.assertEqual(first, second)
        self.assertGreater(len(first), 1)


class SchemaTests(unittest.TestCase):
    def test_schema_accepts_a_canonical_contract(self):
        validator = _schema_validator()
        data = yaml.safe_load(
            (ROOT / WORKFLOW_DIR_NAME / CONTRACTS_DIR_NAME / "06-visual-qa.yaml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual([], list(validator.iter_errors(data)))

    def test_schema_rejects_unknown_key(self):
        validator = _schema_validator()
        data = yaml.safe_load(
            (ROOT / WORKFLOW_DIR_NAME / CONTRACTS_DIR_NAME / "01-client-intake.yaml").read_text(
                encoding="utf-8"
            )
        )
        data["unexpected"] = True
        self.assertTrue(list(validator.iter_errors(data)))

    def test_schema_rejects_unknown_stage_reference(self):
        validator = _schema_validator()
        data = yaml.safe_load(
            (ROOT / WORKFLOW_DIR_NAME / CONTRACTS_DIR_NAME / "01-client-intake.yaml").read_text(
                encoding="utf-8"
            )
        )
        data["next"] = ["bogus-stage"]
        self.assertTrue(list(validator.iter_errors(data)))


class ConstantsTests(unittest.TestCase):
    def test_exported_directory_names(self):
        self.assertEqual("workflows", WORKFLOW_DIR_NAME)
        self.assertEqual("contracts", CONTRACTS_DIR_NAME)


if __name__ == "__main__":
    unittest.main()
