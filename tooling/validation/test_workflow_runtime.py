from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.workflow.initialize_client import initialize_client
from tooling.workflow.router import next_stage
from tooling.workflow.state import initial_state
from tooling.workflow.validate_workflow import validate_runtime, validate_workflow_file


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


def write_early_artifacts(client: Path) -> None:
    client.mkdir(parents=True, exist_ok=True)
    (client / "client-profile.yaml").write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
    (client / "resolved-intelligence.yaml").write_text("active_presets: []\n", encoding="utf-8")


def write_direction_artifacts(client: Path) -> None:
    directions = client / "directions"
    directions.mkdir(parents=True, exist_ok=True)
    for name in ("direction-a.yaml", "direction-b.yaml", "direction-c.yaml", "comparison.yaml"):
        (directions / name).write_text("id: sample\n", encoding="utf-8")


def install_prototype_platform(root: Path) -> None:
    for path in (
        root / "packages" / "agency_flutter_ui" / "pubspec.yaml",
        root / "apps" / "prototype_app" / "pubspec.yaml",
    ):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("name: fixture\n", encoding="utf-8")


def write_prototype_artifacts(client: Path) -> None:
    prototype = client / "prototype"
    (prototype / "fixtures").mkdir(parents=True, exist_ok=True)
    (prototype / "prototype-manifest.yaml").write_text("client_id: acme\n", encoding="utf-8")
    (prototype / "fixtures" / "demo.yaml").write_text("products: []\n", encoding="utf-8")


def write_qa_artifacts(client: Path, *, open_critical: bool = False) -> None:
    prototype = client / "prototype"
    qa = prototype / "qa"
    qa.mkdir(parents=True, exist_ok=True)
    (prototype / "screenshot-manifest.yaml").write_text("client_id: acme\nentries: []\n", encoding="utf-8")
    findings = {
        "client_id": "acme",
        "findings": ([{
            "severity": "critical",
            "screen": "home",
            "direction": "a",
            "viewport": "390x844",
            "issue": "overflow",
            "status": "open",
        }] if open_critical else []),
    }
    (qa / "findings.yaml").write_text(yaml.safe_dump(findings), encoding="utf-8")


class WorkflowRuntimeTests(unittest.TestCase):
    def test_initializer_creates_exact_standard_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            client_dir = initialize_client(root, "acme", "Acme Furniture")
            expected = {
                "brief.md",
                "client-profile.yaml",
                "workflow-state.yaml",
                "references/.gitkeep",
                "resources/.gitkeep",
                "directions/.gitkeep",
                "fixtures/.gitkeep",
            }
            actual = {
                str(path.relative_to(client_dir)).replace("\\", "/")
                for path in client_dir.rglob("*")
                if path.is_file()
            }
            self.assertEqual(expected, actual)

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
            self.assertEqual("client-intake", next_stage(root, client, initial_state("acme"))["stage"])

    def test_valid_profile_advances_to_resolve_intelligence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            client.mkdir(parents=True)
            (client / "client-profile.yaml").write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            self.assertEqual("resolve-intelligence", next_stage(root, client, state)["stage"])

    def test_resource_research_can_be_skipped_with_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence"]
            state["skipped"] = [{"stage": "resource-research", "reason": "no-external-resources-required"}]
            self.assertEqual("generate-directions", next_stage(root, client, state)["stage"])

    def test_build_prototype_blocks_when_platform_is_not_installed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual("prototype-platform-not-installed", result["reason"])

    def test_installed_platform_makes_build_prototype_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            install_prototype_platform(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual({"stage": "build-prototype", "status": "ready"}, result)

    def test_completed_build_requires_prototype_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            install_prototype_platform(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions", "build-prototype"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual("build-prototype", result["stage"])
            self.assertEqual("prototype-artifacts-missing", result["reason"])

    def test_completed_prototype_advances_to_visual_qa(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            install_prototype_platform(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            write_prototype_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions", "build-prototype"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            self.assertEqual("visual-qa", next_stage(root, client, state)["stage"])

    def test_completed_visual_qa_requires_artifacts_and_no_open_critical_findings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            install_prototype_platform(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            write_prototype_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions", "build-prototype", "visual-qa"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual("visual-qa-artifacts-missing", result["reason"])
            write_qa_artifacts(client, open_critical=True)
            result = next_stage(root, client, state)
            self.assertEqual("visual-qa-blockers-open", result["reason"])
            write_qa_artifacts(client, open_critical=False)
            self.assertEqual("client-review", next_stage(root, client, state)["stage"])

    def test_productionize_is_not_selected_without_approved_experience(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            write_prototype_artifacts(client)
            write_qa_artifacts(client)
            state = initial_state("acme")
            state["completed"] = [
                "client-intake", "resolve-intelligence", "generate-directions",
                "build-prototype", "visual-qa", "client-review",
            ]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual("approved-experience-missing", result.get("reason"))

    def test_workflow_file_missing_required_section_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.md"
            path.write_text("## PURPOSE\nDo a thing\n## READ\ninputs\n", encoding="utf-8")
            errors = validate_workflow_file(path)
            self.assertTrue(any("PROCESS" in error for error in errors))

    def test_repository_runtime_contract_validates(self):
        root = Path(__file__).resolve().parents[2]
        self.assertEqual([], validate_runtime(root))


if __name__ == "__main__":
    unittest.main()
