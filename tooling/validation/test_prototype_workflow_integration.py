from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.workflow.router import next_stage
from tooling.workflow.state import initial_state


class PrototypeWorkflowIntegrationTests(unittest.TestCase):
    def _client(self, root: Path) -> tuple[Path, dict]:
        client = root / "client-projects" / "acme"
        (client / "directions").mkdir(parents=True)
        (client / "prototype" / "qa").mkdir(parents=True)
        (root / "packages" / "agency_flutter_ui").mkdir(parents=True)
        (root / "apps" / "prototype_app").mkdir(parents=True)
        (root / "packages" / "agency_flutter_ui" / "pubspec.yaml").write_text("name: ui\n", encoding="utf-8")
        (root / "apps" / "prototype_app" / "pubspec.yaml").write_text("name: app\n", encoding="utf-8")
        (client / "client-profile.yaml").write_text("id: acme\n", encoding="utf-8")
        (client / "resolved-intelligence.yaml").write_text("active_presets: []\n", encoding="utf-8")
        for name in ("direction-a.yaml", "direction-b.yaml", "direction-c.yaml", "comparison.yaml"):
            (client / "directions" / name).write_text("id: x\n", encoding="utf-8")
        state = initial_state("acme")
        state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
        state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
        return client, state

    def test_installed_platform_makes_build_prototype_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client, state = self._client(root)
            result = next_stage(root, client, state)
            self.assertEqual({"stage": "build-prototype", "status": "ready"}, result)

    def test_completed_build_requires_prototype_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client, state = self._client(root)
            state["completed"].append("build-prototype")
            result = next_stage(root, client, state)
            self.assertEqual("build-prototype", result["stage"])
            self.assertEqual("prototype-manifest-missing", result["reason"])

    def test_visual_qa_requires_findings_and_blocks_critical(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client, state = self._client(root)
            (client / "prototype" / "prototype-manifest.yaml").write_text("version: 1\n", encoding="utf-8")
            state["completed"].append("build-prototype")
            result = next_stage(root, client, state)
            self.assertEqual("visual-qa", result["stage"])
            self.assertEqual("ready", result["status"])

            state["completed"].append("visual-qa")
            (client / "prototype" / "qa" / "screenshot-manifest.yaml").write_text("version: 1\n", encoding="utf-8")
            findings = {
                "client_id": "acme",
                "findings": [{
                    "severity": "critical", "screen": "home", "direction": "a",
                    "viewport": "390x844", "issue": "overflow", "status": "open",
                }],
            }
            (client / "prototype" / "qa" / "visual-findings.yaml").write_text(yaml.safe_dump(findings), encoding="utf-8")
            result = next_stage(root, client, state)
            self.assertEqual("visual-qa", result["stage"])
            self.assertEqual("critical-visual-qa-findings", result["reason"])

    def test_clean_visual_qa_advances_to_client_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client, state = self._client(root)
            (client / "prototype" / "prototype-manifest.yaml").write_text("version: 1\n", encoding="utf-8")
            (client / "prototype" / "qa" / "screenshot-manifest.yaml").write_text("version: 1\n", encoding="utf-8")
            (client / "prototype" / "qa" / "visual-findings.yaml").write_text(
                yaml.safe_dump({"client_id": "acme", "findings": []}), encoding="utf-8"
            )
            state["completed"].extend(["build-prototype", "visual-qa"])
            result = next_stage(root, client, state)
            self.assertEqual({"stage": "client-review", "status": "ready"}, result)


if __name__ == "__main__":
    unittest.main()
