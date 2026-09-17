from __future__ import annotations

import shutil
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tooling.workflow.execution import StageCompletionGateFailed
from tooling.workflow.initialize_client import initialize_client
from tooling.workflow.lease import WorkflowLeaseConflict
from tooling.workflow.manifests import (
    ExecutionManifest,
    ValidatorEvidence,
    load_manifest,
    manifest_path,
    write_manifest_create_only,
)
from tooling.workflow.runner import (
    checkpoint_stage,
    complete_stage,
    inspect_client,
    reconcile_state,
    resume_stage,
    start_stage,
)
from tooling.workflow.state import load_state, save_state


ROOT = Path(__file__).resolve().parents[2]
COMMIT = "0" * 40
AT = "2026-09-17T00:00:00Z"
NOW = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)
ACTOR = "opencode:session-a"


def _root(tmp: str) -> Path:
    """Build the same temp-root fixture as WorkflowExecutionTests._root.

    Real stage contracts plus the real client-input schemas (the router's
    intake validation reads them from the repository root) and a real client
    initialized through ``initialize_client``.
    """
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


def _snapshot(client: Path) -> dict[str, bytes]:
    return {
        path.relative_to(client).as_posix(): path.read_bytes()
        for path in sorted(client.rglob("*"))
        if path.is_file()
    }


def _passed(name: str) -> ValidatorEvidence:
    return ValidatorEvidence(name=name, status="passed", at=AT)


def _attempt_paths(client: Path) -> list[Path]:
    return sorted((client / "workflow" / "executions").rglob("attempt-*.yaml"))


class ResumeEndToEndTests(unittest.TestCase):
    def test_scenario_a_fresh_session_normal_continuation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)

            started = start_stage(
                root, client, actor=ACTOR, source_commit_sha=COMMIT, now=NOW
            )
            complete_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                actor=ACTOR,
                validator_results=(_passed("client-input-contract"),),
                at=NOW,
            )

            # Discard every in-memory controller object: reload from files only.
            del started

            status = inspect_client(root, client, now=NOW + timedelta(minutes=1))

            self.assertEqual("resolve-intelligence", status.current_stage)
            self.assertEqual("resolve-intelligence", status.next_stage)
            self.assertEqual("ready", status.next_status)
            self.assertIn("client-intake", status.completed)
            self.assertNotIn("client-intake", status.pending)
            self.assertIsNone(status.lease_owner)
            self.assertEqual("none", status.recovery_action)

    def test_scenario_b_interruption_after_a_checkpoint_resumes_same_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)

            started = start_stage(
                root, client, actor=ACTOR, source_commit_sha=COMMIT, now=NOW
            )
            checkpoint_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                checkpoint="intake-complete",
                actor=ACTOR,
                at=NOW,
            )
            # Process death: the attempt is never completed and the lease lapses.
            before = _snapshot(client)

            resumed = resume_stage(
                root,
                client,
                actor=ACTOR,
                source_commit_sha=COMMIT,
                now=NOW + timedelta(minutes=31),
            )

            self.assertEqual(started.manifest.run_id, resumed.status.active_run_id)
            self.assertEqual(1, resumed.status.attempt)
            self.assertEqual("intake-complete", resumed.status.last_checkpoint)
            self.assertEqual("in_progress", resumed.manifest.status)
            self.assertEqual("intake-complete", resumed.manifest.checkpoints[-1].name)
            self.assertIsNotNone(resumed.lease)
            self.assertFalse(resumed.status.lease_expired)

            # No duplicate immutable artifact: still exactly one attempt, and no
            # completed manifest was fabricated by the resume.
            attempts = _attempt_paths(client)
            self.assertEqual(1, len(attempts))
            self.assertEqual("in_progress", load_manifest(attempts[0]).status)
            # The pre-existing evidence was preserved verbatim.
            self.assertEqual(
                before[attempts[0].relative_to(client).as_posix()],
                attempts[0].read_bytes(),
            )

    def test_scenario_c_reconcile_a_stale_pointer_exactly_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)

            # A valid, frozen, completed manifest exists ...
            completed = (
                ExecutionManifest.start(
                    run_id="wf-acme-20260917T120000Z-abc12345",
                    client_id="acme",
                    stage="client-intake",
                    attempt=1,
                    source_commit_sha=COMMIT,
                    started_at=AT,
                )
                .with_checkpoint("intake-complete", at=AT)
                .with_validators([_passed("client-input-contract")])
                .complete(at=AT, required_validators=["client-input-contract"])
            )
            write_manifest_create_only(
                manifest_path(client, completed.run_id, completed.attempt), completed
            )
            # ... but the canonical pointer still sits on the old stage.
            state = load_state(client / "workflow-state.yaml")
            state["current_stage"] = "client-intake"
            state["status"] = "in_progress"
            state["stage_state"] = {
                "client-intake": {"attempt": 1, "status": "in_progress"}
            }
            save_state(client / "workflow-state.yaml", state)

            inspected = inspect_client(root, client, now=NOW)
            self.assertEqual("reconcile_state", inspected.recovery_action)

            first = reconcile_state(root, client, actor=ACTOR, now=NOW)
            self.assertEqual("resolve-intelligence", first.status.current_stage)
            self.assertIn("client-intake", first.status.completed)
            self.assertNotIn("client-intake", first.status.pending)
            self.assertEqual("none", first.status.recovery_action)

            # A second call is a no-op: nothing is written again.
            frozen = (client / "workflow-state.yaml").read_bytes()
            second = reconcile_state(root, client, actor=ACTOR, now=NOW)
            self.assertEqual(frozen, (client / "workflow-state.yaml").read_bytes())
            self.assertEqual("resolve-intelligence", second.status.current_stage)
            self.assertEqual("none", second.status.recovery_action)

    def test_scenario_d_changed_inputs_create_a_new_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            profile = client / "derived" / "client-profile.yaml"

            started = start_stage(
                root, client, actor=ACTOR, source_commit_sha=COMMIT, now=NOW
            )
            complete_stage(
                root,
                client,
                run_id=started.manifest.run_id,
                actor=ACTOR,
                validator_results=(_passed("client-input-contract"),),
                at=NOW,
            )
            prior_path = manifest_path(client, started.manifest.run_id, 1)
            prior_bytes = prior_path.read_bytes()

            # Operator re-runs the same stage after a contract-relevant input changed.
            state = load_state(client / "workflow-state.yaml")
            state["current_stage"] = "client-intake"
            state["status"] = "in_progress"
            save_state(client / "workflow-state.yaml", state)
            profile.write_text(
                "id: acme\ndisplay_name: Acme\nbusiness_model: b2b\n",
                encoding="utf-8",
            )

            rerun = start_stage(
                root,
                client,
                actor=ACTOR,
                source_commit_sha=COMMIT,
                now=NOW + timedelta(minutes=5),
            )

            self.assertEqual("client-intake", rerun.manifest.stage)
            self.assertEqual(2, rerun.manifest.attempt)
            self.assertNotEqual(started.manifest.run_id, rerun.manifest.run_id)
            self.assertEqual(prior_bytes, prior_path.read_bytes())

    def test_scenario_e_concurrent_ownership_is_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)

            start_stage(root, client, actor=ACTOR, source_commit_sha=COMMIT, now=NOW)
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

    def test_scenario_f_workflow_advances_only_after_validator_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)

            started = start_stage(
                root, client, actor=ACTOR, source_commit_sha=COMMIT, now=NOW
            )

            with self.assertRaises(StageCompletionGateFailed):
                complete_stage(
                    root,
                    client,
                    run_id=started.manifest.run_id,
                    actor=ACTOR,
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


if __name__ == "__main__":
    unittest.main()
