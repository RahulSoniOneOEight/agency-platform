"""Deterministic H.2 candidate/artifact integrity tests (Milestone H.2, Task 5).

These tests are Flutter-free and network-free. They prove:

- cross-language canonical-identity parity with the Dart golden vectors;
- candidate identity changes when any bound input changes;
- artifact-manifest verification rejects digest, ordering, and duplicate
  tampering with stable sorted errors;
- the committed reference candidate binds the H.1 production config identity,
  the repository migration set, and the committed artifact fixture;
- the candidate-build workflow builds and uploads only, with no release action
  and exactly one Flutter Web build.
"""

from __future__ import annotations

import io
import json
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from tooling.hardening.candidate import (
    APPROVAL_EVIDENCE_RELATIVE,
    CANONICAL_FIELDS,
    CANDIDATE_NAME,
    FIXTURE_BUILD_VERSION,
    FIXTURE_SOURCE_SHA,
    MANIFEST_NAME,
    RELEASE_RELATIVE,
    build_artifact_manifest,
    build_candidate,
    canonical_identity,
    main,
    validate_candidate,
    verify_candidate_artifact,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
RELEASE_DIR = CLIENT / RELEASE_RELATIVE
FIXTURE_ARTIFACT = RELEASE_DIR / "artifact-fixture"
CANDIDATE_PATH = RELEASE_DIR / CANDIDATE_NAME
MANIFEST_PATH = RELEASE_DIR / MANIFEST_NAME
H1_REPORT = CLIENT / "production" / "evidence" / "h1-foundation-report.json"
APPROVAL_EVIDENCE = CLIENT / APPROVAL_EVIDENCE_RELATIVE
APPROVAL_EVIDENCE_REF = (
    "client-projects/reference-commerce/reference-e2e/evidence/"
    "review-approval-evidence.json"
)
WORKFLOW = ROOT / ".github" / "workflows" / "candidate-build.yml"

GOLDEN_DIGEST = (
    "sha256:934f8ac3511500a156959782c6a51225d0f3595bbe10d1f40689546eeda6f20c"
)
DEL_GOLDEN_DIGEST = (
    "sha256:4524d5df540240cacc11237736ea82483fdd205b875b4b748b1f1c9923c26f9e"
)

# The two canonicalization fixtures are shared verbatim with the Dart tests in
# packages/agency_operations_core/test/release_candidate_test.dart.
GOLDEN_VALUE: dict[str, object] = {
    "client_id": "caf\u00e9-commerce",
    "migration_set": ["2026-01-init.sql", "2026-02-nested/\u00e9.sql"],
    "nested": {
        "labels": ["d\u00e9j\u00e0 vu", "na\u00efve"],
        "flags": [True, False, None],
    },
}

DEL_GOLDEN_VALUE: dict[str, object] = {
    "boundary": ["tilde:~", "del:\u007f", "unit:\u001f"],
    "client_id": "caf\u00e9-\u007f",
}


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _materialize_client(root: Path) -> Path:
    """Copy the reference client config/evidence/release tree under *root*.

    Returns the copied client directory so a test can tamper with it without
    touching the committed repository state.
    """
    client = root / "client-projects" / "reference-commerce"
    (client / "production").mkdir(parents=True)
    shutil.copytree(CLIENT / "production" / "config", client / "production" / "config")
    shutil.copytree(
        CLIENT / "production" / "evidence", client / "production" / "evidence"
    )
    shutil.copytree(RELEASE_DIR, client / "production" / "release")
    migrations = root / "supabase" / "migrations"
    migrations.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "supabase" / "migrations", migrations)
    return client


def _write_candidate(path: Path, candidate: dict[str, object]) -> None:
    path.write_text(json.dumps(candidate), encoding="utf-8")


def _base_fields(**overrides: object) -> dict[str, object]:
    fields: dict[str, object] = {
        "client_id": "reference-commerce",
        "target_environment": "production",
        "source_sha": FIXTURE_SOURCE_SHA,
        "artifact_digest": "sha256:" + "a" * 64,
        "build_version": FIXTURE_BUILD_VERSION,
        "migration_set": ["supabase/migrations/202609180001_x.sql"],
        "release_config_identity": "sha256:" + "b" * 64,
        "approved_experience_ref": APPROVAL_EVIDENCE_REF,
        "h1_foundation_report_ref": (
            "client-projects/reference-commerce/production/evidence/"
            "h1-foundation-report.json"
        ),
    }
    fields.update(overrides)
    return fields


def _assert_stable(test: unittest.TestCase, errors: list[str]) -> None:
    test.assertTrue(errors, errors)
    test.assertEqual(errors, sorted(errors))
    test.assertEqual(errors, sorted(set(errors)))


class GoldenParityTests(unittest.TestCase):
    def test_golden_vectors_match_dart_pinned_digests(self):
        self.assertEqual(GOLDEN_DIGEST, canonical_identity(GOLDEN_VALUE))
        self.assertEqual(DEL_GOLDEN_DIGEST, canonical_identity(DEL_GOLDEN_VALUE))


class CandidateIdentityTests(unittest.TestCase):
    def test_candidate_identity_is_canonical_over_nine_fields(self):
        candidate = build_candidate(
            ROOT, CLIENT, FIXTURE_ARTIFACT, FIXTURE_SOURCE_SHA, FIXTURE_BUILD_VERSION
        )
        fields = {field: candidate[field] for field in CANONICAL_FIELDS}
        self.assertEqual(canonical_identity(fields), candidate["candidate_identity"])

    def test_candidate_identity_changes_on_source_sha(self):
        first = build_candidate(
            ROOT, CLIENT, FIXTURE_ARTIFACT, FIXTURE_SOURCE_SHA, FIXTURE_BUILD_VERSION
        )
        second = build_candidate(
            ROOT, CLIENT, FIXTURE_ARTIFACT, "a" * 40, FIXTURE_BUILD_VERSION
        )
        self.assertNotEqual(
            first["candidate_identity"], second["candidate_identity"]
        )

    def test_candidate_identity_changes_on_artifact_digest(self):
        with tempfile.TemporaryDirectory() as tmp:
            first_artifact = Path(tmp) / "first"
            second_artifact = Path(tmp) / "second"
            first_artifact.mkdir()
            second_artifact.mkdir()
            (first_artifact / "index.html").write_text("<html>a</html>", encoding="utf-8")
            (second_artifact / "index.html").write_text("<html>b</html>", encoding="utf-8")
            first = build_candidate(
                ROOT,
                CLIENT,
                first_artifact,
                FIXTURE_SOURCE_SHA,
                FIXTURE_BUILD_VERSION,
            )
            second = build_candidate(
                ROOT,
                CLIENT,
                second_artifact,
                FIXTURE_SOURCE_SHA,
                FIXTURE_BUILD_VERSION,
            )
        self.assertNotEqual(
            first["artifact_digest"], second["artifact_digest"]
        )
        self.assertNotEqual(
            first["candidate_identity"], second["candidate_identity"]
        )

    def test_candidate_identity_changes_on_target_environment(self):
        self.assertNotEqual(
            canonical_identity(_base_fields(target_environment="production")),
            canonical_identity(_base_fields(target_environment="staging")),
        )

    def test_candidate_identity_changes_on_release_config_identity(self):
        self.assertNotEqual(
            canonical_identity(_base_fields(release_config_identity="sha256:" + "b" * 64)),
            canonical_identity(_base_fields(release_config_identity="sha256:" + "c" * 64)),
        )

    def test_candidate_identity_changes_on_migration_set(self):
        self.assertNotEqual(
            canonical_identity(_base_fields(migration_set=["2026-01-init.sql"])),
            canonical_identity(
                _base_fields(migration_set=["2026-01-init.sql", "2026-02-next.sql"])
            ),
        )

    def test_migration_set_identity_changes_with_migration_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            migrations = root / "supabase" / "migrations"
            migrations.mkdir(parents=True)
            migration = migrations / "202609180001_reference.sql"
            migration.write_text("select 1;", encoding="utf-8")
            first = build_candidate(
                root, CLIENT, FIXTURE_ARTIFACT, FIXTURE_SOURCE_SHA, FIXTURE_BUILD_VERSION
            )
            migration.write_text("select 2;", encoding="utf-8")
            second = build_candidate(
                root, CLIENT, FIXTURE_ARTIFACT, FIXTURE_SOURCE_SHA, FIXTURE_BUILD_VERSION
            )
        self.assertNotEqual(
            first["migration_set_identity"], second["migration_set_identity"]
        )

    def test_migration_set_identity_recomputable_from_embedded_entries(self):
        candidate = build_candidate(
            ROOT, CLIENT, FIXTURE_ARTIFACT, FIXTURE_SOURCE_SHA, FIXTURE_BUILD_VERSION
        )
        entries = candidate["migration_set_entries"]
        self.assertTrue(entries)
        self.assertEqual(
            [entry["path"] for entry in entries], candidate["migration_set"]
        )
        self.assertEqual(
            canonical_identity(entries), candidate["migration_set_identity"]
        )


class ArtifactIntegrityTests(unittest.TestCase):
    def test_build_artifact_manifest_is_sorted_and_self_verifying(self):
        manifest = build_artifact_manifest(FIXTURE_ARTIFACT)
        paths = [entry["path"] for entry in manifest["entries"]]
        self.assertEqual(sorted(paths), paths)
        self.assertEqual(len(paths), len(set(paths)))
        self.assertEqual(
            canonical_identity({"entries": manifest["entries"]}),
            manifest["artifact_digest"],
        )
        self.assertEqual(_load(MANIFEST_PATH), manifest)

    def test_verify_rejects_artifact_digest_mismatch(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        manifest["artifact_digest"] = "sha256:" + "0" * 64
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(
            any("does not match candidate.artifact_digest" in error for error in errors),
            errors,
        )

    def test_verify_rejects_unsorted_manifest(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        manifest["entries"] = list(reversed(manifest["entries"]))
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(any("paths must be sorted" in error for error in errors), errors)

    def test_verify_rejects_duplicate_manifest_entries(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        manifest["entries"] = [manifest["entries"][0], manifest["entries"][0]]
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(any("paths must be unique" in error for error in errors), errors)

    def test_verify_reports_missing_candidate_fields(self):
        errors = verify_candidate_artifact({}, {"entries": []})
        _assert_stable(self, errors)
        self.assertTrue(
            any("missing required candidate field" in error for error in errors), errors
        )

    def test_verify_errors_are_stable_sorted_and_unique(self):
        candidate = _load(CANDIDATE_PATH)
        candidate["source_sha"] = "not-a-sha"
        candidate["artifact_digest"] = "nope"
        candidate["release_config_identity"] = "nope"
        errors = verify_candidate_artifact(candidate, {"entries": []})
        _assert_stable(self, errors)
        self.assertEqual(errors, verify_candidate_artifact(candidate, {"entries": []}))

    def test_verify_rejects_tampered_migration_entries(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        candidate["migration_set_entries"][0]["sha256"] = "sha256:" + "0" * 64
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "does not match the recomputed migration set identity" in error
                for error in errors
            ),
            errors,
        )

    def test_verify_rejects_tampered_migration_set_identity(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        candidate["migration_set_identity"] = "sha256:" + "0" * 64
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "does not match the recomputed migration set identity" in error
                for error in errors
            ),
            errors,
        )

    def test_verify_rejects_migration_entries_not_matching_migration_set(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        candidate["migration_set_entries"][0]["path"] = (
            "supabase/migrations/other.sql"
        )
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "paths must match candidate.migration_set" in error
                for error in errors
            ),
            errors,
        )

    def test_verify_rejects_unknown_top_level_field(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        candidate["unexpected_field"] = "x"
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(
            any("unknown top-level candidate field" in error for error in errors),
            errors,
        )

    def test_verify_rejects_empty_required_field(self):
        candidate = _load(CANDIDATE_PATH)
        manifest = _load(MANIFEST_PATH)
        candidate["client_id"] = ""
        errors = verify_candidate_artifact(candidate, manifest)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "candidate.client_id: must be a non-empty string" in error
                for error in errors
            ),
            errors,
        )

    def test_verify_rejects_non_relative_manifest_paths(self):
        candidate = _load(CANDIDATE_PATH)
        for bad_path in ("/absolute/index.html", "../escape.html", "dir\\file.html"):
            manifest = _load(MANIFEST_PATH)
            manifest["entries"][0]["path"] = bad_path
            errors = verify_candidate_artifact(candidate, manifest)
            _assert_stable(self, errors)
            self.assertTrue(
                any("POSIX relative path" in error for error in errors),
                (bad_path, errors),
            )

    def test_verify_rejects_non_relative_migration_paths(self):
        manifest = _load(MANIFEST_PATH)
        for bad_path in ("/absolute/x.sql", "../escape.sql", "dir\\x.sql"):
            candidate = _load(CANDIDATE_PATH)
            candidate["migration_set_entries"][0]["path"] = bad_path
            errors = verify_candidate_artifact(candidate, manifest)
            _assert_stable(self, errors)
            self.assertTrue(
                any("POSIX relative path" in error for error in errors),
                (bad_path, errors),
            )


class ReferenceCandidateTests(unittest.TestCase):
    def test_fixture_candidate_is_reproducible(self):
        expected = build_candidate(
            ROOT, CLIENT, FIXTURE_ARTIFACT, FIXTURE_SOURCE_SHA, FIXTURE_BUILD_VERSION
        )
        self.assertEqual(_load(CANDIDATE_PATH), expected)

    def test_release_config_identity_matches_h1_production_config(self):
        candidate = _load(CANDIDATE_PATH)
        report = _load(H1_REPORT)
        production = next(
            entry
            for entry in report["environments"]
            if entry["environment"] == "production"
        )
        self.assertEqual(
            "sha256:43b6737e3c7922c81e8620d113a2f4bd8c2e518578b160fc50c949f35b1659d0",
            production["config_identity"],
        )
        self.assertEqual(
            production["config_identity"], candidate["release_config_identity"]
        )

    def test_approved_experience_ref_points_to_existing_approval_evidence(self):
        candidate = _load(CANDIDATE_PATH)
        self.assertEqual(APPROVAL_EVIDENCE_REF, candidate["approved_experience_ref"])
        self.assertTrue(APPROVAL_EVIDENCE.is_file())
        self.assertTrue(
            (ROOT / candidate["approved_experience_ref"]).is_file(),
            candidate["approved_experience_ref"],
        )
        self.assertFalse(
            (CLIENT / "approved-experience.yaml").exists(),
            "H.2 must not create approval authority (R13)",
        )

    def test_validate_candidate_reference_is_clean(self):
        self.assertEqual([], validate_candidate(ROOT, CLIENT))

    def test_validate_candidate_detects_tampered_release_config_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            candidate_path = client / "production" / "release" / CANDIDATE_NAME
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            candidate["release_config_identity"] = "sha256:" + "0" * 64
            _write_candidate(candidate_path, candidate)
            errors = validate_candidate(root, client)
        _assert_stable(self, errors)
        self.assertTrue(
            any("release_config_identity" in error for error in errors), errors
        )

    def test_validate_candidate_rejects_tampered_pinned_source_sha(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            candidate_path = client / "production" / "release" / CANDIDATE_NAME
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            candidate["source_sha"] = "a" * 40
            candidate["candidate_identity"] = canonical_identity(
                {field: candidate[field] for field in CANONICAL_FIELDS}
            )
            _write_candidate(candidate_path, candidate)
            errors = validate_candidate(root, client)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "source_sha does not match the pinned fixture" in error
                for error in errors
            ),
            errors,
        )

    def test_validate_candidate_rejects_tampered_pinned_build_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            candidate_path = client / "production" / "release" / CANDIDATE_NAME
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            candidate["build_version"] = "9.9.9+tampered"
            candidate["candidate_identity"] = canonical_identity(
                {field: candidate[field] for field in CANONICAL_FIELDS}
            )
            _write_candidate(candidate_path, candidate)
            errors = validate_candidate(root, client)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "build_version does not match the pinned fixture" in error
                for error in errors
            ),
            errors,
        )

    def test_validate_candidate_rejects_tampered_migration_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            client = _materialize_client(root)
            candidate_path = client / "production" / "release" / CANDIDATE_NAME
            candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
            candidate["migration_set_entries"][0]["sha256"] = "sha256:" + "0" * 64
            _write_candidate(candidate_path, candidate)
            errors = validate_candidate(root, client)
        _assert_stable(self, errors)
        self.assertTrue(
            any(
                "does not match the recomputed migration set identity" in error
                for error in errors
            ),
            errors,
        )

    def test_main_validates_reference_cleanly(self):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(0, main([str(CLIENT)]))
        self.assertEqual("", buffer.getvalue())


class CandidateBuildWorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WORKFLOW.read_text(encoding="utf-8")
        self.lowered = self.text.lower()

    def test_candidate_build_workflow_has_required_build_and_upload_steps(self):
        self.assertIn("workflow_dispatch", self.text)
        self.assertIn("actions/checkout@v4", self.text)
        self.assertIn("github.sha", self.text)
        self.assertIn("subosito/flutter-action@v2", self.text)
        self.assertIn("channel: stable", self.text)
        self.assertIn("python -m tooling.production.validate_config", self.text)
        self.assertIn("python -m tooling.production.validate_migrations", self.text)
        self.assertIn("python -m tooling.production.report", self.text)
        self.assertIn("python -m tooling.hardening.candidate", self.text)
        self.assertIn("actions/upload-artifact@v4", self.text)

    def test_candidate_build_workflow_is_non_deploying(self):
        self.assertNotIn("wrangler", self.lowered)
        self.assertNotIn("deploy", self.lowered)
        self.assertNotIn("authorization", self.lowered)
        self.assertEqual(1, self.lowered.count("flutter build web"))


if __name__ == "__main__":
    unittest.main()
