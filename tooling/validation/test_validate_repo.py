from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = Path(__file__).with_name("validate_repo.py")
STEP2_CONTROL_FILES = (
    "REFERENCE_POLICY.md",
    "DESIGN_SYSTEM.md",
    "VISUAL_QA.md",
    "PENPOT_MAPPING.md",
)


class ValidatorContractTests(unittest.TestCase):
    def load_validator(self):
        spec = importlib.util.spec_from_file_location("validate_repo", VALIDATOR_PATH)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_current_repository_has_no_missing_required_paths(self):
        validator = self.load_validator()
        self.assertEqual([], validator.missing_required_paths(ROOT))

    def test_missing_required_path_is_reported(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            missing = validator.missing_required_paths(Path(tmp))
        self.assertIn("AGENTS.md", missing)
        self.assertIn("design-contract/tokens", missing)

    def test_step2_control_files_are_required(self):
        validator = self.load_validator()
        for path in STEP2_CONTROL_FILES:
            self.assertIn(path, validator.REQUIRED_PATHS)


if __name__ == "__main__":
    unittest.main()
