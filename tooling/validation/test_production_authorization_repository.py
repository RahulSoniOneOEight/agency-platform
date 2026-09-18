from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from tooling.production_authorization.errors import ProductionAuthorizationVersionConflict
from tooling.production_authorization.models import ProductionAuthorization, ReleaseActor
from tooling.production_authorization.repository import FileProductionAuthorizationRepository


def authorization(version=1, environment="production", supersedes=None):
    return ProductionAuthorization(
        authorization_id=f"pa-client-{environment}-{version:04d}", authorization_version=version,
        client_id="client", environment=environment, approval_version=2,
        approval_review_state_hash="sha256:"+"a"*64, approval_source_commit_sha="1"*40,
        source_commit_sha="2"*40, build_artifact_id="build", build_hash="sha256:"+"b"*64,
        qa_evidence_ids=("qa",), validation_evidence_ids=("val",), security_evidence_ids=("sec",),
        rollback_plan_ref="rollback.md", migration_plan_ref=None, release_notes_ref="notes.md",
        acknowledged_non_blocking_item_ids=(), supporting_evidence_refs=(),
        authorized_by=ReleaseActor("owner","Owner","human","release_owner"),
        authorized_at=datetime(2026,9,18,8,0,tzinfo=timezone.utc), supersedes=supersedes,
    )


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo=FileProductionAuthorizationRepository(Path(self.tmp.name)/"client")

    def test_create_and_list(self):
        path=self.repo.create(authorization())
        before=path.read_bytes()
        self.assertEqual([1],[a.authorization_version for a in self.repo.list("client","production")])
        self.assertEqual(before,path.read_bytes())

    def test_duplicate_rejected_without_overwrite(self):
        path=self.repo.create(authorization())
        before=path.read_bytes()
        with self.assertRaises(ProductionAuthorizationVersionConflict):
            self.repo.create(authorization())
        self.assertEqual(before,path.read_bytes())

    def test_out_of_order_rejected(self):
        with self.assertRaises(ProductionAuthorizationVersionConflict):
            self.repo.create(authorization(version=2,supersedes=1))

    def test_environment_streams_are_independent(self):
        self.repo.create(authorization(environment="production"))
        self.repo.create(authorization(environment="staging"))
        self.assertEqual(1,len(self.repo.list("client","production")))
        self.assertEqual(1,len(self.repo.list("client","staging")))


if __name__=="__main__":
    unittest.main()
