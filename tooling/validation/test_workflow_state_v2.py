from __future__ import annotations

import copy
import json
import tempfile
import unittest
from datetime import date
from pathlib import Path

import yaml

from tooling.workflow.state import (
    STAGE_ATTEMPT_STATUSES,
    STAGES,
    STATUSES,
    WORKFLOW_STATUSES,
    WorkflowStateError,
    initial_state,
    load_state,
    normalize_state,
    save_state,
    save_state_atomic,
)


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "workflow-state.schema.json"

CANONICAL_KEYS = [
    "version",
    "client_id",
    "workflow",
    "current_stage",
    "status",
    "run_id",
    "completed",
    "skipped",
    "pending",
    "blocked",
    "stage_state",
    "active_lease",
    "last_transition",
    "last_updated",
]

V1_STATE = {
    "version": 1,
    "client_id": "demo",
    "current_stage": "visual-qa",
    "status": "in_progress",
    "completed": ["client-intake", "resolve-intelligence"],
    "skipped": [{"stage": "resource-research", "reason": "not-required"}],
    "pending": [],
    "blocked": [],
    "last_updated": "2026-09-17",
}

V2_STATE = {
    "version": 2,
    "client_id": "demo",
    "workflow": "standard-agency",
    "current_stage": "visual-qa",
    "status": "in_progress",
    "run_id": "wf-demo-20260917T000000Z-abcd",
    "completed": ["client-intake", "resolve-intelligence"],
    "skipped": [{"stage": "resource-research", "reason": "not-required"}],
    "pending": ["generate-directions"],
    "blocked": [],
    "stage_state": {"visual-qa": {"attempt": 1, "status": "in_progress"}},
    "active_lease": None,
    "last_transition": None,
    "last_updated": "2026-09-17",
}


def _schema_validator() -> "object":
    try:
        from jsonschema import Draft202012Validator
    except ImportError:  # pragma: no cover - jsonschema is an expected dependency
        raise unittest.SkipTest("jsonschema is not available")
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


class NormalizeStateTests(unittest.TestCase):
    def test_v1_state_normalizes_to_v2_without_losing_completed_and_skipped(self):
        normalized = normalize_state(V1_STATE)
        self.assertEqual(2, normalized["version"])
        self.assertEqual("visual-qa", normalized["current_stage"])
        self.assertEqual(V1_STATE["completed"], normalized["completed"])
        self.assertEqual(V1_STATE["skipped"], normalized["skipped"])
        self.assertEqual("standard-agency", normalized["workflow"])
        self.assertIsNone(normalized["run_id"])
        self.assertEqual({}, normalized["stage_state"])
        self.assertIsNone(normalized["active_lease"])
        self.assertIsNone(normalized["last_transition"])
        self.assertEqual("2026-09-17", normalized["last_updated"])

    def test_v1_state_without_pending_derives_pending_from_stages(self):
        state = {key: value for key, value in V1_STATE.items() if key != "pending"}
        normalized = normalize_state(state)
        covered = {"client-intake", "resolve-intelligence", "resource-research"}
        self.assertEqual([stage for stage in STAGES if stage not in covered], normalized["pending"])

    def test_v1_provided_pending_is_preserved_verbatim(self):
        state = dict(V1_STATE)
        state["pending"] = ["generate-directions", "generate-directions"]
        self.assertEqual(["generate-directions", "generate-directions"], normalize_state(state)["pending"])

    def test_v2_state_round_trips_unchanged(self):
        self.assertEqual(V2_STATE, normalize_state(V2_STATE))

    def test_initial_state_is_already_canonical_v2(self):
        state = initial_state("demo")
        self.assertEqual(CANONICAL_KEYS, list(state.keys()))
        self.assertEqual(2, state["version"])
        self.assertEqual("standard-agency", state["workflow"])
        self.assertIsNone(state["run_id"])
        self.assertEqual({}, state["stage_state"])
        self.assertEqual(state, normalize_state(state))

    def test_normalize_state_does_not_mutate_its_input(self):
        for source in (V1_STATE, V2_STATE):
            original = copy.deepcopy(source)
            normalize_state(source)
            self.assertEqual(original, source)


class NormalizeStateValidationTests(unittest.TestCase):
    def test_non_mapping_is_rejected(self):
        for value in ([], "state", 3, None):
            with self.assertRaises(WorkflowStateError):
                normalize_state(value)  # type: ignore[arg-type]

    def test_unsupported_version_is_rejected(self):
        for version in (0, 3, "2", None):
            with self.assertRaises(WorkflowStateError):
                normalize_state({**V2_STATE, "version": version})

    def test_missing_version_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({"client_id": "demo", "current_stage": "client-intake", "status": "not_started"})

    def test_invalid_current_stage_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "current_stage": "bogus"})

    def test_invalid_status_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "status": "bogus"})

    def test_invalid_completed_entry_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "completed": ["bogus"]})
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "completed": "client-intake"})

    def test_invalid_skipped_entry_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "skipped": [{"stage": "bogus", "reason": "x"}]})
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "skipped": [{"stage": "resource-research"}]})

    def test_invalid_pending_entry_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "pending": ["bogus"]})

    def test_invalid_blocked_entry_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "blocked": ["bogus"]})

    def test_invalid_stage_state_key_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "stage_state": {"bogus": {}}})

    def test_client_id_mismatch_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state(V2_STATE, client_id="other")

    def test_client_id_match_is_accepted(self):
        self.assertEqual(V2_STATE, normalize_state(V2_STATE, client_id="demo"))


class PersistenceTests(unittest.TestCase):
    def test_save_state_atomic_creates_parents_and_round_trips(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "nested" / "client" / "workflow-state.yaml"
            save_state_atomic(path, V1_STATE)
            self.assertTrue(path.exists())
            raw = yaml.safe_load(path.read_text(encoding="utf-8"))
            self.assertEqual(2, raw["version"])
            self.assertEqual(date.today().isoformat(), raw["last_updated"])
            self.assertEqual(raw, load_state(path))
            self.assertEqual([], list(path.parent.glob("*.tmp")))

    def test_save_state_atomic_leaves_no_temp_file_on_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "workflow-state.yaml"
            with self.assertRaises(WorkflowStateError):
                save_state_atomic(path, {**V2_STATE, "current_stage": "bogus"})
            self.assertFalse(path.exists())
            self.assertEqual([], list(Path(tmp).glob("*.tmp")))

    def test_save_state_delegates_and_writes_canonical_v2(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "workflow-state.yaml"
            save_state(path, V1_STATE)
            self.assertEqual(2, yaml.safe_load(path.read_text(encoding="utf-8"))["version"])

    def test_load_state_rejects_non_mapping(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "workflow-state.yaml"
            path.write_text("", encoding="utf-8")
            with self.assertRaises(WorkflowStateError):
                load_state(path)


class SchemaTests(unittest.TestCase):
    def test_schema_accepts_canonical_v2_state(self):
        validator = _schema_validator()
        self.assertEqual([], list(validator.iter_errors(normalize_state(V2_STATE))))

    def test_schema_rejects_unknown_top_level_key(self):
        validator = _schema_validator()
        state = normalize_state(V2_STATE)
        state["unexpected"] = True
        self.assertTrue(list(validator.iter_errors(state)))

    def test_schema_rejects_invalid_stage_name(self):
        validator = _schema_validator()
        state = normalize_state(V2_STATE)
        state["completed"] = ["bogus"]
        self.assertTrue(list(validator.iter_errors(state)))

    def test_schema_rejects_unknown_stage_state_key(self):
        validator = _schema_validator()
        state = normalize_state(V2_STATE)
        state["stage_state"] = {"bogus": {}}
        self.assertTrue(list(validator.iter_errors(state)))


class Cycle1ReviewFixTests(unittest.TestCase):
    """Regression tests for the Cycle 1 independent review findings."""

    def test_yaml_date_last_updated_is_coerced_to_iso_string(self):
        import datetime

        state = normalize_state({**V2_STATE, "last_updated": datetime.date(2026, 9, 17)})
        self.assertEqual("2026-09-17", state["last_updated"])
        self.assertIsInstance(state["last_updated"], str)

    def test_shipped_template_is_schema_valid(self):
        validator = _schema_validator()
        root = Path(__file__).resolve().parents[2]
        template = yaml.safe_load(
            (root / "templates" / "workflow-state.yaml").read_text(encoding="utf-8")
        )
        self.assertEqual([], list(validator.iter_errors(normalize_state(template))))

    def test_invalid_stage_attempt_status_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state(
                {
                    **V2_STATE,
                    "stage_state": {"visual-qa": {"status": "garbage"}},
                }
            )

    def test_schema_rejects_invalid_stage_attempt_status(self):
        validator = _schema_validator()
        state = normalize_state(V2_STATE)
        state["stage_state"] = {"visual-qa": {"status": "garbage"}}
        self.assertTrue(list(validator.iter_errors(state)))

    def test_non_string_last_updated_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({**V2_STATE, "last_updated": ["2026-09-17"]})


class ConstantsTests(unittest.TestCase):
    def test_exported_status_constants(self):
        self.assertEqual(STATUSES, WORKFLOW_STATUSES)
        self.assertEqual(
            {"not_started", "in_progress", "blocked", "failed", "complete"},
            STAGE_ATTEMPT_STATUSES,
        )
        self.assertEqual(
            [
                "client-intake",
                "resolve-intelligence",
                "resource-research",
                "generate-directions",
                "build-prototype",
                "visual-qa",
                "client-review",
                "productionize",
                "release",
            ],
            STAGES,
        )


if __name__ == "__main__":
    unittest.main()
