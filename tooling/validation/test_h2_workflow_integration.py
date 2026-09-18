"""H.2 workflow/runtime integration tests (Milestone H.2, Task 12).

Deterministic and offline. These tests prove the release lifecycle is wired into
the fixed workflow runtime without overloading stage 08:

- the stage-09 ``release`` contract loads and declares the required artifacts,
  validators, and checkpoints, and the Markdown NEXT parity holds;
- the router routes ``productionize`` -> ``release`` and only marks the workflow
  complete after ``release``;
- stage 09 cannot complete with a missing H.2 hardening report or a missing
  exact G authorization (the real evidence validators fail closed);
- stage 08 remains ``production-capable`` (no deployment/authorization) and its
  contract ``next`` is ``[release]``.
"""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import yaml

from tooling.hardening.validate import validate_hardening
from tooling.release.release_record import validate_release_record
from tooling.workflow.contracts import load_stage_contract
from tooling.workflow.router import next_stage
from tooling.workflow.state import initial_state

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
SCHEMA_DIR = ROOT / "client-projects" / "schema"

CLIENT_TREE = (
    "input",
    "derived",
    "directions",
    "resolved-intelligence.yaml",
    "prototype/qa",
    "prototype/prototype-manifest.yaml",
    "production/config",
    "production/evidence",
    "production/release",
    "production/hardening",
    "release/reference-proof",
)

APPROVED_EXPERIENCE = {
    "version": 1,
    "client_id": "reference-commerce",
    "selection": {"mode": "direction", "base_direction": "a"},
}


def _materialize_client(root: Path) -> Path:
    """Copy the committed client artifacts into a temp root (no mutation)."""
    client = root / "client-projects" / "reference-commerce"
    client.mkdir(parents=True)
    for relative in CLIENT_TREE:
        source = CLIENT / relative
        destination = client / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination)
        else:
            shutil.copy2(source, destination)
    shutil.copytree(SCHEMA_DIR, root / "client-projects" / "schema")
    shutil.copytree(ROOT / "supabase", root / "supabase")
    return client


def _write_approved_experience(client: Path) -> None:
    (client / "approved-experience.yaml").write_text(
        yaml.safe_dump(APPROVED_EXPERIENCE, sort_keys=False), encoding="utf-8"
    )


class Stage09ContractTests(unittest.TestCase):
    def test_release_contract_declares_the_required_surface(self):
        contract = load_stage_contract(ROOT, "release")
        self.assertEqual("release", contract.stage)
        self.assertEqual(("productionize",), contract.requires_stages)
        self.assertEqual(
            (
                "production/evidence/h1-foundation-report.json",
                "production/evidence/h2-hardening-report.json",
            ),
            contract.requires_artifacts,
        )
        self.assertEqual(
            ("production/evidence/release-record.json",), contract.produces
        )
        self.assertEqual(
            ("h2-hardening", "production-authorization", "h2-release-record"),
            contract.validators,
        )
        self.assertEqual(
            ("staging-validated", "candidate-authorized", "production-released"),
            contract.checkpoints,
        )
        self.assertEqual((), contract.next_stages)

    def test_release_workflow_markdown_declares_the_required_sections(self):
        text = (ROOT / "workflows" / "09-release.md").read_text(encoding="utf-8")
        for section in ("PURPOSE", "READ", "PROCESS", "WRITE", "VALIDATE", "DO NOT", "NEXT"):
            self.assertIn(f"## {section}", text)


def _schema_validator(schema_name: str):
    try:
        from jsonschema import Draft202012Validator
    except ImportError:  # pragma: no cover - jsonschema is an expected dependency
        raise unittest.SkipTest("jsonschema is not available")
    schema = json.loads((SCHEMA_DIR / schema_name).read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


class StageSchemaCoverageTests(unittest.TestCase):
    """The stage enums must cover every contract and a ``release`` manifest.

    The stage-09 commit added ``release`` to the runtime but not to these two
    schemas; these tests validate the whole contract set and a synthetic
    ``stage: release`` execution manifest so the omission cannot recur.
    """

    def test_every_stage_contract_validates_against_the_schema(self):
        validator = _schema_validator("workflow-stage-contract.schema.json")
        paths = sorted((ROOT / "workflows" / "contracts").glob("*.yaml"))
        self.assertEqual(9, len(paths), [path.name for path in paths])
        for path in paths:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
            errors = [
                f"{error.json_path}: {error.message}"
                for error in validator.iter_errors(data)
            ]
            self.assertEqual([], errors, f"{path.name}: {errors}")
        stages = {
            yaml.safe_load(path.read_text(encoding="utf-8"))["stage"] for path in paths
        }
        self.assertIn("release", stages)

    def test_release_execution_manifest_validates_against_the_schema(self):
        from tooling.workflow.manifests import ExecutionManifest, validate_manifest

        manifest = ExecutionManifest.start(
            run_id="wf-reference-commerce-20260918T000000Z-abcdef12",
            client_id="reference-commerce",
            stage="release",
            attempt=1,
            source_commit_sha="0" * 40,
            started_at="2026-09-18T00:00:00Z",
        )
        self.assertEqual([], validate_manifest(manifest.to_dict()))

    def test_stage_schema_rejects_an_unknown_stage_reference(self):
        validator = _schema_validator("workflow-stage-contract.schema.json")
        data = yaml.safe_load(
            (ROOT / "workflows" / "contracts" / "09-release.yaml").read_text(
                encoding="utf-8"
            )
        )
        data["next"] = ["bogus-stage"]
        self.assertTrue(list(validator.iter_errors(data)))


class Stage09EvidenceGateTests(unittest.TestCase):
    def test_missing_hardening_report_blocks_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = _materialize_client(root)
            (
                client / "production" / "evidence" / "h2-hardening-report.json"
            ).unlink()
            errors = validate_hardening(root, client)
        self.assertTrue(
            any("h2-hardening-report.json" in error for error in errors), errors
        )

    def test_missing_g_authorization_ref_blocks_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = _materialize_client(root)
            (
                client
                / "production"
                / "release"
                / "production-authorization-ref.json"
            ).unlink()
            errors = validate_release_record(root, client)
        self.assertTrue(
            any("authorization" in error for error in errors), errors
        )

    def test_missing_g_authorization_body_blocks_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = _materialize_client(root)
            (
                client
                / "release"
                / "reference-proof"
                / "production-authorization-v0001.json"
            ).unlink()
            errors = validate_release_record(root, client)
        self.assertTrue(
            any("authorization body" in error for error in errors), errors
        )


class RouterReleaseStageTests(unittest.TestCase):
    def _client_state(self):
        state = initial_state("reference-commerce")
        state["completed"] = [
            "client-intake",
            "resolve-intelligence",
            "generate-directions",
            "build-prototype",
            "visual-qa",
            "client-review",
        ]
        state["skipped"] = [
            {"stage": "resource-research", "reason": "curated-reference-set-provided"}
        ]
        return state

    def test_router_routes_productionize_then_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = _materialize_client(root)
            _write_approved_experience(client)
            state = self._client_state()

            routed = next_stage(ROOT, client, state)
            self.assertEqual("productionize", routed["stage"])

            state["completed"].append("productionize")
            routed = next_stage(ROOT, client, state)
            self.assertEqual("release", routed["stage"])
            self.assertEqual("ready", routed["status"])

            state["completed"].append("release")
            routed = next_stage(ROOT, client, state)
            self.assertEqual({"stage": None, "status": "complete"}, routed)


class Stage08BoundaryTests(unittest.TestCase):
    def test_stage08_next_is_release_and_produces_nothing(self):
        contract = load_stage_contract(ROOT, "productionize")
        self.assertEqual(("release",), contract.next_stages)
        self.assertEqual((), contract.produces)
        self.assertEqual(("production-capable",), contract.checkpoints)
        self.assertNotIn("production-authorization", contract.validators)
        self.assertNotIn("h2-release-record", contract.validators)

    def test_stage08_markdown_forbids_deployment_and_authorization(self):
        text = (ROOT / "workflows" / "08-productionize.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("09-release.md", text)
        self.assertIn("not** production-authorized", text)
        self.assertIn("Do not deploy production", text)
        self.assertIn("ProductionAuthorization", text)


if __name__ == "__main__":
    unittest.main()
