from __future__ import annotations

import shutil
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tooling.workflow.execution import (
    IllegalStageTransition,
    StageCompletionGateFailed,
    StagePrerequisiteFailed,
)
from tooling.workflow.initialize_client import initialize_client
from tooling.workflow.lease import WorkflowLeaseConflict
from tooling.workflow.manifests import (
    ValidatorEvidence,
    load_manifest,
    manifest_path,
    manifest_relpath,
)
from tooling.workflow.runner import (
    StageRun,
    WorkflowRunStatus,
    checkpoint_stage,
    complete_stage,
    fail_stage,
    inspect_client,
    resume_stage,
    start_stage,
)
from tooling.workflow.state import STAGES, load_state, save_state


ROOT = Path(__file__).resolve().parents[2]
COMMIT = "0" * 40
AT = "2026-09-17T00:00:00Z"
NOW_ISO = "2026-09-17T12:00:00Z"
NOW = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)


def _root(tmp: str) -> Path:
    root = Path(tmp)
    (root / "client-projects").mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "workflows" / "contracts", root / "workflows" / "contracts")
    shutil.copytree(
        ROOT / "client-projects" / "schema" / "input",
        root / "client-projects" / "schema" / "input",
    )
    return root


def _client(root: Path) -> Path:
    return initialize_client(root, "acme", "Acme")


def _snapshot(client: Path) -> dict[str, tuple[bytes, int]]:
    return {
        path.relative_to(client).as_posix(): (
            path.read_bytes(),
            path.stat().st_mtime_ns,
        )
        for path in sorted(client.rglob("*"))
        if path.is_file()
    }


def _passed(name: str) -> ValidatorEvidence:
    return ValidatorEvidence(name=name, status="passed", at=AT)


class InspectClientTests(unittest.TestCase):
    def test_inspect_client_on_a_fresh_client_reports_intake_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            status = inspect_client(root, client, now=NOW)

            self.assertIsInstance(status, WorkflowRunStatus)
            self.assertEqual("acme", status.client_id)
            self.assertEqual("client-intake", status.current_stage)
            self.assertEqual("not_started", status.status)
            self.assertEqual((), status.completed)
            self.assertEqual((), status.skipped)
            self.assertEqual(tuple(STAGES), status.pending)
            self.assertIsNone(status.active_run_id)
            self.assertIsNone(status.attempt)
            self.assertIsNone(status.stage_status)
            self.assertIsNone(status.last_checkpoint)
            self.assertIsNone(status.lease_owner)
            self.assertIsNone(status.lease_expires_at)
            self.assertFalse(status.lease_expired)
            self.assertEqual("none", status.recovery_action)
            self.assertEqual("client-intake", status.next_stage)
            self.assertEqual("ready", status.next_status)
            self.assertIsNone(status.next_reason)
            self.assertIsNone(status.manifest_ref)

    def test_inspect_client_performs_no_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            start_stage(root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW)
            before = _snapshot(client)

            status = inspect_client(root, client, now=NOW)

            self.assertEqual("client-intake", status.current_stage)
            self.assertEqual(before, _snapshot(client))


class StartStageTests(unittest.TestCase):
    def test_start_stage_returns_in_progress_manifest_and_active_lease(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)

            run = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )

            self.assertIsInstance(run, StageRun)
            self.assertEqual("client-intake", run.manifest.stage)
            self.assertEqual("in_progress", run.manifest.status)
            self.assertEqual(1, run.manifest.attempt)
            self.assertIsNotNone(run.lease)
            self.assertEqual("opencode:test", run.lease.owner)
            self.assertEqual(run.manifest.run_id, run.status.active_run_id)
            self.assertEqual(1, run.status.attempt)
            self.assertEqual("in_progress", run.status.stage_status)
            self.assertEqual("opencode:test", run.status.lease_owner)
            self.assertFalse(run.status.lease_expired)
            self.assertEqual(
                manifest_relpath(run.manifest.run_id, 1), run.status.manifest_ref
            )
            self.assertTrue(
                manifest_path(client, run.manifest.run_id, 1).exists()
            )

    def test_start_stage_reuse_does_not_create_a_second_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )
            complete_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                actor="opencode:test",
                validator_results=(_passed("client-input-contract"),),
                at=NOW,
            )

            state = load_state(client / "workflow-state.yaml")
            state["current_stage"] = "client-intake"
            state["status"] = "in_progress"
            save_state(client / "workflow-state.yaml", state)

            reused = start_stage(
                root,
                client,
                actor="opencode:test",
                source_commit_sha=COMMIT,
                now=NOW + timedelta(minutes=5),
            )

            self.assertEqual(started.manifest.run_id, reused.manifest.run_id)
            self.assertEqual(1, reused.manifest.attempt)
            self.assertEqual("completed", reused.manifest.status)
            manifests = sorted(
                (client / "workflow" / "executions").glob("*/attempt-*.yaml")
            )
            self.assertEqual(1, len(manifests))

    def test_start_stage_is_blocked_when_prerequisites_are_unmet(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            state = load_state(client / "workflow-state.yaml")
            state["current_stage"] = "resolve-intelligence"
            save_state(client / "workflow-state.yaml", state)

            with self.assertRaises(StagePrerequisiteFailed):
                start_stage(
                    root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
                )


class CheckpointStageTests(unittest.TestCase):
    def test_checkpoint_stage_records_the_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )

            run = checkpoint_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                checkpoint="intake-complete",
                actor="opencode:test",
                at=NOW,
            )

            self.assertEqual("intake-complete", run.manifest.checkpoints[-1].name)
            self.assertEqual("intake-complete", run.status.last_checkpoint)
            on_disk = load_manifest(
                manifest_path(client, started.manifest.run_id, 1)
            )
            self.assertEqual("intake-complete", on_disk.checkpoints[-1].name)
            self.assertEqual("in_progress", on_disk.status)

    def test_checkpoint_stage_rejects_an_undeclared_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )

            with self.assertRaises(IllegalStageTransition):
                checkpoint_stage(
                    root,
                    client,
                    run_id=started.manifest.run_id,
                    checkpoint="not-a-checkpoint",
                    actor="opencode:test",
                    at=NOW,
                )


class CompleteStageTests(unittest.TestCase):
    def test_complete_stage_advances_and_releases_the_lease(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )

            run = complete_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                actor="opencode:test",
                validator_results=(_passed("client-input-contract"),),
                at=NOW,
            )

            self.assertEqual("resolve-intelligence", run.status.current_stage)
            self.assertIn("client-intake", run.status.completed)
            self.assertNotIn("client-intake", run.status.pending)
            self.assertIsNone(run.status.lease_owner)
            self.assertIsNone(run.lease)
            self.assertEqual("completed", run.manifest.status)
            self.assertEqual("resolve-intelligence", run.status.next_stage)

    def test_complete_stage_rejects_a_failing_validator(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )

            with self.assertRaises(StageCompletionGateFailed):
                complete_stage(
                    root,
                    client,
                    run_id=started.manifest.run_id,
                    actor="opencode:test",
                    validator_results=(
                        ValidatorEvidence(
                            name="client-input-contract", status="failed", at=AT
                        ),
                    ),
                    at=NOW,
                )

            status = inspect_client(root, client, now=NOW)
            self.assertEqual("client-intake", status.current_stage)
            self.assertNotIn("client-intake", status.completed)
            self.assertEqual("in_progress", status.stage_status)
            self.assertIsNotNone(status.lease_owner)


class FailStageTests(unittest.TestCase):
    def test_fail_stage_records_failure_evidence_and_does_not_advance(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:test", source_commit_sha=COMMIT, now=NOW
            )

            run = fail_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                reason="boom",
                actor="opencode:test",
                at=NOW,
            )

            self.assertEqual("client-intake", run.status.current_stage)
            self.assertNotIn("client-intake", run.status.completed)
            self.assertEqual("failed", run.manifest.status)
            self.assertIsNone(run.status.lease_owner)
            on_disk = load_manifest(
                manifest_path(client, started.manifest.run_id, 1)
            )
            self.assertEqual("failed", on_disk.status)
            self.assertEqual("boom", on_disk.failure_reason)
            self.assertEqual(NOW_ISO, on_disk.completed_at)


class ResumeStageTests(unittest.TestCase):
    def test_resume_stage_after_an_expired_lease_keeps_the_same_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:session-a", source_commit_sha=COMMIT, now=NOW
            )
            checkpoint_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                checkpoint="intake-complete",
                actor="opencode:session-a",
                at=NOW,
            )

            run = resume_stage(
                root,
                client,
                actor="opencode:session-a",
                source_commit_sha=COMMIT,
                now=NOW + timedelta(minutes=31),
            )

            self.assertEqual(started.manifest.run_id, run.status.active_run_id)
            self.assertEqual(1, run.status.attempt)
            self.assertEqual("in_progress", run.manifest.status)
            self.assertEqual("intake-complete", run.status.last_checkpoint)
            self.assertIsNotNone(run.lease)
            self.assertFalse(run.status.lease_expired)

    def test_resume_stage_reports_a_foreign_live_lease_as_recovery_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            started = start_stage(
                root, client, actor="opencode:session-a", source_commit_sha=COMMIT, now=NOW
            )
            checkpoint_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                checkpoint="intake-complete",
                actor="opencode:session-a",
                at=NOW,
            )

            from tooling.workflow.runner import RecoveryRequired

            with self.assertRaises(RecoveryRequired):
                resume_stage(
                    root,
                    client,
                    actor="opencode:session-b",
                    source_commit_sha=COMMIT,
                    now=NOW + timedelta(minutes=1),
                )


class ConcurrencyTests(unittest.TestCase):
    def test_second_owner_is_rejected_and_mutates_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            start_stage(
                root, client, actor="opencode:session-a", source_commit_sha=COMMIT, now=NOW
            )
            before = _snapshot(client)

            with self.assertRaises(WorkflowLeaseConflict):
                start_stage(
                    root,
                    client,
                    actor="opencode:session-b",
                    source_commit_sha=COMMIT,
                    now=NOW,
                )

            self.assertEqual(before, _snapshot(client))


if __name__ == "__main__":
    unittest.main()
