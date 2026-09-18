"""H.2 -> G authorization bridge tests (Milestone H.2, Task 8).

Deterministic and offline. These tests prove:

- the committed H.2 candidate, its projection into a G ``ReleaseCandidate``, and
  the committed synthetic-human H.2 authorization verify cleanly;
- the committed authorization is a *new* exact-candidate fixture (it does not
  reuse the historical H.1/G authorization and cannot authorize the H.2
  candidate);
- every H.2-only binding fails closed: source SHA, artifact digest, environment,
  migration-set identity, release-config identity, H.1 report ref, the committed
  H.2 hardening report candidate identity, and the artifact manifest digest;
- G validity is delegated to the existing release gate (spy + propagation of the
  gate's own exceptions);
- no code under ``tooling/release`` creates, imports a creator of, or defines an
  authorization creation path.
"""

from __future__ import annotations

import ast
import dataclasses
import json
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

from tooling.production_authorization.errors import (
    ProductionAuthorizationCandidateMismatch,
    ProductionAuthorizationEnvironmentMismatch,
    ProductionAuthorizationInvalidated,
)
from tooling.production_authorization.models import (
    ProductionAuthorization,
    ReleaseActor,
    canonical_json,
)
from tooling.production_authorization.validity import AuthorizationEvent
from tooling.production_authorization.validate import validate_client_authorizations
from tooling.release.coordinator import (
    H2AuthorizationBridgeError,
    verify_h2_authorized_candidate,
)
from tooling.release.evidence import (
    build_h2_authorization_ref,
    build_h2_g_candidate,
    h2_authorization_path,
    h2_authorization_ref_path,
    load_artifact_manifest,
    load_f_report,
    load_h2_authorization,
    load_h2_authorization_ref,
    load_h2_candidate,
    load_hardening_report,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
RELEASE_DIR = ROOT / "tooling" / "release"

H2_AUTHORIZATION_RELATIVE = (
    "client-projects/reference-commerce/release/reference-proof/"
    "production-authorization-v0001.json"
)
H2_AUTHORIZATION_PATH = h2_authorization_path(CLIENT)
HISTORICAL_AUTHORIZATION_PATH = (
    CLIENT
    / "release"
    / "production-authorizations"
    / "production"
    / "authorization-v0001.json"
)

AUTHORIZATION_ID = "pa-reference-commerce-production-h2-0001"
AUTHORIZATION_VERSION = 1
AUTHORIZED_AT = datetime(2026, 9, 18, 10, 0, 0, tzinfo=timezone.utc)
RELEASE_OWNER = ReleaseActor(
    actor_id="release-owner-reference",
    name="Reference Release Owner",
    kind="human",
    role="release_owner",
)

FORBIDDEN_IMPORT_MODULES = (
    "tooling.production_authorization.coordinator",
    "tooling.production_authorization.repository",
)
FORBIDDEN_IMPORT_NAMES = (
    "ProductionAuthorizationCoordinator",
    "FileProductionAuthorizationRepository",
    "ProductionAuthorizationRepository",
)
FORBIDDEN_CALL_NAMES = ("ProductionAuthorization",)
FORBIDDEN_DEFINITION_NAMES = ("create", "authorize")


def _load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_h2_authorization() -> ProductionAuthorization:
    return ProductionAuthorization.from_dict(load_h2_authorization(CLIENT))


def _authorization_for(candidate) -> ProductionAuthorization:
    """Rebuild the exact authorization the committed fixture must equal."""
    return ProductionAuthorization(
        authorization_id=AUTHORIZATION_ID,
        authorization_version=AUTHORIZATION_VERSION,
        client_id=candidate.client_id,
        environment=candidate.environment,
        approval_version=candidate.approval_version,
        approval_review_state_hash=candidate.approval_review_state_hash,
        approval_source_commit_sha=candidate.approval_source_commit_sha,
        source_commit_sha=candidate.source_commit_sha,
        build_artifact_id=candidate.build_artifact_id,
        build_hash=candidate.build_hash,
        qa_evidence_ids=tuple(item.evidence_id for item in candidate.qa_evidence),
        validation_evidence_ids=tuple(
            item.evidence_id for item in candidate.validation_evidence
        ),
        security_evidence_ids=tuple(
            item.evidence_id for item in candidate.security_evidence
        ),
        rollback_plan_ref=candidate.rollback_plan_ref,
        migration_plan_ref=candidate.migration_plan_ref,
        release_notes_ref=candidate.release_notes_ref,
        acknowledged_non_blocking_item_ids=(
            candidate.acknowledged_non_blocking_item_ids
        ),
        supporting_evidence_refs=candidate.supporting_evidence_refs,
        authorized_by=RELEASE_OWNER,
        authorized_at=AUTHORIZED_AT,
        supersedes=None,
    )


class BridgeFixtureMixin(unittest.TestCase):
    def fixture(self):
        h2 = load_h2_candidate(CLIENT)
        report = load_hardening_report(CLIENT)
        f_report = load_f_report(ROOT, CLIENT)
        g = build_h2_g_candidate(h2, report, f_report)
        auth = _load_h2_authorization()
        return h2, report, f_report, g, auth


class BridgeHappyPathTests(BridgeFixtureMixin):
    def test_committed_candidate_projection_and_authorization_verify(self):
        h2, _report, _f_report, g, auth = self.fixture()
        self.assertIsNone(verify_h2_authorized_candidate(h2, g, auth))

    def test_committed_authorization_matches_projection_exactly(self):
        _h2, _report, _f_report, g, auth = self.fixture()
        self.assertEqual(canonical_json(_authorization_for(g)), canonical_json(auth))

    def test_authorization_ref_binds_the_exact_candidate(self):
        h2, _report, _f_report, _g, _auth = self.fixture()
        ref = load_h2_authorization_ref(CLIENT)
        self.assertEqual(AUTHORIZATION_ID, ref["authorization_id"])
        self.assertEqual(AUTHORIZATION_VERSION, ref["authorization_version"])
        self.assertEqual(h2["candidate_identity"], ref["candidate_identity"])
        self.assertEqual(h2["artifact_digest"], ref["artifact_digest"])
        self.assertEqual(h2["source_sha"], ref["source_sha"])
        self.assertEqual(
            h2["migration_set_identity"], ref["migration_set_identity"]
        )
        self.assertEqual(
            h2["release_config_identity"], ref["release_config_identity"]
        )
        self.assertTrue(h2_authorization_ref_path(CLIENT).is_file())

    def test_committed_authorization_ref_equals_builder_output(self):
        h2, _report, _f_report, _g, auth = self.fixture()
        self.assertEqual(
            build_h2_authorization_ref(auth, h2),
            load_h2_authorization_ref(CLIENT),
        )

    def test_authorization_is_a_human_release_owner_and_active(self):
        auth = _load_h2_authorization()
        self.assertTrue(auth.authorized_by.is_human_release_owner)
        self.assertEqual("active", auth.status.value)

    def test_historical_g_authorization_cannot_authorize_the_h2_candidate(self):
        h2, _report, _f_report, g, _auth = self.fixture()
        historical = ProductionAuthorization.from_dict(
            _load_json(HISTORICAL_AUTHORIZATION_PATH)
        )
        auth = _load_h2_authorization()
        self.assertNotEqual(historical.authorization_id, auth.authorization_id)
        self.assertNotEqual(historical.build_hash, auth.build_hash)
        self.assertNotEqual(historical.source_commit_sha, auth.source_commit_sha)
        with self.assertRaises(Exception):
            verify_h2_authorized_candidate(h2, g, historical)


class BridgeMismatchTests(BridgeFixtureMixin):
    def _assert_bridge_error(self, h2, g, auth):
        with self.assertRaises(H2AuthorizationBridgeError):
            verify_h2_authorized_candidate(h2, g, auth)

    def test_source_sha_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["source_sha"] = "0" * 40
        self._assert_bridge_error(bad, g, auth)

    def test_artifact_digest_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["artifact_digest"] = "sha256:" + "1" * 64
        self._assert_bridge_error(bad, g, auth)

    def test_environment_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["target_environment"] = "staging"
        self._assert_bridge_error(bad, g, auth)

    def test_build_version_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["build_version"] = "9.9.9+tampered"
        self._assert_bridge_error(bad, g, auth)

    def test_migration_set_identity_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["migration_set_identity"] = "sha256:" + "2" * 64
        self._assert_bridge_error(bad, g, auth)

    def test_release_config_identity_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["release_config_identity"] = "sha256:" + "3" * 64
        self._assert_bridge_error(bad, g, auth)

    def test_h1_report_ref_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["h1_foundation_report_ref"] = (
            "client-projects/reference-commerce/production/evidence/"
            "h2-hardening-report.json"
        )
        self._assert_bridge_error(bad, g, auth)

    def test_absolute_h1_report_ref_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["h1_foundation_report_ref"] = str(
            ROOT / h2["h1_foundation_report_ref"]
        )
        self.assertTrue(Path(bad["h1_foundation_report_ref"]).is_absolute())
        self._assert_bridge_error(bad, g, auth)

    def test_parent_segment_h1_report_ref_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dict(h2)
        bad["h1_foundation_report_ref"] = (
            "client-projects/reference-commerce/production/evidence/"
            "nested/../h1-foundation-report.json"
        )
        self.assertIn("..", bad["h1_foundation_report_ref"].split("/"))
        self.assertEqual(
            (ROOT / bad["h1_foundation_report_ref"]).resolve(),
            (ROOT / h2["h1_foundation_report_ref"]).resolve(),
        )
        self._assert_bridge_error(bad, g, auth)

    def test_hardening_report_bound_to_another_candidate_fails(self):
        h2, report, _f_report, g, auth = self.fixture()
        other = dict(report)
        other["candidate_identity"] = "sha256:" + "4" * 64
        with mock.patch(
            "tooling.release.coordinator.load_hardening_report", return_value=other
        ):
            self._assert_bridge_error(h2, g, auth)

    def test_artifact_manifest_digest_mismatch_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        manifest = load_artifact_manifest(CLIENT)
        other = dict(manifest)
        other["artifact_digest"] = "sha256:" + "5" * 64
        with mock.patch(
            "tooling.release.coordinator.load_artifact_manifest", return_value=other
        ):
            self._assert_bridge_error(h2, g, auth)

    def test_invalidated_g_authorization_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        event = AuthorizationEvent(
            event_id="event-invalidated",
            authorization_id=auth.authorization_id,
            event_type="invalidated",
            reason="test invalidation",
            actor=RELEASE_OWNER,
            occurred_at=AUTHORIZED_AT,
        )
        with self.assertRaises(ProductionAuthorizationInvalidated):
            verify_h2_authorized_candidate(h2, g, auth, (event,))

    def test_revoked_g_authorization_fails(self):
        h2, _report, _f_report, g, auth = self.fixture()
        event = AuthorizationEvent(
            event_id="event-revoked",
            authorization_id=auth.authorization_id,
            event_type="revoked",
            reason="test revocation",
            actor=RELEASE_OWNER,
            occurred_at=AUTHORIZED_AT,
        )
        with self.assertRaises(ProductionAuthorizationInvalidated):
            verify_h2_authorized_candidate(h2, g, auth, (event,))


class BridgeDelegationTests(BridgeFixtureMixin):
    def test_release_gate_is_invoked_with_the_exact_candidate(self):
        h2, _report, _f_report, g, auth = self.fixture()
        from tooling.production_authorization.release_gate import (
            verify_release_gate as real_gate,
        )

        with mock.patch(
            "tooling.release.coordinator.verify_release_gate",
            side_effect=real_gate,
        ) as patched:
            verify_h2_authorized_candidate(h2, g, auth)
        patched.assert_called_once_with(auth, g, ())

    def test_g_only_mismatch_propagates_the_g_exception(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dataclasses.replace(auth, build_artifact_id="wrong-artifact-id")
        with self.assertRaises(ProductionAuthorizationCandidateMismatch):
            verify_h2_authorized_candidate(h2, g, bad)

    def test_g_environment_mismatch_propagates_the_g_exception(self):
        h2, _report, _f_report, g, auth = self.fixture()
        bad = dataclasses.replace(auth, environment="staging")
        with self.assertRaises(ProductionAuthorizationEnvironmentMismatch):
            verify_h2_authorized_candidate(h2, g, bad)


class AuthorityBoundaryTests(unittest.TestCase):
    def _release_modules(self):
        modules = sorted(RELEASE_DIR.rglob("*.py"))
        self.assertTrue(
            modules,
            f"authority-boundary scan is vacuous: no .py files under {RELEASE_DIR}",
        )
        return modules

    def test_tooling_release_never_imports_or_constructs_authorization_creation(self):
        for path in self._release_modules():
            source = path.read_text(encoding="utf-8")
            relative = path.relative_to(ROOT).as_posix()
            tree = ast.parse(source)
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom):
                    self.assertNotIn(node.module or "", FORBIDDEN_IMPORT_MODULES, relative)
                    for alias in node.names:
                        self.assertNotIn(alias.name, FORBIDDEN_IMPORT_NAMES, relative)
                elif isinstance(node, ast.Import):
                    for alias in node.names:
                        self.assertNotIn(alias.name, FORBIDDEN_IMPORT_NAMES, relative)
                elif isinstance(node, ast.Call):
                    func = node.func
                    name = (
                        func.id
                        if isinstance(func, ast.Name)
                        else func.attr
                        if isinstance(func, ast.Attribute)
                        else ""
                    )
                    self.assertNotIn(name, FORBIDDEN_CALL_NAMES, relative)
            self.assertNotIn("ProductionAuthorizationCoordinator", source, relative)
            self.assertNotIn("FileProductionAuthorizationRepository", source, relative)
            self.assertNotIn("ProductionAuthorizationRepository", source, relative)
            self.assertNotIn(".create(", source, relative)

    def test_tooling_release_defines_no_authorize_or_create_function(self):
        for path in self._release_modules():
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    self.assertNotIn(
                        node.name,
                        FORBIDDEN_DEFINITION_NAMES,
                        f"{path.relative_to(ROOT).as_posix()}:{node.name}",
                    )


class AuthorizationPlacementTests(unittest.TestCase):
    """The H.2 authorization is a G authority artifact, never a production one.

    The synthetic human authorization is a *permission*, not a production
    implementation artifact, so it must not live under ``production/`` (the H.1
    authority boundary) nor inside the G authorization area
    ``release/production-authorizations/`` (which the G validator scans). It is
    committed as a reference proof and must not alter G's validated set.
    """

    def test_fixture_lives_at_the_reference_proof_path(self):
        self.assertTrue(H2_AUTHORIZATION_PATH.is_file(), H2_AUTHORIZATION_PATH)
        self.assertEqual(
            H2_AUTHORIZATION_RELATIVE,
            H2_AUTHORIZATION_PATH.relative_to(ROOT).as_posix(),
        )

    def test_authorization_body_is_not_under_production(self):
        production_dir = CLIENT / "production"
        self.assertNotIn(production_dir, H2_AUTHORIZATION_PATH.parents)
        colliding = (
            production_dir
            / "release"
            / "production-authorizations"
            / "production"
            / "authorization-v0001.json"
        )
        self.assertFalse(colliding.exists(), colliding)
        self.assertFalse(
            (production_dir / "release" / "production-authorizations").exists(),
            "the colliding synthetic authorization directory must be deleted",
        )

    def test_authorization_body_is_not_in_the_g_authorization_area(self):
        self.assertFalse(
            H2_AUTHORIZATION_PATH.is_relative_to(
                CLIENT / "release" / "production-authorizations"
            ),
            H2_AUTHORIZATION_PATH,
        )

    def test_ref_points_at_the_new_authorization_path_and_identity(self):
        ref = load_h2_authorization_ref(CLIENT)
        self.assertEqual(H2_AUTHORIZATION_RELATIVE, ref.get("authorization_path"))
        referenced = ROOT / str(ref["authorization_path"])
        self.assertTrue(referenced.is_file(), referenced)
        body = ProductionAuthorization.from_dict(load_h2_authorization(CLIENT))
        self.assertEqual(ref["authorization_id"], body.authorization_id)
        self.assertEqual(ref["authorization_version"], body.authorization_version)

    def test_reference_proof_does_not_enter_the_g_authorization_set(self):
        from tooling.production_authorization.repository import (
            FileProductionAuthorizationRepository,
        )

        authorizations = FileProductionAuthorizationRepository(CLIENT).list(
            "reference-commerce", "production"
        )
        self.assertEqual(
            ["pa-reference-commerce-production-0001"],
            [item.authorization_id for item in authorizations],
        )

    def test_g_validation_remains_clean(self):
        self.assertEqual([], validate_client_authorizations(ROOT, CLIENT))


class DeterminismTests(BridgeFixtureMixin):
    def test_projection_is_deterministic(self):
        h2, report, f_report, g, _auth = self.fixture()
        again = build_h2_g_candidate(h2, report, f_report)
        self.assertEqual(canonical_json(g), canonical_json(again))

    def test_authorization_ref_is_deterministic(self):
        h2, _report, _f_report, _g, auth = self.fixture()
        self.assertEqual(
            build_h2_authorization_ref(auth, h2),
            build_h2_authorization_ref(auth, h2),
        )

    def test_bridge_is_repeatable_offline(self):
        h2, _report, _f_report, g, auth = self.fixture()
        verify_h2_authorized_candidate(h2, g, auth)
        verify_h2_authorized_candidate(h2, g, auth)


if __name__ == "__main__":
    unittest.main()
