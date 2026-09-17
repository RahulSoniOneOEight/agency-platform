from __future__ import annotations

import copy
import hashlib
import shutil
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from tooling.workflow.contracts import load_stage_contract
from tooling.workflow.execution import (
    IdempotencyAction,
    IdempotencyDecision,
    complete_attempt,
    decide_idempotency,
    prior_manifests,
    start_attempt,
)
from tooling.workflow.manifests import (
    ArtifactRef,
    ExecutionManifest,
    ValidatorEvidence,
    artifacts_for_paths,
    input_identity,
    manifest_path,
    sha256_bytes,
    sha256_file,
    write_manifest_create_only,
)
from tooling.workflow.state import initial_state


ROOT = Path(__file__).resolve().parents[2]
COMMIT = "0" * 40
AT = "2026-09-17T00:00:00Z"
SHA_A = "a" * 64
SHA_B = "b" * 64
RUN_ID = "wf-acme-20260917T000000Z-abcdef12"
OTHER_RUN_ID = "wf-acme-20260917T000000Z-99999999"


def _root(tmp: str) -> Path:
    root = Path(tmp)
    (root / "client-projects").mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "workflows" / "contracts", root / "workflows" / "contracts")
    return root


def _client(root: Path) -> Path:
    client = root / "client-projects" / "acme"
    client.mkdir(parents=True, exist_ok=True)
    return client


def _start(
    *,
    stage: str = "client-intake",
    run_id: str = RUN_ID,
    attempt: int = 1,
    inputs: tuple[ArtifactRef, ...] = (),
) -> ExecutionManifest:
    return ExecutionManifest.start(
        run_id=run_id,
        client_id="acme",
        stage=stage,
        attempt=attempt,
        source_commit_sha=COMMIT,
        started_at=AT,
        inputs=inputs,
    )


def _completed(
    *,
    stage: str = "client-intake",
    run_id: str = RUN_ID,
    attempt: int = 1,
    inputs: tuple[ArtifactRef, ...] = (),
    validator: str = "client-input-contract",
) -> ExecutionManifest:
    return (
        _start(stage=stage, run_id=run_id, attempt=attempt, inputs=inputs)
        .with_validators([ValidatorEvidence(name=validator, status="passed", at=AT)])
        .complete(at=AT, required_validators=[validator])
    )


def _failed(
    *,
    stage: str = "client-intake",
    run_id: str = RUN_ID,
    attempt: int = 1,
    inputs: tuple[ArtifactRef, ...] = (),
) -> ExecutionManifest:
    return _start(stage=stage, run_id=run_id, attempt=attempt, inputs=inputs).fail(
        reason="boom", at=AT
    )


def _in_progress(
    *,
    stage: str = "client-intake",
    run_id: str = RUN_ID,
    attempt: int = 1,
    checkpoint: str | None = None,
    inputs: tuple[ArtifactRef, ...] = (),
) -> ExecutionManifest:
    manifest = _start(stage=stage, run_id=run_id, attempt=attempt, inputs=inputs)
    if checkpoint is not None:
        manifest = manifest.with_checkpoint(checkpoint, at=AT)
    return manifest


class IdentityHelperTests(unittest.TestCase):
    def test_sha256_bytes_is_bare_hex(self):
        digest = sha256_bytes(b"hello manifest\n")
        self.assertEqual(hashlib.sha256(b"hello manifest\n").hexdigest(), digest)
        self.assertEqual(64, len(digest))

    def test_input_identity_is_order_independent(self):
        a = ArtifactRef(path="a.yaml", sha256=SHA_A)
        b = ArtifactRef(path="b.yaml", sha256=SHA_B)
        self.assertEqual(input_identity([a, b]), input_identity([b, a]))

    def test_input_identity_sorted_by_path(self):
        b = ArtifactRef(path="b.yaml", sha256=SHA_B)
        a = ArtifactRef(path="a.yaml", sha256=SHA_A)
        self.assertEqual(
            (("a.yaml", SHA_A), ("b.yaml", SHA_B)), input_identity([b, a])
        )

    def test_input_identity_empty_is_empty_tuple(self):
        self.assertEqual((), input_identity([]))

    def test_artifacts_for_paths_hashes_existing_and_blank_for_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp)
            (client / "derived").mkdir()
            (client / "derived" / "client-profile.yaml").write_bytes(b"profile\n")
            refs = artifacts_for_paths(
                client, ["derived/client-profile.yaml", "derived/missing.yaml"]
            )
            self.assertEqual("derived/client-profile.yaml", refs[0].path)
            self.assertEqual(
                sha256_file(client / "derived" / "client-profile.yaml"), refs[0].sha256
            )
            self.assertEqual("derived/missing.yaml", refs[1].path)
            self.assertEqual("", refs[1].sha256)

    def test_artifacts_for_paths_uses_posix_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            refs = artifacts_for_paths(Path(tmp), ["a/b/c.yaml"])
            self.assertEqual("a/b/c.yaml", refs[0].path)


class DecideIdempotencyTests(unittest.TestCase):
    def test_identical_inputs_and_completed_manifest_reuse(self):
        refs = (ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_A),)
        prior = _completed(inputs=refs)
        contract = load_stage_contract(ROOT, "client-intake")
        decision = decide_idempotency(contract, [prior], refs)
        self.assertEqual(IdempotencyAction.REUSE, decision.action)
        self.assertEqual(RUN_ID, decision.run_id)
        self.assertEqual(1, decision.attempt)

    def test_empty_inputs_reuse_only_when_both_are_empty(self):
        contract = load_stage_contract(ROOT, "client-intake")
        both_empty = decide_idempotency(contract, [_completed()], [])
        self.assertEqual(IdempotencyAction.REUSE, both_empty.action)
        prior_with_inputs = _completed(
            inputs=(ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_A),)
        )
        mismatch = decide_idempotency(contract, [prior_with_inputs], [])
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, mismatch.action)

    def test_changed_inputs_yield_new_attempt_with_incremented_number(self):
        contract = load_stage_contract(ROOT, "client-intake")
        prior = _completed(
            inputs=(ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_A),)
        )
        decision = decide_idempotency(
            contract,
            [prior],
            [ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_B)],
            run_id=OTHER_RUN_ID,
        )
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, decision.action)
        self.assertEqual(2, decision.attempt)
        self.assertEqual(OTHER_RUN_ID, decision.run_id)

    def test_in_progress_with_checkpoint_resumes(self):
        contract = load_stage_contract(ROOT, "client-intake")
        prior = _in_progress(checkpoint="intake-complete")
        decision = decide_idempotency(contract, [prior], [])
        self.assertEqual(IdempotencyAction.RESUME, decision.action)
        self.assertEqual(RUN_ID, decision.run_id)
        self.assertEqual(1, decision.attempt)

    def test_in_progress_without_checkpoint_is_new_attempt(self):
        contract = load_stage_contract(ROOT, "client-intake")
        decision = decide_idempotency(contract, [_in_progress()], [])
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, decision.action)
        self.assertEqual(2, decision.attempt)

    def test_failed_attempt_yields_new_attempt(self):
        contract = load_stage_contract(ROOT, "client-intake")
        decision = decide_idempotency(contract, [_failed()], [])
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, decision.action)
        self.assertEqual(2, decision.attempt)

    def test_resume_requires_matching_run_when_run_supplied(self):
        contract = load_stage_contract(ROOT, "client-intake")
        prior = _in_progress(checkpoint="intake-complete")
        decision = decide_idempotency(contract, [prior], [], run_id=OTHER_RUN_ID)
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, decision.action)
        self.assertEqual(2, decision.attempt)

    def test_other_stage_manifests_are_ignored(self):
        contract = load_stage_contract(ROOT, "client-intake")
        foreign = _completed(stage="resolve-intelligence", validator="resolved-intelligence-contract")
        decision = decide_idempotency(contract, [foreign], [])
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, decision.action)
        self.assertEqual(1, decision.attempt)

    def test_new_attempt_without_run_id_returns_blank_run(self):
        contract = load_stage_contract(ROOT, "client-intake")
        decision = decide_idempotency(contract, [], [])
        self.assertEqual(IdempotencyAction.NEW_ATTEMPT, decision.action)
        self.assertEqual(1, decision.attempt)
        self.assertEqual("", decision.run_id)

    def test_decision_is_a_frozen_value_object(self):
        contract = load_stage_contract(ROOT, "client-intake")
        decision = decide_idempotency(contract, [], [])
        self.assertIsInstance(decision, IdempotencyDecision)
        with self.assertRaises(Exception):
            decision.attempt = 5  # type: ignore[misc]


class PriorManifestsTests(unittest.TestCase):
    def test_prior_manifests_filters_by_stage_and_reads_disk(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            client_intake = _completed(attempt=1)
            resolve = _completed(
                stage="resolve-intelligence",
                run_id=OTHER_RUN_ID,
                validator="resolved-intelligence-contract",
            )
            write_manifest_create_only(
                manifest_path(client, client_intake.run_id, client_intake.attempt),
                client_intake,
            )
            write_manifest_create_only(
                manifest_path(client, resolve.run_id, resolve.attempt), resolve
            )
            found = prior_manifests(client, "client-intake")
            self.assertEqual([client_intake], found)

    def test_prior_manifests_returns_empty_when_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            self.assertEqual([], prior_manifests(client, "client-intake"))


class StartAttemptIdempotencyTests(unittest.TestCase):
    def _completed_with_inputs(self, refs):
        prior = _completed(inputs=refs)
        return prior

    def test_reuse_creates_no_new_manifest_and_leaves_state_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            refs = (ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_A),)
            prior = self._completed_with_inputs(refs)
            write_manifest_create_only(
                manifest_path(client, prior.run_id, prior.attempt), prior
            )
            state = initial_state("acme")
            before = copy.deepcopy(state)

            new_state, reused = start_attempt(
                root,
                client,
                state,
                actor="tester",
                source_commit_sha=COMMIT,
                inputs=refs,
            )

            self.assertEqual(prior.run_id, reused.run_id)
            self.assertEqual(prior.attempt, reused.attempt)
            self.assertEqual("completed", reused.status)
            self.assertEqual(before, state)
            self.assertEqual(before, new_state)
            manifests = sorted(
                (client / "workflow" / "executions").glob("*/attempt-*.yaml")
            )
            self.assertEqual(1, len(manifests))

    def test_changed_inputs_create_next_attempt_and_preserve_prior_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            prior = _completed(
                inputs=(ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_A),)
            )
            prior_path = manifest_path(client, prior.run_id, prior.attempt)
            write_manifest_create_only(prior_path, prior)
            prior_bytes = prior_path.read_bytes()

            state = initial_state("acme")
            changed = (ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_B),)
            new_state, manifest = start_attempt(
                root,
                client,
                state,
                actor="tester",
                source_commit_sha=COMMIT,
                run_id=RUN_ID,
                inputs=changed,
            )

            self.assertEqual(2, manifest.attempt)
            self.assertEqual(RUN_ID, manifest.run_id)
            self.assertEqual(changed, manifest.inputs)
            self.assertEqual(prior_bytes, prior_path.read_bytes())
            self.assertTrue(
                manifest_path(client, RUN_ID, 2).exists()
            )
            self.assertEqual(2, new_state["stage_state"]["client-intake"]["attempt"])

    def test_resume_reuses_in_progress_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            prior = _in_progress(checkpoint="intake-complete")
            write_manifest_create_only(
                manifest_path(client, prior.run_id, prior.attempt), prior
            )
            state = initial_state("acme")

            new_state, resumed = start_attempt(
                root, client, state, actor="tester", source_commit_sha=COMMIT
            )

            self.assertEqual("in_progress", resumed.status)
            self.assertEqual(prior.run_id, resumed.run_id)
            self.assertEqual(1, resumed.attempt)
            self.assertEqual(("intake-complete",), tuple(c.name for c in resumed.checkpoints))
            manifests = sorted(
                (client / "workflow" / "executions").glob("*/attempt-*.yaml")
            )
            self.assertEqual(1, len(manifests))

    def test_reuse_with_default_derivation_after_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            state["current_stage"] = "resolve-intelligence"

            new_state, manifest = start_attempt(
                root,
                client,
                state,
                actor="tester",
                source_commit_sha=COMMIT,
                stage="resolve-intelligence",
            )
            (client / "resolved-intelligence.yaml").write_text(
                "active_presets: []\n", encoding="utf-8"
            )
            final_state, frozen = complete_attempt(
                root,
                client,
                new_state,
                manifest,
                validator_results=[
                    ValidatorEvidence(
                        name="resolved-intelligence-contract", status="passed", at=AT
                    )
                ],
                at=AT,
                actor="tester",
            )

            _, reused = start_attempt(
                root,
                client,
                final_state,
                actor="tester",
                source_commit_sha=COMMIT,
                stage="resolve-intelligence",
            )

            self.assertEqual(frozen.run_id, reused.run_id)
            self.assertEqual(frozen.attempt, reused.attempt)
            self.assertEqual("completed", reused.status)
            manifests = sorted(
                (client / "workflow" / "executions").glob("*/attempt-*.yaml")
            )
            self.assertEqual(1, len(manifests))

    def test_reuse_is_independent_of_wall_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            client = _client(root)
            refs = (ArtifactRef(path="derived/client-profile.yaml", sha256=SHA_A),)
            prior = self._completed_with_inputs(refs)
            write_manifest_create_only(
                manifest_path(client, prior.run_id, prior.attempt), prior
            )
            state = initial_state("acme")

            _, first = start_attempt(
                root,
                client,
                state,
                actor="tester",
                source_commit_sha=COMMIT,
                inputs=refs,
                now=datetime(2026, 9, 17, 0, 0, tzinfo=timezone.utc),
            )
            _, second = start_attempt(
                root,
                client,
                state,
                actor="tester",
                source_commit_sha=COMMIT,
                inputs=refs,
                now=datetime(2030, 1, 1, 0, 0, tzinfo=timezone.utc),
            )
            self.assertEqual(prior, first)
            self.assertEqual(prior, second)
            manifests = sorted(
                (client / "workflow" / "executions").glob("*/attempt-*.yaml")
            )
            self.assertEqual(1, len(manifests))


if __name__ == "__main__":
    unittest.main()
