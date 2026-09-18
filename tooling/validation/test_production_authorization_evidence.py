from __future__ import annotations

import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from tooling.production_authorization.evidence import (
    evidence_freshness_errors, load_release_candidate, require_fresh_evidence
)
from tooling.production_authorization.errors import (
    InvalidReleaseCandidate, ProductionAuthorizationEvidenceMissing, ProductionAuthorizationEvidenceStale
)
from tooling.production_authorization.models import EvidenceRef, ReleaseCandidate, canonical_json

SHA="1"*40; HASH="sha256:"+"a"*64

def ev(eid,cat,sha=SHA,build=HASH,status="passed"):
    return EvidenceRef(eid,cat,status,"test",sha,build)

def candidate():
    return ReleaseCandidate(
      "client","production",2,"sha256:"+"b"*64,"2"*40,SHA,"build",HASH,True,(),
      (ev("qa","qa"),),(ev("repo","validator"),),
      (ev("dependency-check","security"),ev("secret-scan","security"),ev("configuration-review","security")),
      "rollback.md",False,None,"notes.md"
    )

class EvidenceTests(unittest.TestCase):
    def test_load_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"candidate.json"; path.write_text(canonical_json(candidate()),encoding="utf-8")
            self.assertEqual(candidate(),load_release_candidate(path))

    def test_missing_candidate_rejected(self):
        with self.assertRaises(ProductionAuthorizationEvidenceMissing):
            load_release_candidate(Path("definitely-missing.json"))

    def test_malformed_candidate_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"candidate.json"; path.write_text("[]",encoding="utf-8")
            with self.assertRaises(InvalidReleaseCandidate):
                load_release_candidate(path)

    def test_stale_qa_detected(self):
        value=replace(candidate(),qa_evidence=(ev("qa","qa",sha="3"*40),))
        self.assertIn("qa_evidence_stale",evidence_freshness_errors(value))
        with self.assertRaises(ProductionAuthorizationEvidenceStale):
            require_fresh_evidence(value)

    def test_fresh_evidence_passes(self):
        self.assertEqual([],evidence_freshness_errors(candidate()))
        require_fresh_evidence(candidate())


if __name__=="__main__":
    unittest.main()
