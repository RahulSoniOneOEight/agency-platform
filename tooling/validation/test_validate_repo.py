from __future__ import annotations

import importlib.util
import json
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

    def test_client_input_contract_paths_are_required(self):
        validator = self.load_validator()
        self.assertIn("client-projects/schema/client-profile.schema.json", validator.REQUIRED_PATHS)
        self.assertIn("client-projects/schema/input/client-input.schema.json", validator.REQUIRED_PATHS)
        self.assertIn("tooling/workflow/client_input.py", validator.REQUIRED_PATHS)

    def test_b1b_runtime_paths_are_required(self):
        validator = self.load_validator()
        for path in (
            "tooling/prototype/build_runtime_bundle.py",
            "tooling/prototype/validate_runtime_bundle.py",
            "tooling/validation/test_runtime_bundle.py",
            "apps/prototype_app/lib/runtime/runtime_loader.dart",
        ):
            self.assertIn(path, validator.REQUIRED_PATHS)

    def test_current_repository_generated_runtime_bundles_are_fresh(self):
        validator = self.load_validator()
        self.assertEqual([], validator.generated_runtime_bundle_errors(ROOT))

    def test_missing_generated_runtime_bundle_is_reported(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects" / "demo" / "prototype").mkdir(parents=True)
            (
                root
                / "client-projects"
                / "demo"
                / "prototype"
                / "prototype-manifest.yaml"
            ).write_text("client_id: demo\n", encoding="utf-8")

            errors = validator.generated_runtime_bundle_errors(root)

        self.assertTrue(
            any("missing generated runtime bundle" in error for error in errors), errors
        )

    def test_invalid_generated_runtime_bundle_is_reported(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects" / "demo" / "prototype").mkdir(parents=True)
            (
                root
                / "client-projects"
                / "demo"
                / "prototype"
                / "prototype-manifest.yaml"
            ).write_text("client_id: demo\n", encoding="utf-8")
            generated = root / "apps" / "prototype_app" / "assets" / "generated"
            generated.mkdir(parents=True)
            (generated / "demo.json").write_text("{}\n", encoding="utf-8")

            errors = validator.generated_runtime_bundle_errors(root)

        self.assertTrue(any("demo.json" in error for error in errors), errors)

    def test_stale_generated_runtime_bundle_is_reported(self):
        from tooling.prototype.build_prototype import compose_prototype
        from tooling.validation.test_prototype_platform import _write_client

        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _write_client(root, ["a", "b"])
            compose_prototype(root, client)
            bundle_path = (
                root / "apps" / "prototype_app" / "assets" / "generated" / "acme.json"
            )
            self.assertTrue(bundle_path.exists())
            bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
            bundle["default_direction"] = "b"
            bundle_path.write_text(
                json.dumps(bundle, indent=2, sort_keys=True) + "\n", encoding="utf-8"
            )

            errors = validator.generated_runtime_bundle_errors(root)

        self.assertTrue(any("stale" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
