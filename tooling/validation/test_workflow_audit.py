from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from tooling.workflow.audit import (
    AUDIT_KINDS,
    AuditRecord,
    append_audit_record,
    load_audit_records,
    make_deviation,
    make_override,
    make_recovery_record,
    make_ruling,
    validate_audit_record,
)


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "workflow-audit-record.schema.json"

AT = "2026-09-17T12:00:00Z"
ACTOR = "human:reviewer@example.com"
RUN_ID = "wf-acme-20260917T120000Z-abc12345"


def _ruling(**overrides: object) -> AuditRecord:
    kwargs: dict[str, object] = {
        "actor": ACTOR,
        "at": AT,
        "summary": "resolve ambiguity",
        "reason": "spec is silent",
        "decision": "use option A",
    }
    kwargs.update(overrides)
    return make_ruling(**kwargs)  # type: ignore[arg-type]


def _schema_validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    return Draft202012Validator(schema)


class FactoryTests(unittest.TestCase):
    def test_ruling_kind_and_details(self):
        record = make_ruling(
            actor=ACTOR,
            at=AT,
            summary="s",
            reason="r",
            decision="A",
            cost_if_wrong="rework",
            stage="visual-qa",
            run_id=RUN_ID,
        )
        self.assertEqual("ruling", record.kind)
        self.assertEqual("A", record.details["decision"])
        self.assertEqual("rework", record.details["cost_if_wrong"])
        self.assertEqual("visual-qa", record.stage)
        self.assertEqual(RUN_ID, record.run_id)
        self.assertEqual(AT, record.at)

    def test_ruling_omits_absent_cost(self):
        record = make_ruling(actor=ACTOR, at=AT, summary="s", reason="r", decision="A")
        self.assertNotIn("cost_if_wrong", record.details)
        self.assertIsNone(record.stage)
        self.assertIsNone(record.run_id)

    def test_deviation_only_includes_provided_fields(self):
        record = make_deviation(
            actor=ACTOR, at=AT, summary="s", reason="r", expected="gpt-5", actual="gpt-4o"
        )
        self.assertEqual("deviation", record.kind)
        self.assertEqual({"expected": "gpt-5", "actual": "gpt-4o"}, record.details)

    def test_deviation_includes_model_and_tool_metadata(self):
        record = make_deviation(
            actor=ACTOR,
            at=AT,
            summary="s",
            reason="r",
            requested_model="m1",
            actual_model="m2",
            requested_tool="t1",
            actual_tool="t2",
        )
        self.assertEqual(
            {
                "requested_model": "m1",
                "actual_model": "m2",
                "requested_tool": "t1",
                "actual_tool": "t2",
            },
            record.details,
        )

    def test_override_records_affected_gate_and_state(self):
        record = make_override(
            actor=ACTOR,
            at=AT,
            summary="s",
            reason="r",
            affected_gate="visual-qa",
            previous_state="blocked",
            requested_state="complete",
            evidence="acknowledged risk",
        )
        self.assertEqual("override", record.kind)
        self.assertEqual("visual-qa", record.details["affected_gate"])
        self.assertEqual("blocked", record.details["previous_state"])
        self.assertEqual("complete", record.details["requested_state"])
        self.assertEqual("acknowledged risk", record.details["evidence"])

    def test_recovery_record(self):
        record = make_recovery_record(
            actor=ACTOR,
            at=AT,
            summary="s",
            reason="r",
            previous_state="expired",
            requested_state="released",
        )
        self.assertEqual("recovery", record.kind)
        self.assertEqual(
            {"previous_state": "expired", "requested_state": "released"}, record.details
        )

    def test_recovery_without_details_is_allowed(self):
        record = make_recovery_record(actor=ACTOR, at=AT, summary="s", reason="r")
        self.assertEqual({}, record.details)


class FactoryValidationTests(unittest.TestCase):
    def test_blank_actor_summary_reason_rejected(self):
        for field in ("actor", "summary", "reason"):
            kwargs: dict[str, object] = {
                "actor": ACTOR,
                "at": AT,
                "summary": "s",
                "reason": "r",
                "decision": "A",
            }
            kwargs[field] = "   "
            with self.assertRaises(ValueError):
                make_ruling(**kwargs)  # type: ignore[arg-type]

    def test_audit_kinds_constant(self):
        self.assertEqual(("ruling", "deviation", "override", "recovery"), AUDIT_KINDS)

    def test_opencode_actor_cannot_override(self):
        with self.assertRaises(ValueError):
            make_override(
                actor="opencode:session-a",
                at=AT,
                summary="s",
                reason="r",
                affected_gate="visual-qa",
            )

    def test_override_without_affected_gate_rejected(self):
        with self.assertRaises(ValueError):
            make_override(
                actor=ACTOR, at=AT, summary="s", reason="r", affected_gate="   "
            )


class IdentityTests(unittest.TestCase):
    def test_identical_content_produces_identical_id(self):
        first = _ruling()
        second = _ruling()
        self.assertEqual(first.id, second.id)
        self.assertTrue(first.id.startswith("ruling-"))

    def test_different_content_produces_different_id(self):
        self.assertNotEqual(_ruling(summary="one").id, _ruling(summary="two").id)

    def test_to_dict_round_trips(self):
        record = _ruling(stage="visual-qa", run_id=RUN_ID)
        self.assertEqual(record, AuditRecord.from_dict(record.to_dict()))


class AppendTests(unittest.TestCase):
    def test_append_creates_parents_and_never_rewrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "workflow" / "audit.jsonl"
            append_audit_record(path, _ruling(summary="first"))
            first_line = path.read_bytes()
            append_audit_record(path, _ruling(summary="second"))
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(2, len(lines))
            self.assertEqual(first_line, (lines[0] + "\n").encode("utf-8"))

    def test_append_writes_compact_sorted_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "audit.jsonl"
            record = _ruling()
            append_audit_record(path, record)
            line = path.read_text(encoding="utf-8").rstrip("\n")
            self.assertEqual(
                json.dumps(record.to_dict(), sort_keys=True, separators=(",", ":")), line
            )

    def test_load_round_trips_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "audit.jsonl"
            records = [_ruling(summary="one"), _ruling(summary="two")]
            for record in records:
                append_audit_record(path, record)
            self.assertEqual(records, load_audit_records(path))

    def test_load_missing_file_returns_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual([], load_audit_records(Path(tmp) / "missing.jsonl"))

    def test_load_malformed_line_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "audit.jsonl"
            path.write_text("not-json\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_audit_records(path)


class ValidateRecordTests(unittest.TestCase):
    def _valid_records(self) -> list[dict]:
        return [
            _ruling().to_dict(),
            make_deviation(
                actor=ACTOR, at=AT, summary="s", reason="r", expected="a", actual="b"
            ).to_dict(),
            make_override(
                actor=ACTOR, at=AT, summary="s", reason="r", affected_gate="visual-qa"
            ).to_dict(),
            make_recovery_record(actor=ACTOR, at=AT, summary="s", reason="r").to_dict(),
        ]

    def test_valid_records_accepted(self):
        for data in self._valid_records():
            self.assertEqual([], validate_audit_record(data))

    def test_missing_required_field_rejected(self):
        data = _ruling().to_dict()
        del data["reason"]
        self.assertTrue(validate_audit_record(data))

    def test_bad_kind_rejected(self):
        data = _ruling().to_dict()
        data["kind"] = "bogus"
        self.assertTrue(validate_audit_record(data))

    def test_override_without_affected_gate_rejected(self):
        data = make_override(
            actor=ACTOR, at=AT, summary="s", reason="r", affected_gate="visual-qa"
        ).to_dict()
        del data["details"]["affected_gate"]
        self.assertTrue(validate_audit_record(data))

    def test_unknown_key_rejected(self):
        data = _ruling().to_dict()
        data["extra"] = True
        self.assertTrue(validate_audit_record(data))


class SchemaAgreementTests(unittest.TestCase):
    def _cases(self) -> list[dict]:
        valid = _ruling().to_dict()
        missing = _ruling().to_dict()
        del missing["reason"]
        bad_kind = _ruling().to_dict()
        bad_kind["kind"] = "bogus"
        override = make_override(
            actor=ACTOR, at=AT, summary="s", reason="r", affected_gate="visual-qa"
        ).to_dict()
        override_no_gate = json.loads(json.dumps(override))
        del override_no_gate["details"]["affected_gate"]
        unknown = _ruling().to_dict()
        unknown["extra"] = True
        return [valid, missing, bad_kind, override, override_no_gate, unknown]

    def test_schema_agrees_with_validate_audit_record(self):
        validator = _schema_validator()
        for data in self._cases():
            schema_ok = not list(validator.iter_errors(data))
            code_ok = validate_audit_record(data) == []
            self.assertEqual(schema_ok, code_ok, msg=f"disagreement on {data!r}")


if __name__ == "__main__":
    unittest.main()
