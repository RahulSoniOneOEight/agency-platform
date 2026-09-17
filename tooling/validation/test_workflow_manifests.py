from __future__ import annotations

import hashlib
import json
import tempfile
import unittest

import yaml
from pathlib import Path

from tooling.workflow.manifests import (
    ArtifactManifestMismatch,
    ArtifactRef,
    CheckpointRecord,
    ExecutionManifest,
    ManifestError,
    ManifestImmutable,
    StageCompletionGateFailed,
    ValidatorEvidence,
    load_manifest,
    manifest_path,
    manifest_relpath,
    sha256_file,
    validate_manifest,
    write_manifest_create_only,
)


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "workflow-execution-manifest.schema.json"

RUN_ID = "wf-acme-20260917T000000Z-abcdef12"
AT = "2026-09-17T00:00:00Z"
SHA = "a" * 64


def _manifest(**overrides: object) -> ExecutionManifest:
    kwargs: dict[str, object] = {
        "run_id": RUN_ID,
        "client_id": "acme",
        "stage": "client-intake",
        "attempt": 1,
        "source_commit_sha": "0" * 40,
        "started_at": AT,
    }
    kwargs.update(overrides)
    return ExecutionManifest.start(**kwargs)  # type: ignore[arg-type]


def _schema_validator() -> object:
    try:
        from jsonschema import Draft202012Validator
    except ImportError:  # pragma: no cover - jsonschema is an expected dependency
        raise unittest.SkipTest("jsonschema is not available")
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


class StartTests(unittest.TestCase):
    def test_start_sets_in_progress_and_empty_collections(self):
        manifest = _manifest()
        self.assertEqual("in_progress", manifest.status)
        self.assertEqual("acme", manifest.client_id)
        self.assertEqual("client-intake", manifest.stage)
        self.assertEqual(1, manifest.attempt)
        self.assertEqual((), manifest.inputs)
        self.assertEqual((), manifest.outputs)
        self.assertEqual((), manifest.checkpoints)
        self.assertEqual((), manifest.validators)
        self.assertEqual((), manifest.rulings)
        self.assertEqual((), manifest.deviations)
        self.assertIsNone(manifest.completed_at)
        self.assertIsNone(manifest.failure_reason)

    def test_start_carries_inputs(self):
        ref = ArtifactRef(path="derived/client-profile.yaml", sha256=SHA)
        manifest = _manifest(inputs=(ref,))
        self.assertEqual((ref,), manifest.inputs)


class CheckpointTests(unittest.TestCase):
    def test_with_checkpoint_appends_and_preserves_order(self):
        manifest = (
            _manifest()
            .with_checkpoint("first", at=AT)
            .with_checkpoint("second", at="2026-09-17T00:01:00Z")
        )
        self.assertEqual(
            (CheckpointRecord(name="first", at=AT), CheckpointRecord(name="second", at="2026-09-17T00:01:00Z")),
            manifest.checkpoints,
        )

    def test_original_manifest_is_not_mutated(self):
        manifest = _manifest()
        manifest.with_checkpoint("first", at=AT)
        self.assertEqual((), manifest.checkpoints)


class OutputTests(unittest.TestCase):
    def test_identical_duplicate_output_is_a_no_op(self):
        ref = ArtifactRef(path="derived/client-profile.yaml", sha256=SHA)
        manifest = _manifest().with_output(ref).with_output(ref)
        self.assertEqual((ref,), manifest.outputs)

    def test_conflicting_output_hash_raises(self):
        first = ArtifactRef(path="derived/client-profile.yaml", sha256=SHA)
        second = ArtifactRef(path="derived/client-profile.yaml", sha256="b" * 64)
        with self.assertRaises(ArtifactManifestMismatch):
            _manifest().with_output(first).with_output(second)

    def test_distinct_paths_accumulate(self):
        first = ArtifactRef(path="a.yaml", sha256=SHA)
        second = ArtifactRef(path="b.yaml", sha256="b" * 64)
        manifest = _manifest().with_output(first).with_output(second)
        self.assertEqual((first, second), manifest.outputs)


class CompletionTests(unittest.TestCase):
    def test_complete_without_passing_required_validator_raises(self):
        with self.assertRaises(StageCompletionGateFailed):
            _manifest().complete(at=AT, required_validators=["client-input-contract"])

    def test_complete_with_failed_required_validator_raises(self):
        manifest = _manifest().with_validators(
            [ValidatorEvidence(name="client-input-contract", status="failed", at=AT)]
        )
        with self.assertRaises(StageCompletionGateFailed):
            manifest.complete(at=AT, required_validators=["client-input-contract"])

    def test_complete_with_passing_required_validator_freezes(self):
        manifest = _manifest().with_validators(
            [ValidatorEvidence(name="client-input-contract", status="passed", at=AT)]
        )
        completed = manifest.complete(at=AT, required_validators=["client-input-contract"])
        self.assertEqual("completed", completed.status)
        self.assertEqual(AT, completed.completed_at)
        self.assertIsNone(completed.failure_reason)
        with self.assertRaises(ManifestImmutable):
            completed.with_checkpoint("later", at=AT)

    def test_fail_freezes(self):
        failed = _manifest().fail(reason="boom", at=AT)
        self.assertEqual("failed", failed.status)
        self.assertEqual("boom", failed.failure_reason)
        self.assertEqual(AT, failed.completed_at)
        with self.assertRaises(ManifestImmutable):
            failed.with_output(ArtifactRef(path="a.yaml", sha256=SHA))

    def test_from_dict_rejects_an_unknown_status(self):
        data = _manifest().to_dict()
        data["status"] = "archived"
        with self.assertRaises(ManifestError):
            ExecutionManifest.from_dict(data)

    def test_write_manifest_refuses_any_non_in_progress_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "attempt-1.yaml"
            write_manifest_create_only(path, _manifest())
            data = load_manifest(path).to_dict()
            data["status"] = "failed"
            path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")
            with self.assertRaises(ManifestImmutable):
                write_manifest_create_only(path, _manifest())


class PersistenceTests(unittest.TestCase):
    def test_write_manifest_create_only_refuses_completed_and_allows_in_progress(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "executions" / RUN_ID / "attempt-1.yaml"
            started = _manifest()
            write_manifest_create_only(path, started)

            updated = started.with_checkpoint("first", at=AT)
            write_manifest_create_only(path, updated)
            self.assertEqual(("first",), tuple(c.name for c in load_manifest(path).checkpoints))

            completed = updated.with_validators(
                [ValidatorEvidence(name="client-input-contract", status="passed", at=AT)]
            ).complete(at=AT, required_validators=["client-input-contract"])
            write_manifest_create_only(path, completed)
            self.assertEqual("completed", load_manifest(path).status)

            with self.assertRaises(ManifestImmutable):
                write_manifest_create_only(path, updated)

    def test_write_manifest_leaves_no_temp_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "attempt-1.yaml"
            write_manifest_create_only(path, _manifest())
            self.assertEqual([], list(path.parent.glob("*.tmp")))

    def test_manifest_path_and_relpath_agree(self):
        with tempfile.TemporaryDirectory() as tmp:
            client_dir = Path(tmp) / "client-projects" / "acme"
            self.assertEqual(
                "workflow/executions/%s/attempt-2.yaml" % RUN_ID,
                manifest_relpath(RUN_ID, 2),
            )
            self.assertEqual(
                client_dir / "workflow" / "executions" / RUN_ID / "attempt-2.yaml",
                manifest_path(client_dir, RUN_ID, 2),
            )


class HashTests(unittest.TestCase):
    def test_sha256_file_is_deterministic_bare_hex(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "artifact.yaml"
            path.write_bytes(b"hello manifest\n")
            digest = sha256_file(path)
            self.assertEqual(hashlib.sha256(b"hello manifest\n").hexdigest(), digest)
            self.assertEqual(digest, sha256_file(path))
            self.assertEqual(64, len(digest))
            self.assertTrue(all(character in "0123456789abcdef" for character in digest))


class RoundTripTests(unittest.TestCase):
    def _rich_manifest(self) -> ExecutionManifest:
        return (
            _manifest()
            .with_checkpoint("first", at=AT)
            .with_output(ArtifactRef(path="derived/client-profile.yaml", sha256=SHA, authority="tooling"))
            .with_validators([ValidatorEvidence(name="client-input-contract", status="passed", at=AT)])
            .with_ruling({"id": "r1", "decision": "accept"})
            .with_deviation({"id": "d1", "reason": "legacy"})
        )

    def test_to_dict_from_dict_round_trips_exactly(self):
        manifest = self._rich_manifest()
        self.assertEqual(manifest, ExecutionManifest.from_dict(manifest.to_dict()))

    def test_to_dict_is_deterministic_key_order(self):
        manifest = self._rich_manifest()
        self.assertEqual(list(manifest.to_dict()), list(manifest.to_dict()))
        self.assertEqual(
            [
                "run_id",
                "client_id",
                "stage",
                "attempt",
                "source_commit_sha",
                "started_at",
                "status",
                "inputs",
                "outputs",
                "checkpoints",
                "validators",
                "rulings",
                "deviations",
                "completed_at",
                "failure_reason",
            ],
            list(manifest.to_dict()),
        )


class SchemaTests(unittest.TestCase):
    def test_schema_accepts_a_valid_manifest(self):
        validator = _schema_validator()
        manifest = (
            _manifest()
            .with_checkpoint("first", at=AT)
            .with_output(ArtifactRef(path="derived/client-profile.yaml", sha256=SHA))
            .with_validators([ValidatorEvidence(name="client-input-contract", status="passed", at=AT)])
        )
        self.assertEqual([], list(validator.iter_errors(manifest.to_dict())))
        self.assertEqual([], validate_manifest(manifest.to_dict()))

    def test_schema_rejects_unknown_key(self):
        validator = _schema_validator()
        data = _manifest().to_dict()
        data["unexpected"] = True
        self.assertTrue(list(validator.iter_errors(data)))
        self.assertTrue(validate_manifest(data))

    def test_schema_rejects_bad_status(self):
        validator = _schema_validator()
        data = _manifest().to_dict()
        data["status"] = "bogus"
        self.assertTrue(list(validator.iter_errors(data)))
        self.assertTrue(validate_manifest(data))

    def test_schema_rejects_bad_sha256(self):
        data = _manifest().with_output(ArtifactRef(path="a.yaml", sha256=SHA)).to_dict()
        data["outputs"][0]["sha256"] = "not-a-hash"
        self.assertTrue(validate_manifest(data))


if __name__ == "__main__":
    unittest.main()
