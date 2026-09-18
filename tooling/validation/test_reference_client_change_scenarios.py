from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from tooling.reference_client.change_scenarios import (
    CONTRACT_IMPACTING,
    IMPLEMENTATION_ONLY,
    classify_change,
    contract_impacting_change,
    implementation_only_change,
    validate_change_evidence,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SCHEMA_PATH = (
    ROOT
    / "client-projects"
    / "schema"
    / "reference-client-change-evidence.schema.json"
)
EVIDENCE_PATH = (
    CLIENT
    / "reference-e2e"
    / "evidence"
    / "change-scenarios-evidence.json"
)

SOURCE_COMMIT_SHA = "89abcdef0123456789abcdef0123456789abcdef"


def valid_evidence() -> dict:
    return {
        "client_id": "reference-commerce",
        "fixture_version": 1,
        "scenario_ids": [
            "contract-change-reapproval",
            "implementation-only-change",
        ],
        "source_commit_sha": SOURCE_COMMIT_SHA,
        "contract_change": {
            "review_rounds": 2,
            "approval_versions": [1, 2],
            "v1_immutable": True,
            "v2_version": 2,
            "v2_supersedes": 1,
            "v2_review_round": 2,
            "v2_hash_differs": True,
            "v2_source_sha_differs": True,
            "third_approval_refused": True,
        },
        "implementation_only": {
            "approval_versions": [1],
            "review_round": 1,
            "classification": "implementation_only",
            "approved_hash_unchanged": True,
            "still_eligible": True,
            "default_classification": "contract_impacting",
        },
        "assertions": [
            {"id": "contract.review_round_2", "passed": True},
            {"id": "implementation.approval_count_1", "passed": True},
        ],
    }


class ChangeClassificationTests(unittest.TestCase):
    def test_canonical_contract_change_is_contract_impacting(self):
        self.assertEqual(
            CONTRACT_IMPACTING, classify_change(contract_impacting_change())
        )

    def test_canonical_implementation_change_is_implementation_only(self):
        self.assertEqual(
            IMPLEMENTATION_ONLY, classify_change(implementation_only_change())
        )

    def test_explicit_internal_only_descriptor_is_implementation_only(self):
        descriptor = implementation_only_change()
        self.assertEqual(IMPLEMENTATION_ONLY, classify_change(descriptor))

    def test_uncertain_descriptor_defaults_to_contract_impacting(self):
        descriptor = implementation_only_change()
        descriptor["uncertain"] = True
        self.assertEqual(CONTRACT_IMPACTING, classify_change(descriptor))

    def test_missing_field_defaults_to_contract_impacting(self):
        descriptor = implementation_only_change()
        del descriptor["internal_only"]
        self.assertEqual(CONTRACT_IMPACTING, classify_change(descriptor))

    def test_truthy_non_boolean_flag_is_contract_impacting(self):
        descriptor = implementation_only_change()
        descriptor["internal_only"] = "true"
        self.assertEqual(CONTRACT_IMPACTING, classify_change(descriptor))


class ChangeEvidenceSchemaTests(unittest.TestCase):
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


class ChangeEvidenceValidationTests(unittest.TestCase):
    def test_valid_inline_evidence_passes(self):
        self.assertEqual([], validate_change_evidence(ROOT, CLIENT, valid_evidence()))

    def test_repository_change_evidence_is_valid(self):
        self.assertTrue(EVIDENCE_PATH.exists(), EVIDENCE_PATH)
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        self.assertEqual([], validate_change_evidence(ROOT, CLIENT, evidence))

    def test_failing_assertion_is_rejected(self):
        evidence = valid_evidence()
        evidence["assertions"][0]["passed"] = False
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("passed true" in error for error in errors), errors)

    def test_single_contract_approval_version_is_rejected(self):
        evidence = valid_evidence()
        evidence["contract_change"]["approval_versions"] = [1]
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("at least two entries" in error for error in errors), errors
        )

    def test_mutated_v1_is_rejected(self):
        evidence = valid_evidence()
        evidence["contract_change"]["v1_immutable"] = False
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("v1_immutable must be true" in error for error in errors), errors
        )

    def test_bad_supersedes_is_rejected(self):
        evidence = valid_evidence()
        evidence["contract_change"]["v2_supersedes"] = 2
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("v2_supersedes" in error for error in errors), errors
        )

    def test_bad_implementation_review_round_is_rejected(self):
        evidence = valid_evidence()
        evidence["implementation_only"]["review_round"] = 2
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("review_round must be 1" in error for error in errors), errors
        )

    def test_wrong_implementation_classification_is_rejected(self):
        evidence = valid_evidence()
        evidence["implementation_only"]["classification"] = CONTRACT_IMPACTING
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("classification must be" in error for error in errors), errors
        )

    def test_changed_approved_hash_is_rejected(self):
        evidence = valid_evidence()
        evidence["implementation_only"]["approved_hash_unchanged"] = False
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("approved_hash_unchanged must be true" in error for error in errors),
            errors,
        )

    def test_wrong_default_classification_is_rejected(self):
        evidence = valid_evidence()
        evidence["implementation_only"]["default_classification"] = IMPLEMENTATION_ONLY
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("default_classification" in error for error in errors), errors
        )

    def test_added_score_key_is_rejected(self):
        evidence = valid_evidence()
        evidence["overall_score"] = 0.9
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("subjective score key" in error for error in errors), errors
        )

    def test_nested_authority_body_is_rejected(self):
        evidence = valid_evidence()
        evidence["implementation_only"]["reviewed_by"] = {"id": "reviewer-123"}
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(
            any("copy authority state" in error for error in errors), errors
        )

    def test_unknown_scenario_id_is_rejected(self):
        evidence = valid_evidence()
        evidence["scenario_ids"] = ["not-a-scenario"]
        errors = validate_change_evidence(ROOT, CLIENT, evidence)
        self.assertTrue(any("scenario_ids" in error for error in errors), errors)

    def test_deepcopy_isolation(self):
        evidence = valid_evidence()
        tampered = copy.deepcopy(evidence)
        tampered["contract_change"]["v2_hash_differs"] = False
        self.assertEqual([], validate_change_evidence(ROOT, CLIENT, evidence))
        errors = validate_change_evidence(ROOT, CLIENT, tampered)
        self.assertTrue(any("v2_hash_differs" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
