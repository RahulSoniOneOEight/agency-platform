from __future__ import annotations

import copy
import shutil
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tooling.workflow.lease import acquire_lease
from tooling.workflow.manifests import (
    ArtifactRef,
    ExecutionManifest,
    ValidatorEvidence,
    manifest_path,
    write_manifest_create_only,
)
from tooling.workflow.recovery import (
    RecoveryAction,
    RecoveryDecision,
    inspect_recovery,
)
from tooling.workflow.state import initial_state


ROOT = Path(__file__).resolve().parents[2]
COMMIT = "0" * 40
AT = "2026-09-17T00:00:00Z"
NOW = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)
OWNER = "opencode:session-a"
RUN_ID = "wf-acme-20260917T120000Z-abc12345"


def _root(tmp: str) -> Path:
    root = Path(tmp)
    (root / "client-projects").mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "workflows" / "contracts", root / "workflows" / "contracts")
    return root


def _client(root: Path) -> Path:
    client = root / "client-projects" / "acme"
    client.mkdir(parents=True, exist_ok=True)
    return client


def _manifest(
    *,
    stage: str = "client-intake",
    run_id: str = RUN_ID,
    attempt: int = 1,
    status: str = "in_progress",
    checkpoint: str | None = None,
    validator: str = "client-input-contract",
) -> ExecutionManifest:
    manifest = ExecutionManifest.start(
        run_id=run_id,
        client_id="acme",
        stage=stage,
        attempt=attempt,
        source_commit_sha=COMMIT,
        started_at=AT,
    )
    if checkpoint is not None:
        manifest = manifest.with_checkpoint(checkpoint, at=AT)
    if status == "completed":
        manifest = manifest.with_validators(
            [ValidatorEvidence(name=validator, status="passed", at=AT)]
        ).complete(at=AT, required_validators=[validator])
    elif status == "failed":
        manifest = manifest.fail(reason="boom", at=AT)
    return manifest


def _write(client: Path, manifest: ExecutionManifest) -> Path:
    path = manifest_path(client, manifest.run_id, manifest.attempt)
    write_manifest_create_only(path, manifest)
    return path


def _state(
    *,
    stage: str = "client-intake",
    stage_state: dict | None = None,
    completed: list | None = None,
    status: str = "in_progress",
    active_lease: dict | None = None,
) -> dict:
    state = initial_state("acme")
    state["current_stage"] = stage
    state["status"] = status
    if stage_state is not None:
        state["stage_state"] = stage_state
    if completed is not None:
        state["completed"] = completed
    if active_lease is not None:
        state["active_lease"] = active_lease
    return state


def _snapshot(client: Path) -> dict[str, bytes]:
    return {
        path.relative_to(client).as_posix(): path.read_bytes()
        for path in sorted(client.rglob("*"))
        if path.is_file()
    }


class InspectRecoveryTests(unittest.TestCase):
    def test_block_when_state_claims_complete_without_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            state = _state(
                stage="client-intake",
                stage_state={"client-intake": {"status": "complete"}},
                completed=["client-intake"],
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.BLOCK, decision.action)
            self.assertEqual("client-intake", decision.stage)

    def test_reconcile_state_when_completed_manifest_has_stale_pointer(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            completed = _manifest(status="completed")
            _write(client, completed)
            state = _state(
                stage="client-intake",
                stage_state={"client-intake": {"status": "in_progress", "attempt": 1}},
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.RECONCILE_STATE, decision.action)
            self.assertEqual("client-intake", decision.stage)
            self.assertEqual(RUN_ID, decision.run_id)
            self.assertEqual(1, decision.attempt)

    def test_resume_when_in_progress_manifest_has_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            _write(client, _manifest(checkpoint="intake-complete"))
            state = _state(
                stage="client-intake",
                stage_state={"client-intake": {"status": "in_progress", "attempt": 1}},
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.RESUME, decision.action)
            self.assertEqual(RUN_ID, decision.run_id)
            self.assertEqual(1, decision.attempt)
            self.assertEqual("intake-complete", decision.checkpoint)

    def test_retry_when_in_progress_manifest_has_no_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            _write(client, _manifest())
            state = _state(
                stage="client-intake",
                stage_state={"client-intake": {"status": "in_progress", "attempt": 1}},
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.RETRY, decision.action)
            self.assertIsNone(decision.checkpoint)

    def test_retry_when_lease_expired_with_unfinished_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            state = _state(stage="client-intake")
            leased_state, _ = acquire_lease(
                state, owner=OWNER, run_id=RUN_ID, now=NOW, ttl_seconds=1800
            )
            decision = inspect_recovery(
                root, client, leased_state, now=NOW + timedelta(minutes=31)
            )
            self.assertEqual(RecoveryAction.RETRY, decision.action)
            self.assertEqual(RUN_ID, decision.run_id)

    def test_none_for_clean_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            decision = inspect_recovery(
                root, client, _state(stage="client-intake"), now=NOW
            )
            self.assertEqual(RecoveryAction.NONE, decision.action)
            self.assertEqual("client-intake", decision.stage)

    def test_none_when_completed_manifest_matches_complete_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            _write(client, _manifest(status="completed"))
            state = _state(
                stage="client-intake",
                stage_state={"client-intake": {"status": "complete", "attempt": 1}},
                completed=["client-intake"],
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.NONE, decision.action)

    def test_expired_lease_without_unfinished_work_is_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            state = _state(stage="productionize", status="complete", completed=["productionize"])
            leased_state, _ = acquire_lease(
                state, owner=OWNER, run_id=RUN_ID, now=NOW, ttl_seconds=1800
            )
            decision = inspect_recovery(
                root, client, leased_state, now=NOW + timedelta(minutes=31)
            )
            self.assertEqual(RecoveryAction.NONE, decision.action)


class PointerAheadTests(unittest.TestCase):
    def test_pointer_ahead_of_prerequisites_blocks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            state = _state(
                stage="build-prototype",
                status="in_progress",
                completed=["client-intake"],
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.BLOCK, decision.action)
            self.assertIn("prerequisites not completed", decision.reason)

    def test_completed_workflow_is_not_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            state = _state(
                stage="productionize",
                status="complete",
                completed=["productionize"],
            )
            decision = inspect_recovery(root, client, state, now=NOW)
            self.assertEqual(RecoveryAction.NONE, decision.action)


class PureReadTests(unittest.TestCase):
    def test_inspect_recovery_does_not_mutate_state_or_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            _write(client, _manifest(checkpoint="intake-complete"))
            state = _state(
                stage="client-intake",
                stage_state={"client-intake": {"status": "in_progress", "attempt": 1}},
            )
            state_before = copy.deepcopy(state)
            files_before = _snapshot(client)

            decision = inspect_recovery(root, client, state, now=NOW)

            self.assertEqual(RecoveryAction.RESUME, decision.action)
            self.assertEqual(state_before, state)
            self.assertEqual(files_before, _snapshot(client))

    def test_decision_is_a_frozen_value_object(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            decision = inspect_recovery(
                root, client, _state(stage="client-intake"), now=NOW
            )
            self.assertIsInstance(decision, RecoveryDecision)
            with self.assertRaises(Exception):
                decision.stage = "other"  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
