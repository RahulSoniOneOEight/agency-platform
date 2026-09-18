"""End-to-end interruption/resume proof for the reference client (Milestone F.3).

The scenario under test drives the *existing* Milestone E workflow runtime
(``tooling.workflow.runner``) on a temp copy of the committed reference client
(RF4/RF9). It proves that a controlled interruption of a state-mutating stage is
resumed deterministically by a fresh runner using repository state alone, with
no chat/session memory, and that the committed evidence is byte-reproducible.

The temp workspace is deleted in cleanup and the committed reference client is
never modified; its tree hash is asserted unchanged around the scenario run.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tooling.reference_client.scenario import (
    canonical_resume_evidence,
    run_resume_scenario,
    validate_resume_evidence,
    write_resume_evidence,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
EVIDENCE_PATH = (
    CLIENT / "reference-e2e" / "evidence" / "resume-evidence.json"
)


def _tree_hash(root: Path) -> str:
    """Deterministic content hash of a directory tree (path + bytes)."""
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _passed_ids(evidence: dict) -> set[str]:
    return {
        entry["id"]
        for entry in evidence["assertions"]
        if isinstance(entry, dict) and entry.get("passed") is True
    }


class ReferenceClientResumeEndToEndTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp(prefix="reference-resume-")
        self.addCleanup(shutil.rmtree, self._tmp, True)
        self.root = Path(self._tmp)

    def test_scenario_evidence_is_valid_and_all_assertions_pass(self):
        evidence = run_resume_scenario(self.root)
        self.assertEqual([], validate_resume_evidence(evidence))
        self.assertTrue(evidence["assertions"])
        failed = [
            entry
            for entry in evidence["assertions"]
            if entry.get("passed") is not True
        ]
        self.assertEqual([], failed)

    def test_committed_evidence_is_byte_identical_to_a_fresh_run(self):
        committed = EVIDENCE_PATH.read_bytes()
        fresh = canonical_resume_evidence(run_resume_scenario(self.root)).encode(
            "utf-8"
        )
        self.assertEqual(committed, fresh)

        # Determinism: an independent temp workspace reproduces the same bytes.
        second_root = Path(tempfile.mkdtemp(prefix="reference-resume-2-"))
        self.addCleanup(shutil.rmtree, second_root, True)
        second = canonical_resume_evidence(
            run_resume_scenario(second_root)
        ).encode("utf-8")
        self.assertEqual(fresh, second)

    def test_write_resume_evidence_matches_committed_bytes(self):
        destination = self.root / "out" / "resume-evidence.json"
        write_resume_evidence(
            self.root,
            self.root / "client-projects" / "reference-commerce",
            destination,
        )
        self.assertEqual(EVIDENCE_PATH.read_bytes(), destination.read_bytes())

    def test_committed_evidence_validates(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        self.assertEqual([], validate_resume_evidence(evidence))

    def test_interruption_path_does_not_advance_before_completion(self):
        evidence = run_resume_scenario(self.root)
        self.assertEqual("visual-qa", evidence["stage"])
        self.assertTrue(evidence["interruption"]["lease_expired"])
        self.assertEqual("resume", evidence["interruption"]["recovery_action"])
        self.assertTrue(evidence["resume"]["same_attempt"])
        self.assertTrue(evidence["resume"]["lease_reclaimed"])
        self.assertEqual(1, evidence["resume"]["manifest_count_for_stage"])
        self.assertGreaterEqual(evidence["resume"]["audit_records"], 1)
        self.assertEqual("client-review", evidence["completion"]["advanced_to"])
        self.assertEqual("visual-qa", evidence["completion"]["last_transition_from"])
        self.assertIn("visual-qa", evidence["completion"]["completed_stages"])
        self.assertTrue(evidence["completion"]["lease_released"])

        passed = _passed_ids(evidence)
        for assertion_id in (
            "interruption.stage_not_advanced",
            "interruption.checkpoint_survives",
            "interruption.attempt_preserved",
            "resume.same_attempt",
            "resume.lease_reclaimed_audited",
            "final.exactly_one_completed_manifest",
        ):
            self.assertIn(assertion_id, passed)

    def test_retry_path_starts_attempt_two_with_prior_manifest_unchanged(self):
        evidence = run_resume_scenario(self.root)
        self.assertEqual("retry", evidence["retry"]["recovery_action"])
        self.assertEqual(2, evidence["retry"]["attempt"])
        self.assertTrue(evidence["retry"]["prior_manifest_unchanged"])
        passed = _passed_ids(evidence)
        self.assertIn("retry.new_attempt", passed)
        self.assertIn("retry.prior_manifest_in_progress", passed)

    def test_no_chat_memory_required_and_state_rederived_from_disk(self):
        evidence = run_resume_scenario(self.root)
        self.assertTrue(evidence["no_chat_memory_required"])
        self.assertIn("final.state_rederived_from_disk", _passed_ids(evidence))

    def test_committed_reference_client_is_never_modified(self):
        before = _tree_hash(CLIENT)
        run_resume_scenario(self.root)
        self.assertEqual(before, _tree_hash(CLIENT))

    def test_tampered_same_attempt_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        self.assertEqual([], validate_resume_evidence(evidence))
        evidence["resume"]["same_attempt"] = False
        errors = validate_resume_evidence(evidence)
        self.assertTrue(any("same_attempt" in error for error in errors), errors)

    def test_tampered_no_chat_memory_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        evidence["no_chat_memory_required"] = False
        errors = validate_resume_evidence(evidence)
        self.assertTrue(
            any("no_chat_memory_required" in error for error in errors), errors
        )

    def test_tampered_completion_target_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        evidence["completion"]["advanced_to"] = "productionize"
        errors = validate_resume_evidence(evidence)
        self.assertTrue(
            any("completion.advanced_to" in error for error in errors), errors
        )

    def test_tampered_retry_attempt_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        evidence["retry"]["attempt"] = 1
        evidence["retry"]["prior_manifest_unchanged"] = False
        errors = validate_resume_evidence(evidence)
        self.assertTrue(
            any("retry.attempt" in error for error in errors), errors
        )
        self.assertTrue(
            any("prior_manifest_unchanged" in error for error in errors), errors
        )

    def test_failing_assertion_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        evidence["assertions"][0]["passed"] = False
        errors = validate_resume_evidence(evidence)
        self.assertTrue(any("passed true" in error for error in errors), errors)

    def test_missing_required_key_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        del evidence["stage"]
        errors = validate_resume_evidence(evidence)
        self.assertTrue(
            any("missing required key: stage" in error for error in errors), errors
        )

    def test_subjective_score_key_is_rejected(self):
        evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        evidence["overall_score"] = 0.9
        errors = validate_resume_evidence(evidence)
        self.assertTrue(
            any("subjective score key" in error for error in errors), errors
        )


if __name__ == "__main__":
    unittest.main()
