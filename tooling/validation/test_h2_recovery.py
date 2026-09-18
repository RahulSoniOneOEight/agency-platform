"""Deterministic H.2 governed recovery tests (Milestone H.2, Task 10).

Offline and provider-free. These tests prove the recovery coordinator:

- rolls an application back only to the previous-known-good artifact/deployment
  identified by the ReleaseRecord chain, and rejects a different/new digest;
- permits database reversal only when the exact migration metadata is
  reversible *and* the committed recovery policy allows it;
- never executes reverse SQL otherwise (blind rollback prohibited), resolving to
  a forward recovery migration or a manual halt;
- executes nothing on a manual halt;
- returns an immutable, self-verifying recovery report;
- and validates the committed reference ``recovery-report.json`` cleanly.

Fake deployment/migration ports record their calls, so no network or provider is
touched.
"""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tooling.release.recovery import (
    ACTION_APPLICATION_ROLLBACK,
    ACTION_DATABASE_REVERSE,
    ACTION_FORWARD_RECOVERY,
    ACTION_MANUAL_HALT,
    build_reference_recovery_report,
    decision_identity,
    execute_recovery,
    load_recovery_policy,
    load_recovery_report,
    plan_recovery,
    recovery_report_identity,
    recovery_report_path,
    validate_recovery,
)

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
REPORT = CLIENT / "production" / "evidence" / "recovery-report.json"

KNOWN_GOOD_DIGEST = "sha256:" + "a" * 64
NEW_DIGEST = "sha256:" + "b" * 64
FAILED_ID = "rel-reference-commerce-production-failed-0001"
KNOWN_GOOD_ID = "rel-reference-commerce-production-0001"
MIGRATION = "supabase/migrations/202609180001_reference_commerce_foundation.sql"


def _policy(modes: list[str] | None = None) -> dict:
    return {
        "policy_version": 1,
        "modes": modes
        if modes is not None
        else [
            "application-rollback",
            "database-reverse-migration",
            "forward-recovery-migration",
            "manual-halt",
        ],
        "application_rollback": {"previous_known_good_only": True},
        "database_reversal": {
            "requires_reversible_flag": True,
            "blind_rollback_prohibited": True,
        },
        "new_artifact_is_new_candidate": True,
    }


def _known_good(digest: str = KNOWN_GOOD_DIGEST) -> dict:
    return {
        "release_id": KNOWN_GOOD_ID,
        "artifact_digest": digest,
        "release_status": "healthy",
    }


def _failed(**request: object) -> dict:
    record = {
        "release_id": FAILED_ID,
        "artifact_digest": NEW_DIGEST,
        "release_status": "failed",
        "previous_known_good_release_id": KNOWN_GOOD_ID,
        "migration_set": [MIGRATION],
    }
    if request:
        record["recovery"] = dict(request)
    return record


class RecordingDeploymentPort:
    def __init__(self, ok: bool = True) -> None:
        self.calls: list[dict] = []
        self.ok = ok

    def rollbackToKnownGood(self, target: dict) -> dict:
        self.calls.append(dict(target))
        return {"ok": self.ok, "deployment_id": "production-deploy-rollback-0001"}


class RecordingMigrationExecutor:
    def __init__(self) -> None:
        self.forward: list[object] = []
        self.reverse: list[object] = []

    def applyForwardMigration(self, migration: object) -> dict:
        self.forward.append(migration)
        return {"ok": True}

    def reverseMigration(self, migration: object) -> dict:
        self.reverse.append(migration)
        return {"ok": True}


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


class PlanApplicationRollbackTests(unittest.TestCase):
    def test_default_rollback_targets_previous_known_good(self):
        decision = plan_recovery(_failed(), _policy(), _known_good())
        self.assertEqual(ACTION_APPLICATION_ROLLBACK, decision["action"])
        self.assertEqual("permitted", decision["outcome"])
        self.assertTrue(decision["permitted"])
        self.assertEqual(KNOWN_GOOD_DIGEST, decision["target_artifact_digest"])
        self.assertEqual(KNOWN_GOOD_ID, decision["previous_known_good_release_id"])
        self.assertEqual("none", decision["migration_action"])

    def test_a_different_new_artifact_digest_is_not_a_rollback(self):
        decision = plan_recovery(
            _failed(action=ACTION_APPLICATION_ROLLBACK, target_artifact_digest=NEW_DIGEST),
            _policy(),
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        self.assertEqual("denied", decision["outcome"])
        self.assertEqual("new_artifact_is_new_candidate", decision["reason"])
        self.assertEqual("none", decision["migration_action"])

    def test_rollback_without_previous_known_good_is_not_permitted(self):
        decision = plan_recovery(
            _failed(action=ACTION_APPLICATION_ROLLBACK),
            _policy(),
            None,
        )
        self.assertFalse(decision["permitted"])
        self.assertEqual("no_previous_known_good", decision["reason"])
        self.assertIn(
            decision["outcome"], ("forward_recovery_required", "manual_halt_required")
        )

    def test_policy_forbidding_rollback_halts(self):
        decision = plan_recovery(
            _failed(action=ACTION_APPLICATION_ROLLBACK),
            _policy(modes=["manual-halt"]),
            _known_good(),
        )
        self.assertEqual(ACTION_MANUAL_HALT, decision["action"])
        self.assertEqual("manual_halt_required", decision["outcome"])
        self.assertFalse(decision["permitted"])

    def test_mismatched_previous_known_good_is_rejected(self):
        other = _known_good()
        other["release_id"] = "rel-some-other-release"
        other["artifact_digest"] = "sha256:" + "c" * 64
        decision = plan_recovery(_failed(), _policy(), other)
        self.assertFalse(decision["permitted"])
        self.assertEqual("previous_known_good_mismatch", decision["reason"])
        self.assertIn(
            decision["outcome"],
            ("forward_recovery_required", "manual_halt_required"),
        )

    def test_unknown_action_does_not_default_to_rollback(self):
        decision = plan_recovery(
            _failed(action="evil_action"), _policy(), _known_good()
        )
        self.assertEqual(ACTION_MANUAL_HALT, decision["action"])
        self.assertEqual("manual_halt_required", decision["outcome"])
        self.assertFalse(decision["permitted"])
        self.assertEqual("unknown_recovery_action", decision["reason"])

    def test_decision_identity_self_verifies(self):
        decision = plan_recovery(_failed(), _policy(), _known_good())
        self.assertEqual(
            decision["decision_identity"], decision_identity(decision)
        )


class PlanDatabaseRecoveryTests(unittest.TestCase):
    def _reverse(self, reversible: bool | None = None, metadata: bool = True):
        request: dict = {"action": ACTION_DATABASE_REVERSE, "migration_path": MIGRATION}
        if metadata:
            request["migration_metadata"] = {MIGRATION: {"reversible": reversible}}
        return plan_recovery(_failed(**request), _policy(), _known_good())

    def test_reversible_migration_is_permitted(self):
        decision = self._reverse(reversible=True)
        self.assertEqual(ACTION_DATABASE_REVERSE, decision["action"])
        self.assertEqual("permitted", decision["outcome"])
        self.assertTrue(decision["permitted"])
        self.assertEqual("reverse", decision["migration_action"])
        self.assertEqual(MIGRATION, decision["migration_path"])

    def test_non_reversible_migration_requires_forward_recovery(self):
        decision = self._reverse(reversible=False)
        self.assertFalse(decision["permitted"])
        self.assertEqual("forward_recovery_required", decision["outcome"])
        self.assertEqual(ACTION_FORWARD_RECOVERY, decision["action"])
        self.assertEqual("forward", decision["migration_action"])

    def test_missing_migration_metadata_is_not_reversible(self):
        decision = self._reverse(metadata=False)
        self.assertFalse(decision["permitted"])
        self.assertEqual("forward_recovery_required", decision["outcome"])
        self.assertEqual(ACTION_FORWARD_RECOVERY, decision["action"])

    def test_policy_disallowing_database_reverse_forces_forward(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": True}},
            ),
            _policy(modes=["application-rollback", "forward-recovery-migration", "manual-halt"]),
            _known_good(),
        )
        self.assertEqual("forward_recovery_required", decision["outcome"])
        self.assertEqual(ACTION_FORWARD_RECOVERY, decision["action"])

    def test_no_forward_mode_halts_instead(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": False}},
            ),
            _policy(modes=["application-rollback", "database-reverse-migration", "manual-halt"]),
            _known_good(),
        )
        self.assertEqual("manual_halt_required", decision["outcome"])
        self.assertEqual(ACTION_MANUAL_HALT, decision["action"])

    def test_reversible_flag_without_metadata_is_not_permitted(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_reversible=True,
            ),
            _policy(),
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        self.assertEqual("forward_recovery_required", decision["outcome"])
        self.assertEqual(ACTION_FORWARD_RECOVERY, decision["action"])

    def test_migration_path_not_in_release_set_is_not_permitted(self):
        forged_path = "supabase/migrations/999999_evil.sql"
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=forged_path,
                migration_metadata={forged_path: {"reversible": True}},
            ),
            _policy(),
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        self.assertEqual("forward_recovery_required", decision["outcome"])
        self.assertEqual(ACTION_FORWARD_RECOVERY, decision["action"])
        self.assertEqual("migration_not_in_release_set", decision["reason"])

    def test_blind_rollback_prohibited_gate(self):
        # A policy that does not prohibit blind rollback is itself unsafe:
        # database reversal stays disallowed even when the request asserts
        # reversibility, so a blind rollback can never be permitted.
        policy = _policy()
        policy["database_reversal"]["blind_rollback_prohibited"] = False
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": True}},
            ),
            policy,
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        self.assertIn(
            decision["outcome"],
            ("forward_recovery_required", "manual_halt_required"),
        )

    def test_blind_reverse_without_reversible_metadata_is_prohibited(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": False}},
            ),
            _policy(),
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        self.assertIn(
            decision["outcome"],
            ("forward_recovery_required", "manual_halt_required"),
        )


class ExecuteRecoveryTests(unittest.TestCase):
    def _report(self, decision: dict, port=None, executor=None):
        port = port or RecordingDeploymentPort()
        executor = executor or RecordingMigrationExecutor()
        return port, executor, execute_recovery(decision, port, executor)

    def test_application_rollback_executes_the_known_good_target(self):
        decision = plan_recovery(_failed(), _policy(), _known_good())
        port, executor, report = self._report(decision)
        self.assertEqual(1, len(port.calls))
        self.assertEqual(KNOWN_GOOD_DIGEST, port.calls[0]["artifact_digest"])
        self.assertEqual(KNOWN_GOOD_ID, port.calls[0]["release_id"])
        self.assertEqual([], executor.forward)
        self.assertEqual([], executor.reverse)
        self.assertTrue(report["deployment_result"]["attempted"])
        self.assertEqual("passed", report["verification_result"])

    def test_new_artifact_digest_is_not_rolled_back(self):
        decision = plan_recovery(
            _failed(action=ACTION_APPLICATION_ROLLBACK, target_artifact_digest=NEW_DIGEST),
            _policy(),
            _known_good(),
        )
        port, executor, report = self._report(decision)
        self.assertEqual([], port.calls)
        self.assertEqual([], executor.forward)
        self.assertEqual([], executor.reverse)
        self.assertEqual("not_run", report["verification_result"])

    def test_non_reversible_migration_executes_no_reverse_sql(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": False}},
            ),
            _policy(),
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        port, executor, report = self._report(decision)
        self.assertEqual([], executor.reverse)
        self.assertEqual([], executor.forward)
        self.assertEqual("not_run", report["verification_result"])

    def test_permitted_forward_recovery_executes_forward(self):
        decision = plan_recovery(
            _failed(action=ACTION_FORWARD_RECOVERY, migration_path=MIGRATION),
            _policy(),
            _known_good(),
        )
        self.assertTrue(decision["permitted"])
        port, executor, report = self._report(decision)
        self.assertEqual([], executor.reverse)
        self.assertEqual([], port.calls)
        self.assertEqual(1, len(executor.forward))
        self.assertEqual("forward", report["migration_result"]["direction"])
        self.assertEqual("passed", report["verification_result"])

    def test_unpermitted_forward_recovery_executes_nothing(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": False}},
            ),
            _policy(),
            _known_good(),
        )
        self.assertFalse(decision["permitted"])
        self.assertEqual(ACTION_FORWARD_RECOVERY, decision["action"])
        port, executor, report = self._report(decision)
        self.assertEqual([], executor.forward)
        self.assertEqual([], executor.reverse)
        self.assertEqual("not_run", report["verification_result"])

    def test_reversible_migration_executes_reverse(self):
        decision = plan_recovery(
            _failed(
                action=ACTION_DATABASE_REVERSE,
                migration_path=MIGRATION,
                migration_metadata={MIGRATION: {"reversible": True}},
            ),
            _policy(),
            _known_good(),
        )
        port, executor, report = self._report(decision)
        self.assertEqual(1, len(executor.reverse))
        self.assertEqual([], executor.forward)
        self.assertEqual([], port.calls)
        self.assertEqual("reverse", report["migration_result"]["direction"])
        self.assertEqual("passed", report["verification_result"])

    def test_manual_halt_executes_nothing(self):
        decision = plan_recovery(
            _failed(action=ACTION_MANUAL_HALT), _policy(), _known_good()
        )
        port, executor, report = self._report(decision)
        self.assertEqual([], port.calls)
        self.assertEqual([], executor.forward)
        self.assertEqual([], executor.reverse)
        self.assertFalse(report["deployment_result"]["attempted"])
        self.assertFalse(report["migration_result"]["attempted"])
        self.assertEqual("not_run", report["verification_result"])

    def test_report_is_immutable_and_self_verifying(self):
        decision = plan_recovery(_failed(), _policy(), _known_good())
        _, _, report = self._report(decision)
        self.assertIsInstance(report, dict)
        self.assertEqual(report["report_identity"], recovery_report_identity(report))
        with self.assertRaises(TypeError):
            report["action"] = "tampered"
        with self.assertRaises(TypeError):
            report.update({"action": "tampered"})
        with self.assertRaises(TypeError):
            report["decision"]["action"] = "tampered"
        with self.assertRaises(TypeError):
            report["deployment_result"]["ok"] = False
        with self.assertRaises(TypeError):
            report["migration_result"]["attempted"] = True

    def test_report_is_deterministic(self):
        decision = plan_recovery(_failed(), _policy(), _known_good())
        _, _, first = self._report(decision)
        _, _, second = self._report(decision)
        self.assertEqual(dict(first), dict(second))


class CommittedFixtureTests(unittest.TestCase):
    def test_validate_recovery_is_clean(self):
        self.assertEqual([], validate_recovery(ROOT, CLIENT))

    def test_committed_report_matches_builder_output(self):
        committed = _load(REPORT)
        expected = build_reference_recovery_report(ROOT, CLIENT)
        self.assertEqual(committed, expected)

    def test_committed_report_identity_self_verifies(self):
        committed = _load(REPORT)
        self.assertEqual(
            committed["report_identity"], recovery_report_identity(committed)
        )

    def test_committed_report_is_a_governed_application_rollback(self):
        committed = _load(REPORT)
        decision = committed["decision"]
        self.assertEqual(ACTION_APPLICATION_ROLLBACK, decision["action"])
        self.assertTrue(decision["permitted"])
        self.assertEqual("none", decision["migration_action"])
        self.assertEqual("passed", committed["verification_result"])
        self.assertEqual(
            committed["previous_known_good"]["artifact_digest"],
            decision["target_artifact_digest"],
        )

    def test_committed_previous_known_good_is_the_release_record(self):
        committed = _load(REPORT)
        release_record = _load(
            CLIENT / "production" / "evidence" / "release-record.json"
        )
        self.assertEqual(
            release_record["release_id"],
            committed["previous_known_good"]["release_id"],
        )
        self.assertEqual(
            release_record["artifact_digest"],
            committed["previous_known_good"]["artifact_digest"],
        )

    def test_committed_report_does_not_imply_blind_db_rollback(self):
        committed = _load(REPORT)
        self.assertNotEqual(
            ACTION_DATABASE_REVERSE, committed["decision"]["action"]
        )
        self.assertFalse(committed["migration_result"]["attempted"])
        for entry in committed["request"]["migration_metadata"].values():
            self.assertIs(False, entry["reversible"])


class ValidateRecoveryTests(unittest.TestCase):
    def _validate(self, report: dict) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "recovery-report.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            with mock.patch(
                "tooling.release.recovery.recovery_report_path", return_value=path
            ):
                return validate_recovery(ROOT, CLIENT)

    def test_missing_report_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "recovery-report.json"
            with mock.patch(
                "tooling.release.recovery.recovery_report_path", return_value=path
            ):
                errors = validate_recovery(ROOT, CLIENT)
        self.assertTrue(any("missing recovery report" in e for e in errors), errors)

    def test_tampered_identity_is_rejected(self):
        report = dict(_load(REPORT))
        report["report_identity"] = "sha256:" + "0" * 64
        errors = self._validate(report)
        self.assertTrue(
            any("report_identity does not verify" in e for e in errors), errors
        )

    def test_tampered_failed_release_snapshot_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        report["failed_release"]["release_status"] = "healthy"
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(
            any("release_status must be 'failed'" in e for e in errors), errors
        )

    def test_flipped_verification_result_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        report["verification_result"] = "failed"
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(any("re-derived" in e for e in errors), errors)

    def test_flipped_deployment_result_ok_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        report["deployment_result"]["ok"] = False
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(any("re-derived" in e for e in errors), errors)

    def test_permitted_rollback_without_attempt_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        report["deployment_result"] = {"attempted": False, "ok": False}
        report["verification_result"] = "not_run"
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(any("must be attempted" in e for e in errors), errors)

    def test_altered_deployment_id_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        report["deployment_result"]["deployment_id"] = "evil-deploy"
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(
            any(
                "deployment_result" in e and "re-derived" in e for e in errors
            ),
            errors,
        )

    def test_forged_blind_reverse_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        decision = report["decision"]
        decision["action"] = ACTION_DATABASE_REVERSE
        decision["outcome"] = "permitted"
        decision["permitted"] = True
        decision["migration_action"] = "reverse"
        decision["decision_identity"] = decision_identity(decision)
        report["action"] = decision["action"]
        report["outcome"] = decision["outcome"]
        report["permitted"] = True
        report["migration_action"] = "reverse"
        report["migration_result"] = {"attempted": True, "ok": True, "direction": "reverse"}
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(
            any("governed decision re-derived" in e for e in errors), errors
        )

    def test_decision_mismatch_is_rejected(self):
        report = copy.deepcopy(_load(REPORT))
        report["decision"]["reason"] = "tampered"
        report["decision"]["decision_identity"] = decision_identity(report["decision"])
        report["reason"] = "tampered"
        report["report_identity"] = recovery_report_identity(report)
        errors = self._validate(report)
        self.assertTrue(
            any("governed decision re-derived" in e for e in errors), errors
        )


class PolicyAndOfflineTests(unittest.TestCase):
    def test_committed_policy_loads_all_modes(self):
        policy = load_recovery_policy(CLIENT)
        self.assertEqual(
            {
                "application-rollback",
                "database-reverse-migration",
                "forward-recovery-migration",
                "manual-halt",
            },
            set(policy["modes"]),
        )

    def test_load_recovery_report_reads_committed_fixture(self):
        report = load_recovery_report(CLIENT)
        self.assertEqual(1, report["report_version"])
        self.assertEqual(
            report["report_identity"], recovery_report_identity(report)
        )

    def test_main_validate_returns_zero(self):
        from tooling.release.recovery import main

        self.assertEqual(0, main([]))

    def test_no_provider_imports(self):
        source = (ROOT / "tooling" / "release" / "recovery.py").read_text(
            encoding="utf-8"
        )
        for provider in ("sentry", "cloudflare", "ga4", "supabase"):
            self.assertNotIn(provider, source.lower())


if __name__ == "__main__":
    unittest.main()
