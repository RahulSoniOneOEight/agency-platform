from __future__ import annotations

import unittest
from datetime import datetime, timezone

from tooling.production_authorization.errors import InvalidProductionAuthorization, InvalidReleaseCandidate
from tooling.production_authorization.models import (
    EvidenceRef, ProductionAuthorization, ReleaseActor, ReleaseCandidate, canonical_json
)

SHA_A="1"*40
HASH_A="sha256:"+"a"*64


def evidence(eid="qa-release", category="qa", status="passed"):
    return EvidenceRef(eid, category, status, "fixture", SHA_A, HASH_A)


def candidate(**overrides):
    values=dict(
        client_id="reference-commerce", environment="production", approval_version=2,
        approval_review_state_hash="sha256:"+"b"*64, approval_source_commit_sha="2"*40,
        source_commit_sha=SHA_A, build_artifact_id="web-rc1", build_hash=HASH_A,
        approval_current=True, unresolved_blocking_feedback_ids=(),
        qa_evidence=(evidence(),), validation_evidence=(evidence("repository-validation","validator"),),
        security_evidence=(
            evidence("dependency-check","security"), evidence("secret-scan","security"),
            evidence("configuration-review","security"),
        ),
        rollback_plan_ref="release/evidence/rollback.md", migration_required=False,
        migration_plan_ref=None, release_notes_ref="release/evidence/release-notes.md",
        acknowledged_non_blocking_item_ids=("feedback-open",),
        supporting_evidence_refs=("reference-e2e/report/reference-report.json",),
    )
    values.update(overrides)
    return ReleaseCandidate(**values)


class ReleaseCandidateTests(unittest.TestCase):
    def test_round_trip(self):
        value=candidate()
        self.assertEqual(value, ReleaseCandidate.from_dict(value.to_dict()))
        self.assertIn('"client_id": "reference-commerce"', canonical_json(value))

    def test_normalizes_lists(self):
        value=candidate(acknowledged_non_blocking_item_ids=("z","a"))
        self.assertEqual(("a","z"), value.acknowledged_non_blocking_item_ids)

    def test_rejects_bad_sha_and_hash(self):
        with self.assertRaises(InvalidReleaseCandidate):
            candidate(source_commit_sha="abc")
        with self.assertRaises(InvalidReleaseCandidate):
            candidate(build_hash="sha256:bad")

    def test_requires_migration_plan_when_required(self):
        with self.assertRaises(InvalidReleaseCandidate):
            candidate(migration_required=True, migration_plan_ref=None)


class AuthorizationTests(unittest.TestCase):
    def _authorization(self, **overrides):
        values=dict(
            authorization_id="pa-reference-commerce-production-0001", authorization_version=1,
            client_id="reference-commerce", environment="production", approval_version=2,
            approval_review_state_hash="sha256:"+"b"*64, approval_source_commit_sha="2"*40,
            source_commit_sha=SHA_A, build_artifact_id="web-rc1", build_hash=HASH_A,
            qa_evidence_ids=("qa-release",), validation_evidence_ids=("repository-validation",),
            security_evidence_ids=("dependency-check","secret-scan","configuration-review"),
            rollback_plan_ref="rollback.md", migration_plan_ref=None, release_notes_ref="notes.md",
            acknowledged_non_blocking_item_ids=("feedback-open",),
            supporting_evidence_refs=("reference-report.json",),
            authorized_by=ReleaseActor("release-owner-1","Release Owner","human","release_owner"),
            authorized_at=datetime(2026,9,18,8,0,tzinfo=timezone.utc),
        )
        values.update(overrides)
        return ProductionAuthorization(**values)

    def test_round_trip_and_canonical_time(self):
        value=self._authorization()
        restored=ProductionAuthorization.from_dict(value.to_dict())
        self.assertEqual(value, restored)
        self.assertEqual("2026-09-18T08:00:00Z", value.to_dict()["authorized_at"])

    def test_rejects_agent_authorizer(self):
        with self.assertRaises(InvalidProductionAuthorization):
            self._authorization(authorized_by=ReleaseActor("agent","OpenCode","agent","release_owner"))

    def test_supersedes_must_be_earlier(self):
        with self.assertRaises(InvalidProductionAuthorization):
            self._authorization(supersedes=1)

    def test_frozen(self):
        value=self._authorization()
        with self.assertRaises(Exception):
            value.environment="staging"


if __name__=="__main__":
    unittest.main()
