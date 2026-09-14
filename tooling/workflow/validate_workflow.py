from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

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
    "client-profile.yaml",
    "direction.yaml",
    "direction-comparison.yaml",
    "workflow-state.yaml",
    "approved-experience.yaml",
]


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


def validate_client(root: Path, client_dir: Path) -> list[str]:
    errors: list[str] = []
    state_path = client_dir / "workflow-state.yaml"
    if not state_path.exists():
        return [f"{client_dir}: missing workflow-state.yaml"]
    try:
        state = load_state(state_path)
    except Exception as exc:
        return [f"{client_dir}: cannot load workflow-state.yaml: {exc}"]
    errors.extend(_validate_state(state, str(client_dir)))
    completed = set(state.get("completed", []))

    required: dict[str, list[Path]] = {
        "client-intake": [client_dir / "client-profile.yaml"],
        "resolve-intelligence": [client_dir / "resolved-intelligence.yaml"],
        "resource-research": [client_dir / "resources" / "selection.yaml"],
        "generate-directions": [
            client_dir / "directions" / "direction-a.yaml",
            client_dir / "directions" / "direction-b.yaml",
            client_dir / "directions" / "direction-c.yaml",
            client_dir / "directions" / "comparison.yaml",
        ],
        "client-review": [client_dir / "approved-experience.yaml"],
    }
    for stage, paths in required.items():
        if stage in completed:
            for path in paths:
                if not path.exists():
                    errors.append(f"{client_dir}: completed {stage} but missing {path.relative_to(client_dir)}")

    if "productionize" in completed and not (client_dir / "approved-experience.yaml").exists():
        errors.append(f"{client_dir}: productionize requires approved-experience.yaml")
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
            if not client_dir.is_dir() or client_dir.name == "schema" or client_dir.name.startswith("."):
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
