from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.workflow.client_input import validate_client_input
from tooling.workflow.initialize_client import initialize_client
from tooling.workflow.router import next_stage
from tooling.workflow.state import initial_state, save_state
from tooling.workflow.validate_workflow import validate_client, validate_runtime, validate_workflow_file


ROOT = Path(__file__).resolve().parents[2]

PROFILE = {
    "id": "acme",
    "business_model": "b2b",
    "industry": "electronics-appliances",
    "use_cases": ["rfq"],
    "objectives": ["grow-rfq"],
    "personas": ["trade-buyer"],
    "jobs": ["request-quote"],
    "platforms": ["web"],
}


def _install_input_schemas(root: Path) -> None:
    dst = root / "client-projects" / "schema" / "input"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "client-projects" / "schema" / "input", dst, dirs_exist_ok=True)


def _write_index(client: Path, *, modules: dict | None = None, collections: dict | None = None) -> None:
    (client / "input").mkdir(parents=True, exist_ok=True)
    (client / "input" / "client-input.yaml").write_text(
        yaml.safe_dump(
            {
                "version": 1,
                "client": {"id": "acme", "display_name": "ACME"},
                "source_status": "client_supplied",
                "modules": modules or {},
                "collections": collections or {},
                "unresolved_input": False,
            },
            sort_keys=False,
        ),
        encoding="utf-8",
    )


def write_early_artifacts(client: Path) -> None:
    _install_input_schemas(client.parents[1])
    client.mkdir(parents=True, exist_ok=True)
    (client / "derived").mkdir(parents=True, exist_ok=True)
    _write_index(client)
    (client / "derived" / "client-profile.yaml").write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
    (client / "resolved-intelligence.yaml").write_text("active_presets: []\n", encoding="utf-8")


def write_direction_artifacts(client: Path) -> None:
    directions = client / "directions"
    directions.mkdir(parents=True, exist_ok=True)
    for name in ("direction-a.yaml", "direction-b.yaml", "direction-c.yaml", "comparison.yaml"):
        (directions / name).write_text("id: sample\n", encoding="utf-8")


MODULE_DOMAINS = {
    "business-rules.yaml": "rules",
    "user-groups.yaml": "groups",
    "journey-priorities.yaml": "journeys",
    "feature-requirements.yaml": "features",
    "platform-requirements.yaml": "requirements",
    "integration-requirements.yaml": "integrations",
    "content-requirements.yaml": "requirements",
    "data-context.yaml": "entities",
    "constraints.yaml": "constraints",
    "open-questions.yaml": "questions",
}

COLLECTION_DOMAINS = {
    "brand": ("brand-input.yaml", "facts"),
    "references": ("references.yaml", "references"),
    "assets": ("asset-manifest.yaml", "assets"),
    "source-documents": ("source-documents.yaml", "documents"),
}


class WorkflowRuntimeTests(unittest.TestCase):
    def test_initializer_creates_exact_standard_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            client_dir = initialize_client(root, "acme", "Acme Furniture")
            for rel in (
                "input",
                "input/brand/brand-assets",
                "input/references/current-app",
                "input/references/competitor",
                "input/references/inspiration",
                "input/assets/products",
                "input/assets/categories",
                "input/assets/banners",
                "input/assets/sellers",
                "input/assets/videos",
                "input/source-documents",
                "derived",
                "resources",
                "directions",
                "prototype",
            ):
                self.assertTrue((client_dir / rel).is_dir(), rel)
            self.assertTrue((client_dir / "workflow-state.yaml").exists())
            self.assertTrue((client_dir / "input" / "client-input.yaml").exists())
            self.assertTrue((client_dir / "derived" / "client-profile.yaml").exists())
            self.assertFalse((client_dir / "client-profile.yaml").exists())
            self.assertFalse((client_dir / "references").exists())
            self.assertFalse((client_dir / "fixtures").exists())
            self.assertEqual([], validate_client_input(ROOT, client_dir))

            index = yaml.safe_load((client_dir / "input" / "client-input.yaml").read_text(encoding="utf-8"))
            self.assertEqual("acme", index["client"]["id"])
            self.assertEqual("Acme Furniture", index["client"]["display_name"])
            self.assertEqual("client_supplied", index["source_status"])
            self.assertEqual({}, index["modules"])
            self.assertEqual({}, index["collections"])
            self.assertTrue(index["unresolved_input"])

            profile = yaml.safe_load((client_dir / "derived" / "client-profile.yaml").read_text(encoding="utf-8"))
            self.assertEqual("acme", profile["id"])
            self.assertEqual("Acme Furniture", profile["display_name"])
            self.assertEqual("", profile["business_model"])
            self.assertEqual("", profile["industry"])
            self.assertEqual([], profile["personas"])
            self.assertEqual([], profile["platforms"])

    def test_initializer_optional_templates_are_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            client_dir = initialize_client(root, "acme")
            input_dir = client_dir / "input"
            for filename, domain in MODULE_DOMAINS.items():
                data = yaml.safe_load((input_dir / filename).read_text(encoding="utf-8"))
                self.assertEqual(1, data["version"], filename)
                self.assertFalse(data["provided"], filename)
                self.assertEqual([], data[domain], filename)
            for subdir, (filename, domain) in COLLECTION_DOMAINS.items():
                data = yaml.safe_load((input_dir / subdir / filename).read_text(encoding="utf-8"))
                self.assertEqual(1, data["version"], filename)
                self.assertFalse(data["provided"], filename)
                self.assertEqual([], data[domain], filename)

    def test_initializer_refuses_existing_client(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects" / "acme").mkdir(parents=True)
            with self.assertRaises(FileExistsError):
                initialize_client(root, "acme")

    def test_initial_next_stage_is_client_intake(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            client.mkdir(parents=True)
            state = initial_state("acme")
            self.assertEqual("client-intake", next_stage(root, client, state)["stage"])

    def test_valid_profile_advances_to_resolve_intelligence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            state["current_stage"] = "resolve-intelligence"
            self.assertEqual("resolve-intelligence", next_stage(root, client, state)["stage"])

    def test_resource_research_can_be_skipped_with_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence"]
            state["skipped"] = [{"stage": "resource-research", "reason": "no-external-resources-required"}]
            result = next_stage(root, client, state)
            self.assertEqual("generate-directions", result["stage"])

    def test_build_prototype_blocks_when_platform_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual("build-prototype", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("prototype-platform-not-installed", result["reason"])

    def test_productionize_is_not_selected_without_approved_experience(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = [
                "client-intake", "resolve-intelligence", "generate-directions",
                "build-prototype", "visual-qa", "client-review",
            ]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertNotEqual("productionize", result.get("stage"))

    def test_workflow_file_missing_required_section_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.md"
            path.write_text("## PURPOSE\nDo a thing\n## READ\ninputs\n", encoding="utf-8")
            errors = validate_workflow_file(path)
            self.assertTrue(errors)
            self.assertTrue(any("PROCESS" in error for error in errors))

    def test_two_direction_client_passes_workflow_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            directions = client / "directions"
            directions.mkdir(parents=True, exist_ok=True)
            for name in ("direction-a.yaml", "direction-b.yaml", "comparison.yaml"):
                (directions / name).write_text("id: sample\n", encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
            save_state(client / "workflow-state.yaml", state)
            errors = validate_client(root, client)
            self.assertEqual([], errors)

    def test_router_blocks_intake_when_client_input_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            (client / "input").mkdir(parents=True)
            (client / "input" / "client-input.yaml").write_text("foo: [1, 2", encoding="utf-8")
            state = initial_state("acme")
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("client-input-invalid", result["reason"])

    def test_router_blocks_intake_when_blocking_question_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            (client / "input").mkdir(parents=True)
            (client / "input" / "open-questions.yaml").write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "questions": [
                            {"id": "q1", "question": "Who approves?", "status": "open", "blocking": True}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            _write_index(client, modules={"open_questions": "open-questions.yaml"})
            state = initial_state("acme")
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("blocking-open-questions", result["reason"])

    def test_router_requires_derived_client_profile_after_intake(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            _write_index(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("derived-client-profile-missing", result["reason"])

    def test_router_allows_intake_progress_with_valid_nonblocking_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            (client / "input").mkdir(parents=True)
            (client / "input" / "open-questions.yaml").write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "questions": [
                            {"id": "q1", "question": "Tone?", "status": "resolved", "blocking": True}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            _write_index(client, modules={"open_questions": "open-questions.yaml"})
            state = initial_state("acme")
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("ready", result["status"])

    def test_validate_client_rejects_root_only_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            (client / "derived" / "client-profile.yaml").unlink()
            (client / "client-profile.yaml").write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            save_state(client / "workflow-state.yaml", state)
            errors = validate_client(root, client)
            self.assertTrue(any("derived" in e and "client-profile.yaml" in e for e in errors))

    def test_repository_runtime_contract_validates(self):
        root = Path(__file__).resolve().parents[2]
        errors = validate_runtime(root)
        self.assertEqual([], errors)


if __name__ == "__main__":
    unittest.main()
