from __future__ import annotations

import copy
import unittest
from datetime import datetime, timedelta, timezone

from tooling.workflow.lease import (
    LEASE_STATUSES,
    WorkflowLease,
    WorkflowLeaseConflict,
    WorkflowLeaseError,
    WorkflowLeaseExpired,
    WorkflowLeaseOwnershipError,
    acquire_lease,
    is_expired,
    load_lease,
    reconcile_expired_lease,
    release_lease,
    renew_lease,
)
from tooling.workflow.state import initial_state


NOW = datetime(2026, 9, 17, 12, 0, tzinfo=timezone.utc)
OWNER = "opencode:session-a"
RUN_ID = "wf-acme-20260917T120000Z-abc12345"
TTL = 1800


def _base_state() -> dict:
    state = initial_state("acme")
    state["current_stage"] = "build-prototype"
    state["status"] = "in_progress"
    state["run_id"] = RUN_ID
    state["completed"] = ["client-intake", "resolve-intelligence"]
    state["pending"] = [
        "resource-research",
        "generate-directions",
        "build-prototype",
        "visual-qa",
        "client-review",
        "productionize",
    ]
    return state


def _impostor(lease: WorkflowLease, *, owner: str | None = None, lease_id: str | None = None) -> WorkflowLease:
    return WorkflowLease(
        lease_id=lease_id if lease_id is not None else lease.lease_id,
        owner=owner if owner is not None else lease.owner,
        run_id=lease.run_id,
        acquired_at=lease.acquired_at,
        expires_at=lease.expires_at,
    )


class AcquireTests(unittest.TestCase):
    def test_fresh_acquire_sets_all_lease_fields(self):
        state, lease = acquire_lease(
            _base_state(), owner=OWNER, run_id=RUN_ID, now=NOW, ttl_seconds=TTL
        )
        self.assertEqual(OWNER, lease.owner)
        self.assertEqual(RUN_ID, lease.run_id)
        self.assertEqual("2026-09-17T12:00:00Z", lease.acquired_at)
        self.assertEqual("2026-09-17T12:30:00Z", lease.expires_at)
        self.assertTrue(lease.lease_id.startswith("lease-"))
        self.assertEqual(lease.to_dict(), state["active_lease"])

    def test_fresh_acquire_does_not_mutate_input_state(self):
        state = _base_state()
        before = copy.deepcopy(state)
        acquire_lease(state, owner=OWNER, run_id=RUN_ID, now=NOW)
        self.assertEqual(before, state)
        self.assertIsNone(state["active_lease"])

    def test_same_owner_and_run_reacquire_is_idempotent(self):
        state, first = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        again_state, again = acquire_lease(
            state, owner=OWNER, run_id=RUN_ID, now=NOW + timedelta(minutes=5)
        )
        self.assertEqual(first, again)
        self.assertEqual(first.lease_id, again.lease_id)
        self.assertEqual(first.expires_at, again.expires_at)
        self.assertEqual(state, again_state)

    def test_both_none_run_ids_reacquire_idempotently(self):
        state, first = acquire_lease(_base_state(), owner=OWNER, run_id=None, now=NOW)
        again_state, again = acquire_lease(state, owner=OWNER, run_id=None, now=NOW)
        self.assertEqual(first, again)
        self.assertEqual(state, again_state)

    def test_different_owner_conflicts(self):
        state, _ = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseConflict):
            acquire_lease(state, owner="opencode:session-b", run_id=RUN_ID, now=NOW)

    def test_different_run_conflicts(self):
        state, _ = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseConflict):
            acquire_lease(
                state,
                owner=OWNER,
                run_id="wf-acme-20260917T120000Z-other",
                now=NOW,
            )

    def test_expired_lease_cannot_be_reacquired_without_reconcile(self):
        state, _ = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseExpired):
            acquire_lease(
                state, owner=OWNER, run_id=RUN_ID, now=NOW + timedelta(minutes=31)
            )

    def test_lease_id_is_deterministic_for_identical_inputs(self):
        _, first = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        _, second = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        self.assertEqual(first.lease_id, second.lease_id)

    def test_blank_owner_is_rejected(self):
        with self.assertRaises(WorkflowLeaseError):
            acquire_lease(_base_state(), owner="   ", run_id=RUN_ID, now=NOW)

    def test_naive_now_is_treated_as_utc(self):
        _, lease = acquire_lease(
            _base_state(), owner=OWNER, run_id=RUN_ID, now=datetime(2026, 9, 17, 12, 0)
        )
        self.assertEqual("2026-09-17T12:00:00Z", lease.acquired_at)
        self.assertEqual("2026-09-17T12:30:00Z", lease.expires_at)


class ExpiryTests(unittest.TestCase):
    def test_is_expired_uses_inclusive_boundary(self):
        _, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        self.assertFalse(is_expired(lease, now=NOW + timedelta(seconds=1799)))
        self.assertTrue(is_expired(lease, now=NOW + timedelta(seconds=1800)))
        self.assertTrue(is_expired(lease, now=NOW + timedelta(seconds=1801)))

    def test_timestamps_end_with_z(self):
        _, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        self.assertTrue(lease.acquired_at.endswith("Z"))
        self.assertTrue(lease.expires_at.endswith("Z"))


class RenewTests(unittest.TestCase):
    def test_renew_extends_expiry_and_keeps_identity(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        new_state, renewed = renew_lease(
            state, lease, now=NOW + timedelta(minutes=10), ttl_seconds=TTL
        )
        self.assertEqual("2026-09-17T12:40:00Z", renewed.expires_at)
        self.assertEqual(lease.lease_id, renewed.lease_id)
        self.assertEqual(lease.acquired_at, renewed.acquired_at)
        self.assertEqual(renewed.to_dict(), new_state["active_lease"])
        self.assertEqual(lease.expires_at, state["active_lease"]["expires_at"])

    def test_renew_with_wrong_owner_raises(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseOwnershipError):
            renew_lease(state, _impostor(lease, owner="opencode:session-b"), now=NOW)

    def test_renew_with_wrong_id_raises(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseOwnershipError):
            renew_lease(state, _impostor(lease, lease_id="lease-000000000000"), now=NOW)

    def test_renew_expired_lease_raises(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseExpired):
            renew_lease(state, lease, now=NOW + timedelta(minutes=31))

    def test_renew_without_held_lease_raises(self):
        _, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseOwnershipError):
            renew_lease(_base_state(), lease, now=NOW)


class ReleaseTests(unittest.TestCase):
    def test_release_clears_lease(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        released = release_lease(state, lease)
        self.assertIsNone(released["active_lease"])
        self.assertEqual(lease.to_dict(), state["active_lease"])

    def test_release_requires_matching_owner_and_id(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseOwnershipError):
            release_lease(state, _impostor(lease, owner="opencode:session-b"))
        with self.assertRaises(WorkflowLeaseOwnershipError):
            release_lease(state, _impostor(lease, lease_id="lease-000000000000"))

    def test_release_without_lease_raises(self):
        _, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        with self.assertRaises(WorkflowLeaseOwnershipError):
            release_lease(_base_state(), lease)


class ReconcileTests(unittest.TestCase):
    def test_reconcile_absent_lease_returns_none_copy(self):
        state = _base_state()
        new_state, lease = reconcile_expired_lease(state, now=NOW)
        self.assertIsNone(lease)
        self.assertEqual(state, new_state)
        self.assertIsNot(state, new_state)

    def test_reconcile_live_lease_is_noop(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        new_state, returned = reconcile_expired_lease(
            state, now=NOW + timedelta(minutes=5)
        )
        self.assertEqual(lease, returned)
        self.assertEqual(state, new_state)

    def test_reconcile_expired_lease_returns_and_clears(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        new_state, returned = reconcile_expired_lease(
            state, now=NOW + timedelta(minutes=31)
        )
        self.assertEqual(lease, returned)
        self.assertIsNone(new_state["active_lease"])
        self.assertEqual(lease.to_dict(), state["active_lease"])


class LoadTests(unittest.TestCase):
    def test_load_lease_absent_is_none(self):
        self.assertIsNone(load_lease(_base_state()))

    def test_load_lease_round_trips(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        self.assertEqual(lease, load_lease(state))

    def test_malformed_active_lease_raises(self):
        malformed = [
            "not-a-mapping",
            {"owner": OWNER},
            {
                "lease_id": "",
                "owner": OWNER,
                "run_id": None,
                "acquired_at": NOW.isoformat(),
                "expires_at": NOW.isoformat(),
            },
        ]
        for value in malformed:
            state = _base_state()
            state["active_lease"] = value
            with self.assertRaises(WorkflowLeaseError):
                load_lease(state)

    def test_lease_statuses_constant(self):
        self.assertEqual(("active", "expired"), LEASE_STATUSES)


class NonMutationTests(unittest.TestCase):
    def _assert_workflow_untouched(self, original: dict, updated: dict) -> None:
        for key in ("current_stage", "completed", "pending", "status", "run_id"):
            self.assertEqual(original[key], updated[key])

    def test_acquire_preserves_workflow_fields(self):
        state = _base_state()
        original = copy.deepcopy(state)
        new_state, _ = acquire_lease(state, owner=OWNER, run_id=RUN_ID, now=NOW)
        self._assert_workflow_untouched(original, new_state)

    def test_renew_preserves_workflow_fields(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        original = copy.deepcopy(state)
        new_state, _ = renew_lease(state, lease, now=NOW + timedelta(minutes=5))
        self._assert_workflow_untouched(original, new_state)

    def test_release_preserves_workflow_fields(self):
        state, lease = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        original = copy.deepcopy(state)
        new_state = release_lease(state, lease)
        self._assert_workflow_untouched(original, new_state)

    def test_reconcile_preserves_workflow_fields(self):
        state, _ = acquire_lease(_base_state(), owner=OWNER, run_id=RUN_ID, now=NOW)
        original = copy.deepcopy(state)
        new_state, _ = reconcile_expired_lease(state, now=NOW + timedelta(minutes=31))
        self._assert_workflow_untouched(original, new_state)


if __name__ == "__main__":
    unittest.main()
