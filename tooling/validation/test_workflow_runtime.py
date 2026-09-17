from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import yaml

from tooling.workflow.audit import load_audit_records
from tooling.workflow.client_input import validate_client_input
from tooling.workflow.contracts import load_stage_contract
from tooling.workflow.execution import (
    IllegalStageTransition,
    StageCompletionGateFailed,
    StagePrerequisiteFailed,
    StageValidationFailed,
    complete_attempt,
    fail_attempt,
    record_checkpoint,
    release_after_completion,
    start_attempt,
)
from tooling.workflow.initialize_client import initialize_client
from tooling.workflow.lease import (
    WorkflowLeaseConflict,
    WorkflowLeaseOwnershipError,
    acquire_lease,
    load_lease,
)
from tooling.workflow.manifests import (
    ExecutionManifest,
    ValidatorEvidence,
    artifacts_for_paths,
    load_manifest,
    manifest_path,
)
from tooling.workflow.router import next_stage
from tooling.workflow.state import initial_state, save_state
from tooling.workflow.validate_workflow import validate_client, validate_runtime, validate_workflow_file


ROOT = Path(__file__).resolve().parents[2]

PROFILE = {
    "id": "acme",
    "business_model": "b2b",
    "industry": "electronics-appliances",
    "use_cases": ["rfq"],
    "objectives": ["grow-rfq"],
    "personas": ["trade-buyer"],
    "jobs": ["request-quote"],
    "platforms": ["web"],
}


def _install_input_schemas(root: Path) -> None:
    dst = root / "client-projects" / "schema" / "input"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "client-projects" / "schema" / "input", dst, dirs_exist_ok=True)


def _write_index(client: Path, *, modules: dict | None = None, collections: dict | None = None) -> None:
    (client / "input").mkdir(parents=True, exist_ok=True)
    (client / "input" / "client-input.yaml").write_text(
        yaml.safe_dump(
            {
                "version": 1,
                "client": {"id": "acme", "display_name": "ACME"},
                "source_status": "client_supplied",
                "modules": modules or {},
                "collections": collections or {},
                "unresolved_input": False,
            },
            sort_keys=False,
        ),
        encoding="utf-8",
    )


def write_early_artifacts(client: Path) -> None:
    _install_input_schemas(client.parents[1])
    client.mkdir(parents=True, exist_ok=True)
    (client / "derived").mkdir(parents=True, exist_ok=True)
    _write_index(client)
    (client / "derived" / "client-profile.yaml").write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
    (client / "resolved-intelligence.yaml").write_text("active_presets: []\n", encoding="utf-8")


def write_direction_artifacts(client: Path) -> None:
    directions = client / "directions"
    directions.mkdir(parents=True, exist_ok=True)
    for name in ("direction-a.yaml", "direction-b.yaml", "direction-c.yaml", "comparison.yaml"):
        (directions / name).write_text("id: sample\n", encoding="utf-8")


MODULE_DOMAINS = {
    "business-rules.yaml": "rules",
    "user-groups.yaml": "groups",
    "journey-priorities.yaml": "journeys",
    "feature-requirements.yaml": "features",
    "platform-requirements.yaml": "requirements",
    "integration-requirements.yaml": "integrations",
    "content-requirements.yaml": "requirements",
    "data-context.yaml": "entities",
    "constraints.yaml": "constraints",
    "open-questions.yaml": "questions",
}

COLLECTION_DOMAINS = {
    "brand": ("brand-input.yaml", "facts"),
    "references": ("references.yaml", "references"),
    "assets": ("asset-manifest.yaml", "assets"),
    "source-documents": ("source-documents.yaml", "documents"),
}


class WorkflowRuntimeTests(unittest.TestCase):
    def test_initializer_creates_exact_standard_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            client_dir = initialize_client(root, "acme", "Acme Furniture")
            for rel in (
                "input",
                "input/brand/brand-assets",
                "input/references/current-app",
                "input/references/competitor",
                "input/references/inspiration",
                "input/assets/products",
                "input/assets/categories",
                "input/assets/banners",
                "input/assets/sellers",
                "input/assets/videos",
                "input/source-documents",
                "derived",
                "resources",
                "directions",
                "prototype",
            ):
                self.assertTrue((client_dir / rel).is_dir(), rel)
            self.assertTrue((client_dir / "workflow-state.yaml").exists())
            self.assertTrue((client_dir / "input" / "client-input.yaml").exists())
            self.assertTrue((client_dir / "derived" / "client-profile.yaml").exists())
            self.assertFalse((client_dir / "client-profile.yaml").exists())
            self.assertFalse((client_dir / "references").exists())
            self.assertFalse((client_dir / "fixtures").exists())
            self.assertEqual([], validate_client_input(ROOT, client_dir))

            index = yaml.safe_load((client_dir / "input" / "client-input.yaml").read_text(encoding="utf-8"))
            self.assertEqual("acme", index["client"]["id"])
            self.assertEqual("Acme Furniture", index["client"]["display_name"])
            self.assertEqual("client_supplied", index["source_status"])
            self.assertEqual({}, index["modules"])
            self.assertEqual({}, index["collections"])
            self.assertTrue(index["unresolved_input"])

            profile = yaml.safe_load((client_dir / "derived" / "client-profile.yaml").read_text(encoding="utf-8"))
            self.assertEqual("acme", profile["id"])
            self.assertEqual("Acme Furniture", profile["display_name"])
            self.assertEqual("", profile["business_model"])
            self.assertEqual("", profile["industry"])
            self.assertEqual([], profile["personas"])
            self.assertEqual([], profile["platforms"])

    def test_initializer_optional_templates_are_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            client_dir = initialize_client(root, "acme")
            input_dir = client_dir / "input"
            for filename, domain in MODULE_DOMAINS.items():
                data = yaml.safe_load((input_dir / filename).read_text(encoding="utf-8"))
                self.assertEqual(1, data["version"], filename)
                self.assertFalse(data["provided"], filename)
                self.assertEqual([], data[domain], filename)
            for subdir, (filename, domain) in COLLECTION_DOMAINS.items():
                data = yaml.safe_load((input_dir / subdir / filename).read_text(encoding="utf-8"))
                self.assertEqual(1, data["version"], filename)
                self.assertFalse(data["provided"], filename)
                self.assertEqual([], data[domain], filename)

    def test_initializer_refuses_existing_client(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects" / "acme").mkdir(parents=True)
            with self.assertRaises(FileExistsError):
                initialize_client(root, "acme")

    def test_initial_next_stage_is_client_intake(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            client.mkdir(parents=True)
            state = initial_state("acme")
            self.assertEqual("client-intake", next_stage(root, client, state)["stage"])

    def test_valid_profile_advances_to_resolve_intelligence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            state["current_stage"] = "resolve-intelligence"
            self.assertEqual("resolve-intelligence", next_stage(root, client, state)["stage"])

    def test_resource_research_can_be_skipped_with_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence"]
            state["skipped"] = [{"stage": "resource-research", "reason": "no-external-resources-required"}]
            result = next_stage(root, client, state)
            self.assertEqual("generate-directions", result["stage"])

    def test_build_prototype_blocks_when_platform_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertEqual("build-prototype", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("prototype-platform-not-installed", result["reason"])

    def test_productionize_is_not_selected_without_approved_experience(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            write_direction_artifacts(client)
            state = initial_state("acme")
            state["completed"] = [
                "client-intake", "resolve-intelligence", "generate-directions",
                "build-prototype", "visual-qa", "client-review",
            ]
            state["skipped"] = [{"stage": "resource-research", "reason": "none-needed"}]
            result = next_stage(root, client, state)
            self.assertNotEqual("productionize", result.get("stage"))

    def test_workflow_file_missing_required_section_fails_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.md"
            path.write_text("## PURPOSE\nDo a thing\n## READ\ninputs\n", encoding="utf-8")
            errors = validate_workflow_file(path)
            self.assertTrue(errors)
            self.assertTrue(any("PROCESS" in error for error in errors))

    def test_two_direction_client_passes_workflow_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            directions = client / "directions"
            directions.mkdir(parents=True, exist_ok=True)
            for name in ("direction-a.yaml", "direction-b.yaml", "comparison.yaml"):
                (directions / name).write_text("id: sample\n", encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake", "resolve-intelligence", "generate-directions"]
            save_state(client / "workflow-state.yaml", state)
            errors = validate_client(root, client)
            self.assertEqual([], errors)

    def test_router_blocks_intake_when_client_input_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            (client / "input").mkdir(parents=True)
            (client / "input" / "client-input.yaml").write_text("foo: [1, 2", encoding="utf-8")
            state = initial_state("acme")
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("client-input-invalid", result["reason"])

    def test_router_blocks_intake_when_blocking_question_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            (client / "input").mkdir(parents=True)
            (client / "input" / "open-questions.yaml").write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "questions": [
                            {"id": "q1", "question": "Who approves?", "status": "open", "blocking": True}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            _write_index(client, modules={"open_questions": "open-questions.yaml"})
            state = initial_state("acme")
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("blocking-open-questions", result["reason"])

    def test_router_requires_derived_client_profile_after_intake(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            _write_index(client)
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("blocked", result["status"])
            self.assertEqual("derived-client-profile-missing", result["reason"])

    def test_router_allows_intake_progress_with_valid_nonblocking_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            (client / "input").mkdir(parents=True)
            (client / "input" / "open-questions.yaml").write_text(
                yaml.safe_dump(
                    {
                        "version": 1,
                        "provided": True,
                        "questions": [
                            {"id": "q1", "question": "Tone?", "status": "resolved", "blocking": True}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            _write_index(client, modules={"open_questions": "open-questions.yaml"})
            state = initial_state("acme")
            result = next_stage(root, client, state)
            self.assertEqual("client-intake", result["stage"])
            self.assertEqual("ready", result["status"])

    def test_validate_client_rejects_root_only_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "client-projects").mkdir()
            _install_input_schemas(root)
            client = root / "client-projects" / "acme"
            write_early_artifacts(client)
            (client / "derived" / "client-profile.yaml").unlink()
            (client / "client-profile.yaml").write_text(yaml.safe_dump(PROFILE), encoding="utf-8")
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            save_state(client / "workflow-state.yaml", state)
            errors = validate_client(root, client)
            self.assertTrue(any("derived" in e and "client-profile.yaml" in e for e in errors))

    def test_repository_runtime_contract_validates(self):
        root = Path(__file__).resolve().parents[2]
        errors = validate_runtime(root)
        self.assertEqual([], errors)


class WorkflowExecutionTests(unittest.TestCase):
    COMMIT = "0" * 40
    AT = "2026-09-17T00:00:00Z"

    def _root(self, tmp: str) -> Path:
        root = Path(tmp)
        (root / "client-projects").mkdir(parents=True, exist_ok=True)
        shutil.copytree(ROOT / "workflows" / "contracts", root / "workflows" / "contracts")
        return root

    def _client(self, root: Path) -> Path:
        client = root / "client-projects" / "acme"
        client.mkdir(parents=True, exist_ok=True)
        return client

    def _passed(self, name: str) -> ValidatorEvidence:
        return ValidatorEvidence(name=name, status="passed", at=self.AT)

    def test_start_attempt_refuses_when_prerequisites_unmet(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            with self.assertRaises(StagePrerequisiteFailed):
                start_attempt(
                    root,
                    client,
                    state,
                    actor="tester",
                    source_commit_sha=self.COMMIT,
                    stage="resolve-intelligence",
                )

    def test_start_attempt_refuses_when_prerequisite_artifact_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            with self.assertRaises(StagePrerequisiteFailed):
                start_attempt(
                    root,
                    client,
                    state,
                    actor="tester",
                    source_commit_sha=self.COMMIT,
                    stage="resolve-intelligence",
                )

    def test_start_attempt_writes_manifest_and_advances_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            self.assertEqual("client-intake", manifest.stage)
            self.assertEqual("in_progress", manifest.status)
            self.assertTrue(manifest_path(client, manifest.run_id, manifest.attempt).exists())
            self.assertEqual(manifest.run_id, new_state["run_id"])
            self.assertEqual("in_progress", new_state["status"])
            self.assertEqual(1, new_state["stage_state"]["client-intake"]["attempt"])
            self.assertIsNone(state["run_id"])
            self.assertEqual({}, state["stage_state"])

    def test_failed_attempt_leaves_pointer_collections_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            failed_state, failed_manifest = fail_attempt(
                client, new_state, manifest, reason="boom", at=self.AT, actor="tester"
            )
            self.assertEqual(state["current_stage"], failed_state["current_stage"])
            self.assertEqual(state["completed"], failed_state["completed"])
            self.assertEqual(state["pending"], failed_state["pending"])
            self.assertEqual("failed", failed_manifest.status)
            self.assertEqual("failed", failed_state["stage_state"]["client-intake"]["status"])
            self.assertEqual(self.AT, failed_state["stage_state"]["client-intake"]["failed_at"])

    def test_complete_attempt_missing_produced_artifact_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            with self.assertRaises(StageValidationFailed):
                complete_attempt(
                    root,
                    client,
                    new_state,
                    manifest,
                    validator_results=[self._passed("client-input-contract")],
                    at=self.AT,
                    actor="tester",
                )

    def test_complete_attempt_failed_validator_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text("id: acme\n", encoding="utf-8")
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            with self.assertRaises(StageCompletionGateFailed):
                complete_attempt(
                    root,
                    client,
                    new_state,
                    manifest,
                    validator_results=[
                        ValidatorEvidence(name="client-input-contract", status="failed", at=self.AT)
                    ],
                    at=self.AT,
                    actor="tester",
                )

    def test_successful_complete_attempt_writes_manifest_before_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text("id: acme\n", encoding="utf-8")
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            final_state, frozen = complete_attempt(
                root,
                client,
                new_state,
                manifest,
                validator_results=[self._passed("client-input-contract")],
                at=self.AT,
                actor="tester",
            )

            path = manifest_path(client, frozen.run_id, frozen.attempt)
            self.assertTrue(path.exists())
            self.assertEqual("completed", load_manifest(path).status)
            self.assertEqual("resolve-intelligence", final_state["current_stage"])
            self.assertIn("client-intake", final_state["completed"])
            self.assertNotIn("client-intake", final_state["pending"])
            self.assertEqual(
                {"from": "client-intake", "to": "resolve-intelligence", "at": self.AT, "actor": "tester"},
                final_state["last_transition"],
            )
            self.assertEqual(
                "complete", final_state["stage_state"]["client-intake"]["status"]
            )

    def test_record_checkpoint_rejects_undeclared_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            contract = load_stage_contract(root, "client-intake")
            state = initial_state("acme")
            _, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            with self.assertRaises(IllegalStageTransition):
                record_checkpoint(manifest, "bogus-checkpoint", at=self.AT, contract=contract)
            updated = record_checkpoint(
                manifest, "intake-complete", at=self.AT, contract=contract
            )
            self.assertEqual("intake-complete", updated.checkpoints[-1].name)

    def test_complete_attempt_rejects_a_non_current_stage_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            foreign = ExecutionManifest(
                run_id=manifest.run_id,
                client_id=manifest.client_id,
                stage="generate-directions",
                attempt=1,
                source_commit_sha=self.COMMIT,
                started_at=self.AT,
            )
            with self.assertRaises(IllegalStageTransition):
                complete_attempt(
                    root,
                    client,
                    new_state,
                    foreign,
                    validator_results=[self._passed("direction-contract")],
                    at=self.AT,
                    actor="tester",
                )
            self.assertEqual("client-intake", new_state["current_stage"])

    def test_complete_attempt_rejects_a_stale_run_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            stale = ExecutionManifest(
                run_id="wf-acme-other",
                client_id=manifest.client_id,
                stage=manifest.stage,
                attempt=1,
                source_commit_sha=self.COMMIT,
                started_at=self.AT,
            )
            with self.assertRaises(IllegalStageTransition):
                complete_attempt(
                    root,
                    client,
                    new_state,
                    stale,
                    validator_results=[self._passed("client-input-contract")],
                    at=self.AT,
                    actor="tester",
                )

    def test_complete_attempt_rejects_a_cross_client_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            foreign = ExecutionManifest(
                run_id=manifest.run_id,
                client_id="other-client",
                stage=manifest.stage,
                attempt=1,
                source_commit_sha=self.COMMIT,
                started_at=self.AT,
            )
            with self.assertRaises(IllegalStageTransition):
                complete_attempt(
                    root,
                    client,
                    new_state,
                    foreign,
                    validator_results=[self._passed("client-input-contract")],
                    at=self.AT,
                    actor="tester",
                )

    def test_fail_attempt_rejects_a_non_current_stage_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            foreign = ExecutionManifest(
                run_id=manifest.run_id,
                client_id=manifest.client_id,
                stage="generate-directions",
                attempt=1,
                source_commit_sha=self.COMMIT,
                started_at=self.AT,
            )
            with self.assertRaises(IllegalStageTransition):
                fail_attempt(client, new_state, foreign, reason="boom", at=self.AT, actor="tester")

    def test_fail_attempt_rejects_a_stale_run_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            stale = ExecutionManifest(
                run_id="wf-acme-other",
                client_id=manifest.client_id,
                stage=manifest.stage,
                attempt=1,
                source_commit_sha=self.COMMIT,
                started_at=self.AT,
            )
            with self.assertRaises(IllegalStageTransition):
                fail_attempt(client, new_state, stale, reason="boom", at=self.AT, actor="tester")

    def test_complete_attempt_rejects_a_manifest_when_no_run_is_active(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            unlinked = ExecutionManifest(
                run_id="wf-acme-unlinked",
                client_id="acme",
                stage="client-intake",
                attempt=1,
                source_commit_sha=self.COMMIT,
                started_at=self.AT,
            )
            with self.assertRaises(IllegalStageTransition):
                complete_attempt(
                    root,
                    client,
                    state,
                    unlinked,
                    validator_results=[self._passed("client-input-contract")],
                    at=self.AT,
                    actor="tester",
                )

    def test_fail_attempt_requires_the_owning_lease(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            started_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            with self.assertRaises(WorkflowLeaseOwnershipError):
                fail_attempt(
                    client,
                    started_state,
                    manifest,
                    reason="boom",
                    at=self.AT,
                    actor="someone-else",
                )
            self.assertEqual("in_progress", started_state["stage_state"]["client-intake"]["status"])

    def test_start_attempt_acquires_the_lease_and_releases_on_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            started_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            self.assertIsNotNone(started_state["active_lease"])
            self.assertEqual("tester", started_state["active_lease"]["owner"])

            final_state, _ = complete_attempt(
                root,
                client,
                started_state,
                manifest,
                validator_results=[self._passed("client-input-contract")],
                at=self.AT,
                actor="tester",
            )
            self.assertIsNone(final_state["active_lease"])

    def test_second_owner_cannot_start_while_a_live_lease_is_held(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            leased_state, _ = start_attempt(
                root, client, state, actor="opencode:session-a", source_commit_sha=self.COMMIT
            )
            before = json.dumps(leased_state, sort_keys=True)
            manifests_before = sorted(
                path.name
                for path in (client / "workflow" / "executions").rglob("attempt-*.yaml")
            )
            with self.assertRaises(WorkflowLeaseConflict):
                start_attempt(
                    root,
                    client,
                    leased_state,
                    actor="opencode:session-b",
                    source_commit_sha=self.COMMIT,
                )
            self.assertEqual(before, json.dumps(leased_state, sort_keys=True))
            self.assertEqual(
                manifests_before,
                sorted(
                    path.name
                    for path in (client / "workflow" / "executions").rglob("attempt-*.yaml")
                ),
            )

    def test_complete_attempt_requires_the_owning_lease(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            started_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            with self.assertRaises(WorkflowLeaseOwnershipError):
                complete_attempt(
                    root,
                    client,
                    started_state,
                    manifest,
                    validator_results=[self._passed("client-input-contract")],
                    at=self.AT,
                    actor="someone-else",
                )
            released = dict(started_state)
            released["active_lease"] = None
            with self.assertRaises(WorkflowLeaseOwnershipError):
                complete_attempt(
                    root,
                    client,
                    released,
                    manifest,
                    validator_results=[self._passed("client-input-contract")],
                    at=self.AT,
                    actor="tester",
                )

    def test_expired_lease_is_reclaimed_with_an_audit_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            leased_state, _ = start_attempt(
                root,
                client,
                state,
                actor="opencode:session-a",
                source_commit_sha=self.COMMIT,
                now=datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc),
                lease_ttl_seconds=60,
            )
            expired_lease_id = leased_state["active_lease"]["lease_id"]
            reclaimed_state, _ = start_attempt(
                root,
                client,
                leased_state,
                actor="opencode:session-b",
                source_commit_sha=self.COMMIT,
                now=datetime(2026, 9, 17, 12, 5, tzinfo=timezone.utc),
            )
            self.assertEqual(
                "opencode:session-b", reclaimed_state["active_lease"]["owner"]
            )
            records = load_audit_records(client / "workflow" / "audit.jsonl")
            self.assertEqual(1, len(records))
            self.assertEqual("recovery", records[0].kind)
            self.assertEqual(
                expired_lease_id, records[0].details["previous_state"]["lease_id"]
            )

    def test_validate_client_rejects_a_broken_manifest_reference(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            final_state, frozen = complete_attempt(
                root,
                client,
                new_state,
                manifest,
                validator_results=[self._passed("client-input-contract")],
                at=self.AT,
                actor="tester",
            )
            final_state["stage_state"]["client-intake"]["artifact_manifest_ref"] = (
                "workflow/executions/missing/attempt-1.yaml"
            )
            save_state(client / "workflow-state.yaml", final_state)
            errors = validate_client(root, client)
            self.assertTrue(
                any("references missing execution manifest" in error for error in errors),
                errors,
            )
            self.assertTrue(frozen.status == "completed")

    def test_validate_client_rejects_a_corrupted_frozen_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            final_state, frozen = complete_attempt(
                root,
                client,
                new_state,
                manifest,
                validator_results=[self._passed("client-input-contract")],
                at=self.AT,
                actor="tester",
            )
            save_state(client / "workflow-state.yaml", final_state)
            path = manifest_path(client, frozen.run_id, frozen.attempt)
            path.write_text("{ not: valid: yaml", encoding="utf-8")
            errors = validate_client(root, client)
            self.assertTrue(any("manifest" in error for error in errors), errors)

    def test_validate_client_rejects_stage_state_complete_without_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            state = initial_state("acme")
            state["completed"] = ["client-intake"]
            state["stage_state"] = {"client-intake": {"status": "complete"}}
            save_state(client / "workflow-state.yaml", state)
            errors = validate_client(root, client)
            self.assertTrue(
                any("no completed execution manifest" in error for error in errors), errors
            )


class WorkflowIdempotencyRuntimeTests(unittest.TestCase):
    """Cycle 2: failure evidence, idempotent reruns, and lease ownership."""

    COMMIT = "0" * 40
    AT = "2026-09-17T00:00:00Z"
    NOW = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)

    def _root(self, tmp: str) -> Path:
        root = Path(tmp)
        (root / "client-projects").mkdir(parents=True, exist_ok=True)
        shutil.copytree(ROOT / "workflows" / "contracts", root / "workflows" / "contracts")
        return root

    def _client(self, root: Path) -> Path:
        client = root / "client-projects" / "acme"
        client.mkdir(parents=True, exist_ok=True)
        return client

    def _passed(self, name: str) -> ValidatorEvidence:
        return ValidatorEvidence(name=name, status="passed", at=self.AT)

    def test_fail_attempt_persists_failed_manifest_on_disk(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root, client, state, actor="tester", source_commit_sha=self.COMMIT
            )
            _, failed = fail_attempt(
                client, new_state, manifest, reason="boom", at=self.AT, actor="tester"
            )
            on_disk = load_manifest(manifest_path(client, failed.run_id, failed.attempt))
            self.assertEqual("failed", on_disk.status)
            self.assertEqual("boom", on_disk.failure_reason)
            self.assertEqual(self.AT, on_disk.completed_at)

    def test_reuse_rerun_does_not_duplicate_completed_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            (client / "derived").mkdir(parents=True, exist_ok=True)
            (client / "derived" / "client-profile.yaml").write_text(
                "id: acme\n", encoding="utf-8"
            )
            refs = artifacts_for_paths(client, ["derived/client-profile.yaml"])
            state = initial_state("acme")
            new_state, manifest = start_attempt(
                root,
                client,
                state,
                actor="tester",
                source_commit_sha=self.COMMIT,
                inputs=refs,
            )
            final_state, frozen = complete_attempt(
                root,
                client,
                new_state,
                manifest,
                validator_results=[self._passed("client-input-contract")],
                at=self.AT,
                actor="tester",
            )

            reused_state, reused = start_attempt(
                root,
                client,
                final_state,
                actor="tester",
                source_commit_sha=self.COMMIT,
                stage="client-intake",
                inputs=refs,
            )

            self.assertEqual(frozen.run_id, reused.run_id)
            self.assertEqual(frozen.attempt, reused.attempt)
            self.assertEqual("completed", reused.status)
            self.assertEqual(final_state, reused_state)
            manifests = sorted(
                (client / "workflow" / "executions").glob("*/attempt-*.yaml")
            )
            self.assertEqual(1, len(manifests))

    def test_lease_blocks_second_owner_and_state_is_not_mutated(self):
        state = initial_state("acme")
        leased_state, lease = acquire_lease(
            state, owner="opencode:session-a", run_id=None, now=self.NOW
        )
        before = copy.deepcopy(leased_state)
        with self.assertRaises(WorkflowLeaseConflict):
            acquire_lease(
                leased_state, owner="opencode:session-b", run_id=None, now=self.NOW
            )
        self.assertEqual(before, leased_state)
        self.assertEqual(lease, load_lease(leased_state))
        self.assertIsNone(state["active_lease"])

    def test_release_after_completion_clears_the_lease(self):
        state = initial_state("acme")
        leased_state, lease = acquire_lease(
            state, owner="opencode:session-a", run_id=None, now=self.NOW
        )
        released = release_after_completion(leased_state, lease)
        self.assertIsNone(released["active_lease"])
        self.assertEqual(lease.to_dict(), leased_state["active_lease"])


class WorkflowValidatorHardeningTests(unittest.TestCase):
    """Cycle 3 slice 3b: hardened, strictly read-only repository validation."""

    COMMIT = "0" * 40
    AT = "2026-09-17T00:00:00Z"

    def _root(self, tmp: str) -> Path:
        root = Path(tmp)
        (root / "client-projects").mkdir(parents=True, exist_ok=True)
        shutil.copytree(ROOT / "workflows" / "contracts", root / "workflows" / "contracts")
        return root

    def _client(self, root: Path) -> Path:
        client = root / "client-projects" / "acme"
        client.mkdir(parents=True, exist_ok=True)
        return client

    def _write_raw_state(self, client: Path, state: dict) -> None:
        (client / "workflow-state.yaml").write_text(
            yaml.safe_dump(state, sort_keys=False), encoding="utf-8"
        )

    def test_validate_client_reports_unknown_top_level_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            state["unexpected_key"] = True
            self._write_raw_state(client, state)

            errors = validate_client(root, client)

        self.assertTrue(any("unexpected_key" in error for error in errors), errors)

    def test_validate_client_reports_lease_expiring_before_acquisition(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            state["status"] = "in_progress"
            state["active_lease"] = {
                "lease_id": "lease-abc",
                "owner": "opencode:test",
                "run_id": "wf-acme-1",
                "acquired_at": "2026-09-17T12:00:00Z",
                "expires_at": "2026-09-17T11:00:00Z",
            }
            self._write_raw_state(client, state)

            errors = validate_client(root, client)

        self.assertTrue(
            any("expires_at" in error and "acquired_at" in error for error in errors),
            errors,
        )

    def test_validate_client_reports_manifest_ref_with_wrong_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            manifest = (
                ExecutionManifest.start(
                    run_id="wf-acme-1",
                    client_id="acme",
                    stage="resolve-intelligence",
                    attempt=1,
                    source_commit_sha=self.COMMIT,
                    started_at=self.AT,
                )
                .with_validators(
                    [ValidatorEvidence(name="resolved-intelligence-contract", status="passed", at=self.AT)]
                )
                .complete(at=self.AT, required_validators=["resolved-intelligence-contract"])
            )
            path = manifest_path(client, "wf-acme-1", 1)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(manifest.to_dict(), sort_keys=False), encoding="utf-8")

            state = initial_state("acme")
            state["current_stage"] = "resolve-intelligence"
            state["status"] = "in_progress"
            state["completed"] = ["client-intake"]
            state["stage_state"] = {
                "client-intake": {
                    "attempt": 1,
                    "status": "complete",
                    "artifact_manifest_ref": "workflow/executions/wf-acme-1/attempt-1.yaml",
                }
            }
            save_state(client / "workflow-state.yaml", state)

            errors = validate_client(root, client)

        self.assertTrue(any("references manifest of stage" in error for error in errors), errors)

    def test_validate_client_reports_malformed_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            path = client / "workflow" / "executions" / "wf-acme-1" / "attempt-1.yaml"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("run_id: wf-acme-1\nstage: client-intake\n", encoding="utf-8")
            self._write_raw_state(client, initial_state("acme"))

            errors = validate_client(root, client)

        self.assertTrue(any("manifest" in error for error in errors), errors)

    def test_validate_client_reports_malformed_audit_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            audit = client / "workflow" / "audit.jsonl"
            audit.parent.mkdir(parents=True, exist_ok=True)
            audit.write_text("{ not valid json\n", encoding="utf-8")
            self._write_raw_state(client, initial_state("acme"))

            errors = validate_client(root, client)

        self.assertTrue(any("audit.jsonl" in error for error in errors), errors)

    def test_validate_client_reports_pointer_ahead_of_prerequisites(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._root(tmp)
            client = self._client(root)
            state = initial_state("acme")
            state["current_stage"] = "build-prototype"
            state["status"] = "in_progress"
            state["completed"] = ["client-intake"]
            save_state(client / "workflow-state.yaml", state)

            errors = validate_client(root, client)

        self.assertTrue(any("prerequisites not completed" in error for error in errors), errors)

    def test_real_repository_workflow_validation_is_clean(self):
        self.assertEqual([], validate_runtime(ROOT))


if __name__ == "__main__":
    unittest.main()
