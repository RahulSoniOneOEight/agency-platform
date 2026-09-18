from __future__ import annotations

import unittest
from dataclasses import replace

from tooling.production_authorization.eligibility import evaluate_eligibility
from tooling.production_authorization.models import EvidenceRef, ReleaseCandidate

SHA="1"*40
HASH="sha256:"+"a"*64

def ev(eid, category, status="passed", *, sha=SHA, build=HASH, executed=True, blocking=0):
    return EvidenceRef(eid,category,status,"test",sha,build,executed,blocking)

def good():
    return ReleaseCandidate(
        client_id="client", environment="production", approval_version=2,
        approval_review_state_hash="sha256:"+"b"*64, approval_source_commit_sha="2"*40,
        source_commit_sha=SHA, build_artifact_id="build", build_hash=HASH, approval_current=True,
        unresolved_blocking_feedback_ids=(),
        qa_evidence=(ev("qa","qa"),),
        validation_evidence=(ev("repo","validator"),ev("workflow","validator")),
        security_evidence=(ev("dependency-check","security"),ev("secret-scan","security"),ev("configuration-review","security")),
        rollback_plan_ref="rollback.md", migration_required=False, migration_plan_ref=None,
        release_notes_ref="notes.md",
    )

class EligibilityTests(unittest.TestCase):
    def codes(self,c):
        return [r.code for r in evaluate_eligibility(c).reasons]

    def test_good_candidate_is_eligible(self):
        result=evaluate_eligibility(good())
        self.assertTrue(result.eligible)
        self.assertEqual((),result.reasons)

    def test_aggregates_review_qa_validator_and_security_failures(self):
        c=replace(
            good(), approval_current=False, unresolved_blocking_feedback_ids=("fb-1",),
            qa_evidence=(ev("qa","qa",status="failed",blocking=1),),
            validation_evidence=(ev("repo","validator",status="failed"),),
            security_evidence=(),
        )
        codes=self.codes(c)
        self.assertIn("approval_not_current",codes)
        self.assertIn("blocking_review_feedback",codes)
        self.assertIn("qa_evidence_failed",codes)
        self.assertIn("blocking_qa_findings",codes)
        self.assertIn("validator_failed",codes)
        self.assertEqual(3,codes.count("security_evidence_missing"))

    def test_stale_candidate_bound_evidence_rejected(self):
        c=replace(good(),qa_evidence=(ev("qa","qa",sha="3"*40),))
        self.assertIn("qa_evidence_stale",self.codes(c))

    def test_declared_only_validator_is_not_pass(self):
        c=replace(good(),validation_evidence=(ev("repo","validator",status="declared_only",executed=False),))
        self.assertIn("validator_failed",self.codes(c))

    def test_reasons_are_stable_sorted(self):
        c=replace(good(),approval_current=False,security_evidence=())
        reasons=evaluate_eligibility(c).reasons
        self.assertEqual(tuple(sorted(reasons)),reasons)


if __name__=="__main__":
    unittest.main()
