from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from tooling.prototype.approved_experience import validate_approved_experience
from tooling.prototype.validate_visual_qa import unresolved_critical_findings, validate_visual_findings
from tooling.workflow.client_input import blocking_open_questions, validate_client_input
from tooling.workflow.contracts import validate_stage_contracts
from tooling.workflow.manifests import ManifestError, load_manifest, validate_manifest
from tooling.workflow.state import WorkflowStateError, load_state, normalize_state


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


def _validate_execution_manifests(client_dir: Path, state: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    loaded: list[tuple[Path, Any]] = []
    executions_dir = client_dir / "workflow" / "executions"
    if executions_dir.is_dir():
        for path in sorted(executions_dir.glob("*/attempt-*.yaml")):
            relative = path.relative_to(client_dir)
            try:
                manifest = load_manifest(path)
            except ManifestError as exc:
                errors.append(f"{client_dir}: {relative}: {exc}")
                continue
            for error in validate_manifest(manifest.to_dict()):
                errors.append(f"{client_dir}: {relative}: {error}")
            loaded.append((path, manifest))

    stage_state = state.get("stage_state") or {}
    for stage in sorted(stage_state):
        entry = stage_state.get(stage)
        if not isinstance(entry, dict) or entry.get("status") != "complete":
            continue
        manifest = None
        ref = entry.get("artifact_manifest_ref")
        if isinstance(ref, str) and ref:
            candidate = client_dir / ref
            if candidate.exists():
                try:
                    manifest = load_manifest(candidate)
                except ManifestError as exc:
                    errors.append(f"{client_dir}: stage {stage}: {exc}")
                    manifest = None
        if manifest is None:
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
        state = load_state(state_path)
    except Exception as exc:
        return [f"{client_dir}: cannot load workflow-state.yaml: {exc}"]
    errors.extend(_validate_state(state, str(client_dir), client_dir.name))
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
