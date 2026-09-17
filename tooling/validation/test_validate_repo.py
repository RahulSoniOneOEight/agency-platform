from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

import yaml


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

    def test_current_repository_generated_runtime_bundles_are_valid(self):
        validator = self.load_validator()
        self.assertEqual([], validator.generated_runtime_bundle_errors(ROOT))

    def test_b1d_binding_paths_are_required(self):
        validator = self.load_validator()
        for path in (
            "design-contract/schema/flutter-binding.schema.json",
            "design-contract/bindings/flutter",
            "tooling/design_contract/flutter_bindings.py",
            "tooling/design_contract/generate_flutter_bindings.py",
            "apps/prototype_app/lib/registry/generated_design_bindings.dart",
        ):
            self.assertIn(path, validator.REQUIRED_PATHS)

    def test_current_repository_flutter_bindings_are_valid(self):
        validator = self.load_validator()
        self.assertEqual([], validator.flutter_binding_errors(ROOT))

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

            errors = validator.theme_contract_errors(root)

        self.assertTrue(any("stale" in error for error in errors), errors)

    def test_current_repository_theme_contract_is_valid(self):
        validator = self.load_validator()
        self.assertEqual([], validator.theme_contract_errors(ROOT))

    def test_b1e_theme_paths_are_required(self):
        validator = self.load_validator()
        for path in (
            "design-contract/schema/foundation-tokens.schema.json",
            "design-contract/schema/semantic-tokens.schema.json",
            "design-contract/schema/theme-preset.schema.json",
            "design-contract/tokens/foundation.yaml",
            "design-contract/tokens/semantic.yaml",
            "design-contract/themes/premium-modern.yaml",
            "tooling/design_contract/theme_contract.py",
            "tooling/design_contract/generate_resolved_themes.py",
            "tooling/validation/test_theme_contract.py",
            "apps/prototype_app/lib/runtime/runtime_theme.dart",
            "packages/agency_flutter_ui/lib/themes/agency_theme_tokens.dart",
        ):
            self.assertIn(path, validator.REQUIRED_PATHS)

    def test_invalid_direction_theme_override_is_reported(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            direction_dir = root / "client-projects" / "acme" / "directions"
            direction_dir.mkdir(parents=True)
            (direction_dir / "direction-a.yaml").write_text(
                yaml.safe_dump(
                    {
                        "id": "a",
                        "theme_overrides": {"ProductCard": {"padding": 8}},
                    }
                ),
                encoding="utf-8",
            )

            errors = validator.theme_contract_errors(root)

        self.assertTrue(any("theme_overrides" in error for error in errors), errors)
        self.assertEqual(sorted(errors), errors)

    def test_current_repository_refinement_notes_are_valid(self):
        validator = self.load_validator()
        self.assertEqual([], validator.refinement_note_errors(ROOT))

    def test_b1f_paths_are_required(self):
        validator = self.load_validator()
        for path in (
            "client-projects/schema/refinement-notes.schema.json",
            "tooling/prototype/refinement_notes.py",
            "tooling/validation/test_refinement_notes.py",
        ):
            self.assertIn(path, validator.REQUIRED_PATHS)
        self.assertFalse(
            [
                path
                for path in validator.REQUIRED_PATHS
                if path.endswith("refinement-notes.yaml")
            ],
            "the optional refinement note file must never be a required path",
        )

    def test_milestone_d_visual_qa_paths_are_required(self):
        validator = self.load_validator()
        for path in (
            "tooling/visual_qa",
            "tooling/visual_qa/capture_runner.py",
            "tooling/visual_qa/qa_contracts.py",
            "tooling/visual_qa/visual_provider.py",
            "tooling/visual_qa/golden_compare.py",
            "tooling/screenshots/capture_web.mjs",
            "client-projects/schema/screenshot-manifest.schema.json",
            "client-projects/schema/qa-finding.schema.json",
            "templates/qa-finding.json",
            "tooling/validation/test_visual_qa_capture.py",
            "tooling/validation/test_visual_qa_contracts.py",
            "apps/widgetbook/test/golden/widgetbook_golden_test.dart",
            "docs/superpowers/specs/2026-09-17-milestone-d-automated-visual-qa-design.md",
            "docs/superpowers/plans/2026-09-17-milestone-d-automated-visual-qa-implementation.md",
            "docs/superpowers/ledgers/2026-09-17-milestone-d-automated-visual-qa-ledger.md",
        ):
            self.assertIn(path, validator.REQUIRED_PATHS)

    def test_milestone_e_workflow_paths_are_required(self):
        validator = self.load_validator()
        for path in (
            "tooling/workflow/contracts.py",
            "tooling/workflow/execution.py",
            "tooling/workflow/manifests.py",
            "tooling/workflow/lease.py",
            "tooling/workflow/audit.py",
            "tooling/workflow/recovery.py",
            "tooling/workflow/runner.py",
            "client-projects/schema/workflow-state.schema.json",
            "client-projects/schema/workflow-stage-contract.schema.json",
            "client-projects/schema/workflow-execution-manifest.schema.json",
            "client-projects/schema/workflow-audit-record.schema.json",
            "workflows/contracts/01-client-intake.yaml",
            "workflows/contracts/08-productionize.yaml",
            "tooling/validation/test_workflow_state_v2.py",
            "tooling/validation/test_workflow_contracts.py",
            "tooling/validation/test_workflow_manifests.py",
            "tooling/validation/test_workflow_lease.py",
            "tooling/validation/test_workflow_audit.py",
            "tooling/validation/test_workflow_idempotency.py",
            "tooling/validation/test_workflow_recovery.py",
            "tooling/validation/test_workflow_runner.py",
            "tooling/validation/test_workflow_resume_e2e.py",
            "docs/superpowers/specs/2026-09-17-milestone-e-workflow-hardening-design.md",
            "docs/superpowers/plans/2026-09-17-milestone-e-workflow-hardening-implementation.md",
            "docs/superpowers/ledgers/2026-09-17-milestone-e-workflow-hardening-ledger.md",
        ):
            self.assertIn(path, validator.REQUIRED_PATHS)
        self.assertFalse(
            [
                path
                for path in validator.REQUIRED_PATHS
                if path.startswith("client-projects/workflow/executions")
            ],
            "generated per-client execution manifests must never be required globally",
        )

    def test_main_reports_refinement_note_errors(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            note = (
                root
                / "client-projects"
                / "acme"
                / "prototype"
                / "refinement-notes.yaml"
            )
            note.parent.mkdir(parents=True)
            note.write_text(
                "version: 1\nchanges:\n  - id: x\n    change: c\n"
                "    classification: custom\n    status: done\n",
                encoding="utf-8",
            )

            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = validator.main(root)

        self.assertEqual(1, code)
        output = buffer.getvalue()
        self.assertIn("Visual refinement note errors:", output)
        self.assertIn("client-projects/acme/prototype/refinement-notes.yaml:", output)

    def test_missing_refinement_notes_is_not_an_error(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects" / "acme" / "prototype").mkdir(parents=True)

            self.assertEqual([], validator.refinement_note_errors(root))

    def test_invalid_refinement_note_is_reported_with_path(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            note = (
                root
                / "client-projects"
                / "acme"
                / "prototype"
                / "refinement-notes.yaml"
            )
            note.parent.mkdir(parents=True)
            note.write_text(
                "version: 1\nchanges:\n  - id: x\n    change: c\n"
                "    classification: custom\n    status: done\n",
                encoding="utf-8",
            )

            errors = validator.refinement_note_errors(root)

        self.assertTrue(errors)
        self.assertTrue(
            all(
                error.startswith(
                    "client-projects/acme/prototype/refinement-notes.yaml: "
                )
                for error in errors
            ),
            errors,
        )
        self.assertEqual(sorted(errors), errors)

    def test_duplicate_refinement_note_id_is_reported(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            note = (
                root
                / "client-projects"
                / "acme"
                / "prototype"
                / "refinement-notes.yaml"
            )
            note.parent.mkdir(parents=True)
            note.write_text(
                "version: 1\nchanges:\n"
                "  - id: dup\n    change: a\n    classification: reject\n    status: observed\n"
                "  - id: dup\n    change: b\n    classification: reject\n    status: observed\n",
                encoding="utf-8",
            )

            errors = validator.refinement_note_errors(root)

        self.assertTrue(any("duplicate change id" in error for error in errors), errors)

    def test_refinement_note_errors_are_ordered_by_path(self):
        validator = self.load_validator()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("zzz", "aaa"):
                note = (
                    root
                    / "client-projects"
                    / name
                    / "prototype"
                    / "refinement-notes.yaml"
                )
                note.parent.mkdir(parents=True)
                note.write_text(
                    "version: 1\nchanges:\n  - id: x\n    change: c\n"
                    "    classification: custom\n    status: done\n",
                    encoding="utf-8",
                )

            errors = validator.refinement_note_errors(root)

        self.assertTrue(errors)
        self.assertEqual(sorted(errors), errors)
        self.assertTrue(errors[0].startswith("client-projects/aaa/"), errors)


if __name__ == "__main__":
    unittest.main()
