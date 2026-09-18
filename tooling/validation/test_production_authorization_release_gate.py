from __future__ import annotations
import unittest
from dataclasses import replace
from datetime import datetime,timezone
from pathlib import Path
from tooling.production_authorization.errors import ProductionAuthorizationCandidateMismatch,ProductionAuthorizationEnvironmentMismatch,ProductionAuthorizationInvalidated
from tooling.production_authorization.models import ReleaseActor
from tooling.production_authorization.reference_client import build_reference_candidate
from tooling.production_authorization.repository import FileProductionAuthorizationRepository
from tooling.production_authorization.release_gate import verify_release_gate
from tooling.production_authorization.validity import AuthorizationEvent

ROOT=Path(__file__).resolve().parents[2]
CLIENT=ROOT/"client-projects"/"reference-commerce"

class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.candidate=build_reference_candidate(ROOT)
        self.authorization=FileProductionAuthorizationRepository(CLIENT).list("reference-commerce","production")[-1]

    def test_exact_candidate_passes(self):
        verify_release_gate(self.authorization,self.candidate)

    def test_sha_mismatch_fails(self):
        with self.assertRaises(ProductionAuthorizationCandidateMismatch):
            verify_release_gate(self.authorization,replace(self.candidate,source_commit_sha="f"*40))

    def test_environment_mismatch_fails(self):
        with self.assertRaises(ProductionAuthorizationEnvironmentMismatch):
            verify_release_gate(self.authorization,replace(self.candidate,environment="staging"))

    def test_invalidation_event_fails(self):
        event=AuthorizationEvent(
            "event-1",self.authorization.authorization_id,"invalidated","manual halt",
            ReleaseActor("owner","Owner","human","release_owner"),
            datetime(2026,9,18,11,0,tzinfo=timezone.utc),
        )
        with self.assertRaises(ProductionAuthorizationInvalidated):
            verify_release_gate(self.authorization,self.candidate,(event,))

if __name__=="__main__":
    unittest.main()
