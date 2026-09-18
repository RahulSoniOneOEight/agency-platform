from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from tooling.reference_client.evidence import load_evidence, validate_evidence


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SCHEMA_PATH = (
    ROOT / "client-projects" / "schema" / "reference-client-report.schema.json"
)
EVIDENCE_PATH = (
    CLIENT / "reference-e2e" / "evidence" / "review-approval-evidence.json"
)

SOURCE_COMMIT_SHA = "0123456789abcdef0123456789abcdef01234567"


def valid_evidence() -> dict:
    return {
        "client_id": "reference-commerce",
        "fixture_version": 1,
        "scenario_id": "normal-happy-path",
        "source_commit_sha": SOURCE_COMMIT_SHA,
        "selected_direction": "b",
        "screen_overrides": {"commerce.search": "a"},
        "section_overrides": {"commerce.pdp": {"pdp.price": "a"}},
        "feedback": {
            "blocking": [
                {
                    "id": "feedback-blocking",
                    "scope": "section",
                    "status": "resolved",
                    "blocking": True,
                    "target": {"screen": "commerce.pdp", "section": "pdp.price"},
                    "origin_qa_finding_id": None,
                    "history_types": ["created", "addressed", "resolved"],
                }
            ],
            "non_blocking": [
                {
                    "id": "feedback-non-blocking",
                    "scope": "general",
                    "status": "open",
                    "blocking": False,
                    "target": {},
                    "origin_qa_finding_id": None,
                    "history_types": ["created"],
                }
            ],
            "visual_annotations": [
                {
                    "id": "feedback-visual",
                    "status": "open",
                    "screenshot_ref": "sha256:abc",
                    "screen": "commerce.pdp",
                    "section": "pdp.price",
                    "effective_direction": "b",
                }
            ],
        },
        "refinement_batches": [
            {
                "id": "batch-001",
                "status": "completed",
                "feedback_ids": ["feedback-blocking"],
                "classification": "implementation_only",
            }
        ],
        "review_rounds": 1,
        "approval_versions": [1],
        "qa": {
            "findings": [
                {
                    "id": "qa-001",
                    "status": "promoted",
                    "severity": "major",
                    "category": "spacing",
                    "surface": "prototype",
                    "screen": "commerce.pdp",
                    "section": "pdp.price",
                    "rule_source": "design_contract",
                    "screenshot_ref": "sha256:abc",
                    "source_commit_sha": SOURCE_COMMIT_SHA,
                }
            ],
            "promotions": [
                {
                    "finding_id": "qa-001",
                    "feedback_id": "feedback-qa-001",
                    "blocking": False,
                }
            ],
        },
        "assertions": [{"id": "mix.selected_direction_b", "passed": True}],
    }


class EvidenceSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))

    def test_schema_accepts_valid_evidence(self):
        errors = list(
            Draft202012Validator(self.schema).iter_errors(valid_evidence())
        )
        self.assertEqual([], errors)

    def test_schema_rejects_overall_score_key(self):
        evidence = valid_evidence()
        evidence["overall_score"] = 0.9
        errors = list(Draft202012Validator(self.schema).iter_errors(evidence))
        self.assertTrue(errors)


class EvidenceValidationTests(unittest.TestCase):
    def test_repository_evidence_is_valid(self):
        evidence = load_evidence(EVIDENCE_PATH)
        self.assertEqual([], validate_evidence(ROOT, CLIENT, evidence))

    def test_valid_inline_evidence_passes(self):
        self.assertEqual([], validate_evidence(ROOT, CLIENT, valid_evidence()))

    def test_failing_assertion_is_rejected(self):
        evidence = valid_evidence()
        evidence["assertions"] = [{"id": "mix.selected_direction_b", "passed": False}]
        errors = validate_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("passed true" in error for error in errors), errors)

    def test_bad_approval_versions_are_rejected(self):
        evidence = valid_evidence()
        evidence["approval_versions"] = [2, 1]
        errors = validate_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("strictly increasing" in error for error in errors), errors)

    def test_fixture_version_mismatch_is_rejected(self):
        evidence = valid_evidence()
        evidence["fixture_version"] = 2
        errors = validate_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("fixture_version" in error for error in errors), errors)

    def test_unknown_scenario_id_is_rejected(self):
        evidence = valid_evidence()
        evidence["scenario_id"] = "not-a-scenario"
        errors = validate_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("scenario_id" in error for error in errors), errors)

    def test_copied_authority_state_is_rejected(self):
        evidence = valid_evidence()
        evidence["feedback"]["blocking"][0]["screen_selections"] = {"x": "a"}
        errors = validate_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("copy authority state" in error for error in errors), errors)

    def test_nested_score_key_is_rejected(self):
        evidence = valid_evidence()
        evidence["qa"]["quality_score"] = 42
        errors = validate_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("subjective score key" in error for error in errors), errors
        )


if __name__ == "__main__":
    unittest.main()
