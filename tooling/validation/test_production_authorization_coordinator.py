from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path

from tooling.production_authorization.coordinator import ProductionAuthorizationCoordinator
from tooling.production_authorization.errors import (
    ProductionAuthorizationActorNotAllowed, ProductionAuthorizationNotEligible
)
from tooling.production_authorization.models import EvidenceRef, ReleaseActor, ReleaseCandidate
from tooling.production_authorization.repository import FileProductionAuthorizationRepository

SHA="1"*40
HASH="sha256:"+"a"*64

def ev(eid,cat):
    return EvidenceRef(eid,cat,"passed","test",SHA,HASH)

def candidate():
    return ReleaseCandidate(
      "client","production",2,"sha256:"+"b"*64,"2"*40,SHA,"build",HASH,True,(),
      (ev("qa","qa"),),(ev("repo","validator"),),
      (ev("dependency-check","security"),ev("secret-scan","security"),ev("configuration-review","security")),
      "rollback.md",False,None,"notes.md"
    )

class CoordinatorTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.repo=FileProductionAuthorizationRepository(Path(self.tmp.name)/"client")
        self.coordinator=ProductionAuthorizationCoordinator(self.repo)
        self.human=ReleaseActor("owner","Owner","human","release_owner")
        self.at=datetime(2026,9,18,8,0,tzinfo=timezone.utc)

    def test_human_authorizes_eligible_candidate(self):
        value=self.coordinator.authorize(candidate(),actor=self.human,authorized_at=self.at)
        self.assertEqual(1,value.authorization_version)
        self.assertEqual(1,len(self.repo.list("client","production")))

    def test_agent_and_ci_cannot_authorize(self):
        for kind in ("agent","ci"):
            with self.assertRaises(ProductionAuthorizationActorNotAllowed):
                self.coordinator.authorize(candidate(),actor=ReleaseActor(kind,kind,kind,"release_owner"),authorized_at=self.at)
        self.assertEqual([],self.repo.list("client","production"))

    def test_ineligible_candidate_writes_nothing(self):
        bad=replace(candidate(),approval_current=False)
        with self.assertRaises(ProductionAuthorizationNotEligible):
            self.coordinator.authorize(bad,actor=self.human,authorized_at=self.at)
        self.assertEqual([],self.repo.list("client","production"))

    def test_versions_are_monotonic_and_supersede(self):
        first=self.coordinator.authorize(candidate(),actor=self.human,authorized_at=self.at)
        second=self.coordinator.authorize(candidate(),actor=self.human,authorized_at=self.at)
        self.assertEqual(2,second.authorization_version)
        self.assertEqual(first.authorization_version,second.supersedes)


if __name__=="__main__":
    unittest.main()
