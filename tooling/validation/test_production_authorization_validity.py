from __future__ import annotations

import unittest
from dataclasses import replace
from datetime import datetime, timezone

from tooling.production_authorization.models import EvidenceRef, ProductionAuthorization, ReleaseActor, ReleaseCandidate
from tooling.production_authorization.validity import AuthorizationEvent, evaluate_authorization

SHA="1"*40; HASH="sha256:"+"a"*64

def ev(eid,cat,status="passed"):
    return EvidenceRef(eid,cat,status,"test",SHA,HASH)

def candidate(**overrides):
    data=dict(
      client_id="client",environment="production",approval_version=2,
      approval_review_state_hash="sha256:"+"b"*64,approval_source_commit_sha="2"*40,
      source_commit_sha=SHA,build_artifact_id="build",build_hash=HASH,approval_current=True,
      unresolved_blocking_feedback_ids=(),qa_evidence=(ev("qa","qa"),),
      validation_evidence=(ev("repo","validator"),),
      security_evidence=(ev("dependency-check","security"),ev("secret-scan","security"),ev("configuration-review","security")),
      rollback_plan_ref="rollback.md",migration_required=False,migration_plan_ref=None,release_notes_ref="notes.md"
    ); data.update(overrides); return ReleaseCandidate(**data)

def authorization(**overrides):
    data=dict(
      authorization_id="pa-client-production-0001",authorization_version=1,client_id="client",
      environment="production",approval_version=2,approval_review_state_hash="sha256:"+"b"*64,
      approval_source_commit_sha="2"*40,source_commit_sha=SHA,build_artifact_id="build",build_hash=HASH,
      qa_evidence_ids=("qa",),validation_evidence_ids=("repo",),
      security_evidence_ids=("dependency-check","secret-scan","configuration-review"),
      rollback_plan_ref="rollback.md",migration_plan_ref=None,release_notes_ref="notes.md",
      acknowledged_non_blocking_item_ids=(),supporting_evidence_refs=(),
      authorized_by=ReleaseActor("owner","Owner","human","release_owner"),
      authorized_at=datetime(2026,9,18,8,0,tzinfo=timezone.utc)
    ); data.update(overrides); return ProductionAuthorization(**data)

class ValidityTests(unittest.TestCase):
    def test_exact_candidate_is_valid(self):
        self.assertTrue(evaluate_authorization(authorization(),candidate()).valid)

    def test_identity_changes_invalidate_use(self):
        cases=[
          replace(candidate(),source_commit_sha="3"*40),
          replace(candidate(),build_artifact_id="build-2"),
          replace(candidate(),build_hash="sha256:"+"c"*64),
          replace(candidate(),environment="staging"),
          replace(candidate(),approval_version=3),
        ]
        for value in cases:
            with self.subTest(value=value):
                self.assertFalse(evaluate_authorization(authorization(),value).valid)

    def test_security_or_qa_regression_blocks(self):
        bad=replace(candidate(),qa_evidence=(ev("qa","qa","failed"),))
        self.assertFalse(evaluate_authorization(authorization(),bad).valid)

    def test_event_invalidates_without_mutating_authorization(self):
        auth=authorization()
        before=auth.to_dict()
        event=AuthorizationEvent(
          "event-1",auth.authorization_id,"invalidated","security regression",
          ReleaseActor("owner","Owner","human","release_owner"),
          datetime(2026,9,18,9,0,tzinfo=timezone.utc),
        )
        result=evaluate_authorization(auth,candidate(),[event])
        self.assertFalse(result.valid)
        self.assertIn("authorization_invalidated",result.reasons)
        self.assertEqual(before,auth.to_dict())


if __name__=="__main__":
    unittest.main()
