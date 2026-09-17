from __future__ import annotations

import json
import re
from collections.abc import Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

from tooling.prototype.approved_experience import validate_approved_experience
from tooling.prototype.validate_visual_qa import unresolved_critical_findings, validate_visual_findings
from tooling.workflow.audit import validate_audit_record
from tooling.workflow.client_input import blocking_open_questions, validate_client_input
from tooling.workflow.contracts import (
    StageContractError,
    load_stage_contract,
    validate_stage_contracts,
)
from tooling.workflow.lease import LEASE_KEYS
from tooling.workflow.manifests import (
    ExecutionManifest,
    ManifestError,
    load_manifest,
    validate_manifest,
)
from tooling.workflow.state import (
    STAGE_ATTEMPT_STATUSES,
    STAGES,
    WorkflowStateError,
    load_state,
    normalize_state,
)


REQUIRED_SECTIONS = ["PURPOSE", "READ", "PROCESS", "WRITE", "VALIDATE", "DO NOT", "NEXT"]
WORKFLOW_FILES = [
    "01-client-intake.md",
    "02-resolve-intelligence.md",
    "03-resource-research.md",
    "04-generate-directions.md",
    "05-build-prototype.md",
    "06-visual-qa.md",
    "07-client-review.md",
    "08-productionize.md",
]
TEMPLATE_FILES = [
    "client-profile.yaml",
    "direction.yaml",
    "direction-comparison.yaml",
    "workflow-state.yaml",
    "approved-experience.yaml",
]
RESERVED_PROJECT_DIRS = {"schema", "examples"}

_STATE_SCHEMA_PATH = (
    Path(__file__).resolve().parents[2]
    / "client-projects"
    / "schema"
    / "workflow-state.schema.json"
)
_AUDIT_RELPATH = Path("workflow") / "audit.jsonl"
_ATTEMPT_FILENAME = re.compile(r"^attempt-(\d+)\.yaml$")


def validate_workflow_file(path: Path) -> list[str]:
    if not path.exists():
        return [f"missing workflow: {path}"]
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    for section in REQUIRED_SECTIONS:
        if f"## {section}" not in text:
            errors.append(f"{path}: missing section {section}")
    return errors


def _validate_state(state: dict[str, Any], label: str, client_id: str) -> list[str]:
    try:
        normalize_state(state, client_id=client_id)
    except WorkflowStateError as exc:
        return [f"{label}: {exc}"]
    return []


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _validate_state_schema(raw_state: Any, label: str) -> list[str]:
    try:
        schema = json.loads(_STATE_SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{label}: cannot load workflow-state schema: {exc}"]
    validator = Draft202012Validator(schema)
    errors: list[str] = []
    for error in validator.iter_errors(raw_state):
        location = ".".join(str(part) for part in error.path) or "<root>"
        errors.append(f"{label}: state schema: {location}: {error.message}")
    return sorted(errors)


def _validate_stage_state(client_dir: Path, state: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    stage_state = state.get("stage_state") or {}
    if not isinstance(stage_state, Mapping):
        return [f"{client_dir}: stage_state must be a mapping"]
    for stage in sorted(stage_state):
        if stage not in STAGES:
            errors.append(f"{client_dir}: stage_state has non-canonical stage {stage!r}")
            continue
        entry = stage_state.get(stage)
        if not isinstance(entry, Mapping):
            errors.append(f"{client_dir}: stage_state[{stage!r}] must be a mapping")
            continue
        status = entry.get("status")
        if status is not None and status not in STAGE_ATTEMPT_STATUSES:
            errors.append(f"{client_dir}: stage_state[{stage!r}] invalid status {status!r}")
    return errors


def _validate_active_lease(client_dir: Path, state: dict[str, Any]) -> list[str]:
    lease = state.get("active_lease")
    if lease is None:
        return []
    if not isinstance(lease, Mapping):
        return [f"{client_dir}: active_lease must be a mapping or null"]
    errors: list[str] = []
    missing = [key for key in LEASE_KEYS if key not in lease]
    if missing:
        errors.append(f"{client_dir}: active_lease missing key {missing[0]!r}")
    acquired = _parse_timestamp(lease.get("acquired_at"))
    expires = _parse_timestamp(lease.get("expires_at"))
    if acquired is None:
        errors.append(f"{client_dir}: active_lease acquired_at is not a parseable timestamp")
    if expires is None:
        errors.append(f"{client_dir}: active_lease expires_at is not a parseable timestamp")
    if acquired is not None and expires is not None and expires < acquired:
        errors.append(f"{client_dir}: active_lease expires_at is before acquired_at")
    return errors


def _validate_audit(client_dir: Path) -> list[str]:
    path = client_dir / _AUDIT_RELPATH
    if not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        return [f"{client_dir}: workflow/audit.jsonl: cannot read audit log: {exc}"]
    errors: list[str] = []
    for number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(
                f"{client_dir}: workflow/audit.jsonl line {number}: malformed audit record: {exc}"
            )
            continue
        for error in validate_audit_record(data):
            errors.append(f"{client_dir}: workflow/audit.jsonl line {number}: {error}")
    return errors


def _validate_pointer_ahead(root: Path, client_dir: Path, state: dict[str, Any]) -> list[str]:
    if state.get("status") == "complete":
        return []
    stage = state.get("current_stage")
    if stage == STAGES[0] or stage not in STAGES:
        return []
    try:
        contract = load_stage_contract(root, stage)
    except StageContractError:
        return []
    completed = set(state.get("completed") or [])
    missing = [required for required in contract.requires_stages if required not in completed]
    if not missing:
        return []
    return [
        f"{client_dir}: current stage {stage} prerequisites not completed: " + ", ".join(missing)
    ]


def _manifest_identity_from_ref(ref: str) -> tuple[str | None, int | None]:
    parts = Path(ref).parts
    run_id = parts[-2] if len(parts) >= 2 else None
    attempt = None
    if parts:
        match = _ATTEMPT_FILENAME.match(parts[-1])
        if match:
            attempt = int(match.group(1))
    return run_id, attempt


def _validate_manifest_identity(
    errors: list[str], client_dir: Path, stage: str, ref: str, manifest: Any
) -> None:
    if manifest.stage != stage:
        errors.append(
            f"{client_dir}: stage {stage} references manifest of stage {manifest.stage!r} at {ref}"
        )
    expected_run_id, expected_attempt = _manifest_identity_from_ref(ref)
    if expected_run_id is not None and manifest.run_id != expected_run_id:
        errors.append(
            f"{client_dir}: stage {stage} manifest {ref} has run_id {manifest.run_id!r}, "
            f"expected {expected_run_id!r}"
        )
    if expected_attempt is not None and manifest.attempt != expected_attempt:
        errors.append(
            f"{client_dir}: stage {stage} manifest {ref} has attempt {manifest.attempt!r}, "
            f"expected {expected_attempt!r}"
        )


def _validate_execution_manifests(client_dir: Path, state: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    loaded: list[tuple[Path, Any]] = []
    executions_dir = client_dir / "workflow" / "executions"
    if executions_dir.is_dir():
        for path in sorted(executions_dir.glob("*/attempt-*.yaml")):
            relative = path.relative_to(client_dir)
            try:
                raw = yaml.safe_load(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, yaml.YAMLError) as exc:
                errors.append(f"{client_dir}: {relative}: {path}: cannot load manifest: {exc}")
                continue
            if not isinstance(raw, Mapping):
                errors.append(f"{client_dir}: {relative}: {path}: manifest must be a mapping")
                continue
            for error in validate_manifest(raw):
                errors.append(f"{client_dir}: {relative}: {error}")
            try:
                manifest = ExecutionManifest.from_dict(raw)
            except ManifestError as exc:
                errors.append(f"{client_dir}: {relative}: {path}: {exc}")
                continue
            except (KeyError, TypeError, ValueError) as exc:
                errors.append(f"{client_dir}: {relative}: {path}: invalid manifest: {exc}")
                continue
            loaded.append((path, manifest))

    stage_state = state.get("stage_state") or {}
    for stage in sorted(stage_state):
        entry = stage_state.get(stage)
        if not isinstance(entry, dict):
            continue
        manifest = None
        ref = entry.get("artifact_manifest_ref")
        if isinstance(ref, str) and ref:
            candidate = client_dir / ref
            if candidate.exists():
                try:
                    manifest = load_manifest(candidate)
                except (ManifestError, KeyError, TypeError, ValueError) as exc:
                    errors.append(f"{client_dir}: stage {stage}: {exc}")
                    manifest = None
                else:
                    _validate_manifest_identity(errors, client_dir, stage, ref, manifest)
            else:
                errors.append(
                    f"{client_dir}: stage {stage} references missing execution manifest {ref}"
                )
        if entry.get("status") != "complete":
            continue
        if manifest is None and not (isinstance(ref, str) and ref):
            # Only an entry without a recorded reference may fall back to a
            # matching completed manifest; a broken reference must not be masked.
            for _, candidate in loaded:
                if candidate.stage == stage and candidate.status == "completed":
                    manifest = candidate
                    break
        if manifest is None:
            errors.append(
                f"{client_dir}: stage {stage} marked complete but no completed execution manifest exists"
            )
        elif manifest.status != "completed":
            errors.append(
                f"{client_dir}: stage {stage} execution manifest is {manifest.status}, expected completed"
            )
    return errors


def validate_client(root: Path, client_dir: Path) -> list[str]:
    errors: list[str] = []
    state_path = client_dir / "workflow-state.yaml"
    if not state_path.exists():
        return [f"{client_dir}: missing workflow-state.yaml"]
    try:
        raw_state = yaml.safe_load(state_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"{client_dir}: cannot load workflow-state.yaml: {exc}"]
    try:
        state = load_state(state_path)
    except Exception as exc:
        return [f"{client_dir}: cannot load workflow-state.yaml: {exc}"]
    errors.extend(_validate_state(state, str(client_dir), client_dir.name))
    errors.extend(_validate_state_schema(raw_state, str(client_dir)))
    errors.extend(_validate_stage_state(client_dir, state))
    errors.extend(_validate_active_lease(client_dir, state))
    errors.extend(_validate_audit(client_dir))
    errors.extend(_validate_pointer_ahead(root, client_dir, state))
    completed = set(state.get("completed", []))

    required: dict[str, list[Path]] = {
        "client-intake": [client_dir / "derived" / "client-profile.yaml"],
        "resolve-intelligence": [client_dir / "resolved-intelligence.yaml"],
        "resource-research": [client_dir / "resources" / "selection.yaml"],
        "generate-directions": [
            client_dir / "directions" / "direction-a.yaml",
            client_dir / "directions" / "direction-b.yaml",
            client_dir / "directions" / "comparison.yaml",
        ],
        "build-prototype": [client_dir / "prototype" / "prototype-manifest.yaml"],
        "visual-qa": [
            client_dir / "prototype" / "qa" / "screenshot-manifest.yaml",
            client_dir / "prototype" / "qa" / "visual-findings.yaml",
        ],
        "client-review": [client_dir / "approved-experience.yaml"],
    }
    for stage, paths in required.items():
        if stage in completed:
            for path in paths:
                if not path.exists():
                    errors.append(f"{client_dir}: completed {stage} but missing {path.relative_to(client_dir)}")

    if "client-intake" in completed:
        errors.extend(f"{client_dir}: {error}" for error in validate_client_input(root, client_dir))
        if blocking_open_questions(client_dir):
            errors.append(f"{client_dir}: client-intake blocked by unresolved blocking questions")

    if "visual-qa" in completed:
        findings_path = client_dir / "prototype" / "qa" / "visual-findings.yaml"
        if findings_path.exists():
            findings = _load_yaml(findings_path)
            errors.extend(f"{client_dir}: {error}" for error in validate_visual_findings(findings))
            if unresolved_critical_findings(findings):
                errors.append(f"{client_dir}: visual-qa completed with unresolved critical findings")

    if "client-review" in completed and (client_dir / "approved-experience.yaml").exists():
        errors.extend(f"{client_dir}: {error}" for error in validate_approved_experience(root, client_dir))

    if "productionize" in completed:
        if not (client_dir / "approved-experience.yaml").exists():
            errors.append(f"{client_dir}: productionize requires approved-experience.yaml")
        else:
            errors.extend(f"{client_dir}: {error}" for error in validate_approved_experience(root, client_dir))

    errors.extend(_validate_execution_manifests(client_dir, state))
    return errors


def validate_runtime(root: Path) -> list[str]:
    errors: list[str] = []
    errors.extend(validate_stage_contracts(root))
    for name in WORKFLOW_FILES:
        errors.extend(validate_workflow_file(root / "workflows" / name))
    for name in TEMPLATE_FILES:
        path = root / "templates" / name
        if not path.exists():
            errors.append(f"missing template: {path}")
        else:
            try:
                yaml.safe_load(path.read_text(encoding="utf-8"))
            except yaml.YAMLError as exc:
                errors.append(f"invalid yaml template {path}: {exc}")

    projects = root / "client-projects"
    if projects.exists():
        for client_dir in sorted(projects.iterdir()):
            if (
                not client_dir.is_dir()
                or client_dir.name in RESERVED_PROJECT_DIRS
                or client_dir.name.startswith(".")
            ):
                continue
            errors.extend(validate_client(root, client_dir))
    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    errors = validate_runtime(root)
    if errors:
        print("Workflow runtime validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print("Workflow runtime validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
