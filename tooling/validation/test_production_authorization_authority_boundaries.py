from __future__ import annotations
import inspect
import json
import unittest
from pathlib import Path
from tooling.production_authorization.models import ReleaseActor
from tooling.production_authorization.reference_client import build_reference_candidate
from tooling.production_authorization.validate import validate_client_authorizations

ROOT=Path(__file__).resolve().parents[2]
CLIENT=ROOT/"client-projects"/"reference-commerce"

class AuthorityBoundaryTests(unittest.TestCase):
    def test_reference_fixture_is_valid_without_deployment(self):
        self.assertEqual([],validate_client_authorizations(ROOT,CLIENT))
        proof=json.loads((CLIENT/"release"/"authorization-proof.json").read_text(encoding="utf-8"))
        self.assertFalse(proof["production_deployment_performed"])

    def test_agents_and_ci_are_not_human_release_owners(self):
        self.assertFalse(ReleaseActor("a","Agent","agent","release_owner").is_human_release_owner)
        self.assertFalse(ReleaseActor("ci","CI","ci","release_owner").is_human_release_owner)
        self.assertTrue(ReleaseActor("h","Human","human","release_owner").is_human_release_owner)

    def test_g_does_not_import_existing_authorities(self):
        import tooling.production_authorization.coordinator as coordinator
        source=inspect.getsource(coordinator)
        for forbidden in ("ReviewState","ApprovalSnapshot","QAFinding","workflow-state"):
            self.assertNotIn(forbidden,source)

    def test_reference_candidate_consumes_f_report_by_reference(self):
        candidate=build_reference_candidate(ROOT)
        self.assertTrue(any(ref.endswith("reference-report.json") for ref in candidate.supporting_evidence_refs))

if __name__=="__main__":
    unittest.main()
