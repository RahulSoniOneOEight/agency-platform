from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from tooling.prototype.approved_experience import validate_approved_experience
from tooling.prototype.validate_visual_qa import unresolved_critical_findings, validate_visual_findings
from tooling.workflow.client_paths import ClientPaths
from tooling.workflow.state import STAGES, STATUSES, load_state


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
    "client-input.yaml",
    "client-profile.yaml",
    "resolved-presets.yaml",
    "intelligence-map.yaml",
    "capability-map.yaml",
    "gaps.yaml",
    "resource-requirements.yaml",
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


def _validate_state(state: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    if state.get("version") != 1:
        errors.append(f"{label}: workflow-state version must be 1")
    if state.get("current_stage") not in STAGES:
        errors.append(f"{label}: invalid current_stage {state.get('current_stage')!r}")
    if state.get("status") not in STATUSES:
        errors.append(f"{label}: invalid status {state.get('status')!r}")
    completed = state.get("completed", [])
    if not isinstance(completed, list) or any(stage not in STAGES for stage in completed):
        errors.append(f"{label}: completed contains invalid stages")
    skipped = state.get("skipped", [])
    if not isinstance(skipped, list):
        errors.append(f"{label}: skipped must be a list")
    else:
        for item in skipped:
            if not isinstance(item, dict) or item.get("stage") not in STAGES or not item.get("reason"):
                errors.append(f"{label}: every skipped stage requires a valid stage and reason")
    return errors


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def validate_client(root: Path, client_dir: Path) -> list[str]:
    errors: list[str] = []
    paths = ClientPaths.for_client(client_dir)
    state_path = paths.workflow_state
    if not state_path.exists():
        return [f"{client_dir}: missing workflow-state.yaml"]
    try:
        state = load_state(state_path)
    except Exception as exc:
        return [f"{client_dir}: cannot load workflow-state.yaml: {exc}"]
    errors.extend(_validate_state(state, str(client_dir)))
    completed = set(state.get("completed", []))

    if "client-intake" in completed:
        if not paths.has_client_input_for_migration():
            errors.append(f"{client_dir}: completed client-intake but missing input/client-input.yaml")
        if not paths.read_client_profile().exists():
            errors.append(f"{client_dir}: completed client-intake but missing derived/client-profile.yaml")

    if "resolve-intelligence" in completed and not paths.has_derived_intelligence_for_migration():
        errors.append(
            f"{client_dir}: completed resolve-intelligence but missing derived resolved-presets/intelligence-map/capability-map/gaps"
        )

    if "resource-research" in completed:
        if not paths.resource_requirements.exists():
            errors.append(f"{client_dir}: completed resource-research but missing derived/resource-requirements.yaml")
        if not paths.resource_selection.exists():
            errors.append(f"{client_dir}: completed resource-research but missing resources/selection.yaml")

    required: dict[str, list[Path]] = {
        "generate-directions": [
            client_dir / "directions" / "direction-a.yaml",
            client_dir / "directions" / "direction-b.yaml",
            client_dir / "directions" / "direction-c.yaml",
            client_dir / "directions" / "comparison.yaml",
        ],
        "build-prototype": [client_dir / "prototype" / "prototype-manifest.yaml"],
        "visual-qa": [
            client_dir / "prototype" / "qa" / "screenshot-manifest.yaml",
            client_dir / "prototype" / "qa" / "visual-findings.yaml",
        ],
        "client-review": [client_dir / "approved-experience.yaml"],
    }
    for stage, stage_paths in required.items():
        if stage in completed:
            for path in stage_paths:
                if not path.exists():
                    errors.append(f"{client_dir}: completed {stage} but missing {path.relative_to(client_dir)}")

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
    return errors


def validate_runtime(root: Path) -> list[str]:
    errors: list[str] = []
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
