from __future__ import annotations
import unittest
from pathlib import Path
from tooling.production_authorization.eligibility import evaluate_eligibility
from tooling.production_authorization.errors import ProductionAuthorizationCandidateMismatch
from tooling.production_authorization.reference_client import build_reference_candidate,candidate_freshness_errors,implementation_only_candidate
from tooling.production_authorization.repository import FileProductionAuthorizationRepository
from tooling.production_authorization.release_gate import verify_release_gate

ROOT=Path(__file__).resolve().parents[2]
CLIENT=ROOT/"client-projects"/"reference-commerce"

class ReferenceClientGTests(unittest.TestCase):
    def test_builds_eligible_candidate_from_merged_f_v2(self):
        candidate=build_reference_candidate(ROOT)
        self.assertEqual(2,candidate.approval_version)
        self.assertEqual("sha256:2b4cc537379f8142b1c629cf6c3bd9b87e78d005363658e526b876e950292153",candidate.approval_review_state_hash)
        self.assertTrue(evaluate_eligibility(candidate).eligible)
        self.assertEqual([],candidate_freshness_errors(ROOT))

    def test_f_report_is_supporting_evidence_not_duplicate_authority(self):
        candidate=build_reference_candidate(ROOT)
        self.assertTrue(any(ref.endswith("reference-report.json") for ref in candidate.supporting_evidence_refs))
        self.assertFalse((CLIENT/"release"/"approval-v2.json").exists())

    def test_committed_authorization_matches_exact_candidate(self):
        candidate=build_reference_candidate(ROOT)
        authorization=FileProductionAuthorizationRepository(CLIENT).list("reference-commerce","production")[-1]
        verify_release_gate(authorization,candidate)

    def test_implementation_only_change_keeps_approval_but_requires_reauthorization(self):
        candidate=build_reference_candidate(ROOT)
        changed=implementation_only_candidate(
            candidate,
            source_commit_sha="f"*40,
            build_artifact_id="reference-commerce-web-rc2",
            build_hash="sha256:"+"d"*64,
        )
        self.assertEqual(candidate.approval_version,changed.approval_version)
        self.assertEqual(candidate.approval_review_state_hash,changed.approval_review_state_hash)
        self.assertTrue(evaluate_eligibility(changed).eligible)
        authorization=FileProductionAuthorizationRepository(CLIENT).list("reference-commerce","production")[-1]
        with self.assertRaises(ProductionAuthorizationCandidateMismatch):
            verify_release_gate(authorization,changed)

if __name__=="__main__":
    unittest.main()
