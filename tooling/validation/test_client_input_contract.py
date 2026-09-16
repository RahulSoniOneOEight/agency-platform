from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.workflow.client_input import blocking_open_questions, validate_client_input

ROOT = Path(__file__).resolve().parents[2]


def _write_input(client_dir: Path, content: dict) -> Path:
    input_dir = client_dir / "input"
    input_dir.mkdir(parents=True, exist_ok=True)
    path = input_dir / "client-input.yaml"
    path.write_text(yaml.safe_dump(content, sort_keys=False), encoding="utf-8")
    return path


def _minimal_input() -> dict:
    return {
        "version": 1,
        "client": {"id": "acme", "display_name": "ACME"},
        "source_status": "client_supplied",
        "modules": {},
        "collections": {},
    }


class ClientInputContractTests(unittest.TestCase):
    def test_minimal_client_input_validates(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            _write_input(client, _minimal_input())
            self.assertEqual([], validate_client_input(ROOT, client))

    def test_referenced_module_is_schema_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            (client / "input").mkdir(parents=True, exist_ok=True)
            content = _minimal_input()
            content["modules"]["user_groups"] = "user-groups.yaml"
            _write_input(client, content)

            (client / "input" / "user-groups.yaml").write_text(
                yaml.safe_dump({"version": 1, "provided": True, "groups": [{"label": "dealer"}]}), encoding="utf-8"
            )
            self.assertEqual([], validate_client_input(ROOT, client))

            (client / "input" / "user-groups.yaml").write_text(
                yaml.safe_dump({"version": 1, "groups": []}), encoding="utf-8"
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("provided" in e for e in errors))

            (client / "input" / "user-groups.yaml").write_text(
                yaml.safe_dump({"provided": True, "groups": []}), encoding="utf-8"
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("version" in e for e in errors))

    def test_referenced_module_requires_domain_array(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            content = _minimal_input()
            content["modules"]["user_groups"] = "user-groups.yaml"
            _write_input(client, content)
            (client / "input" / "user-groups.yaml").write_text(
                yaml.safe_dump({"version": 1, "provided": True}), encoding="utf-8"
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("groups" in e for e in errors))

    def test_collection_key_in_modules_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            content = _minimal_input()
            content["modules"]["brand"] = "brand-input.yaml"
            _write_input(client, content)
            (client / "input" / "brand-input.yaml").write_text(
                yaml.safe_dump({"version": 1, "provided": True, "facts": []}), encoding="utf-8"
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("unknown module key" in e for e in errors))

    def test_missing_referenced_file_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            content = _minimal_input()
            content["modules"]["user_groups"] = "user-groups.yaml"
            _write_input(client, content)
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("missing referenced file" in e for e in errors))

    def test_path_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            content = _minimal_input()
            content["modules"]["user_groups"] = "../user-groups.yaml"
            _write_input(client, content)
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("escapes" in e for e in errors))

    def test_malformed_yaml_returns_error_not_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            (client / "input").mkdir(parents=True, exist_ok=True)
            (client / "input" / "client-input.yaml").write_text("foo: [1, 2", encoding="utf-8")
            errors = validate_client_input(ROOT, client)
            self.assertTrue(errors)

    def test_duplicate_manifest_ids_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            (client / "input").mkdir(parents=True, exist_ok=True)
            content = _minimal_input()
            content["collections"]["references"] = "references.yaml"
            _write_input(client, content)
            (client / "input" / "references.yaml").write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "references": [
                            {"id": "ref-1", "label": "Competitor A"},
                            {"id": "ref-1", "label": "Duplicate"},
                        ],
                    }
                ),
                encoding="utf-8",
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("duplicate" in e for e in errors))

    def test_blocking_open_question_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            (client / "input").mkdir(parents=True, exist_ok=True)
            content = _minimal_input()
            content["modules"]["open_questions"] = "open-questions.yaml"
            _write_input(client, content)
            (client / "input" / "open-questions.yaml").write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "questions": [
                            {
                                "id": "q1",
                                "question": "Who approves orders?",
                                "status": "open",
                                "blocking": True,
                            },
                            {
                                "id": "q2",
                                "question": "Preferred tone?",
                                "status": "resolved",
                                "blocking": True,
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            blocking = blocking_open_questions(client)
            self.assertEqual(["q1"], [q["id"] for q in blocking])

    def test_unreferenced_optional_template_does_not_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            _write_input(client, _minimal_input())
            (client / "input" / "business-rules.yaml").write_text(
                yaml.safe_dump({"version": 1, "provided": False, "rules": []}), encoding="utf-8"
            )
            self.assertEqual([], validate_client_input(ROOT, client))

    def test_brand_visual_contract_is_schema_validated(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "acme"
            (client / "input" / "brand").mkdir(parents=True, exist_ok=True)
            content = _minimal_input()
            content["collections"]["brand"] = "brand/brand-input.yaml"
            _write_input(client, content)
            brand_path = client / "input" / "brand" / "brand-input.yaml"

            brand_path.write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "facts": [],
                        "visual": {
                            "preset": "premium-modern",
                            "primary_color": "#1155CC",
                            "font_family": "Inter",
                            "visual_character": "soft",
                        },
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual([], validate_client_input(ROOT, client))

            brand_path.write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "facts": [],
                        "visual": {"primary_color": "not-a-color"},
                    }
                ),
                encoding="utf-8",
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(any("primary_color" in error for error in errors), errors)

            brand_path.write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "facts": [],
                        "visual": {"nope": 1},
                    }
                ),
                encoding="utf-8",
            )
            errors = validate_client_input(ROOT, client)
            self.assertTrue(errors)

    def test_reference_prototype_demo_validates_end_to_end(self):
        root = Path(__file__).resolve().parents[2]
        client = root / "client-projects" / "examples" / "prototype-demo"
        self.assertEqual([], validate_client_input(root, client))
        self.assertTrue((client / "derived" / "client-profile.yaml").exists())
        self.assertFalse((client / "client-profile.yaml").exists())


if __name__ == "__main__":
    unittest.main()
