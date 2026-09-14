from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from tooling.prototype.approved_experience import validate_approved_experience
from tooling.prototype.validate_visual_qa import unresolved_critical_findings, validate_visual_findings
from tooling.workflow.client_input import blocking_open_questions, validate_client_input


def _is_skipped(state: dict[str, Any], stage: str) -> bool:
    return any(item.get("stage") == stage and item.get("reason") for item in state.get("skipped", []))


def _directions_ready(client_dir: Path) -> bool:
    directions = client_dir / "directions"
    required = ["direction-a.yaml", "direction-b.yaml", "comparison.yaml"]
    return all((directions / name).exists() for name in required)


def _prototype_platform_installed(root: Path) -> bool:
    return (
        (root / "packages" / "agency_flutter_ui" / "pubspec.yaml").exists()
        and (root / "apps" / "prototype_app" / "pubspec.yaml").exists()
    )


def _load_yaml(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def next_stage(root: Path, client_dir: Path, state: dict[str, Any]) -> dict[str, Any]:
    completed = set(state.get("completed", []))

    if validate_client_input(root, client_dir):
        return {"stage": "client-intake", "status": "blocked", "reason": "client-input-invalid"}
    if blocking_open_questions(client_dir):
        return {"stage": "client-intake", "status": "blocked", "reason": "blocking-open-questions"}

    if "client-intake" not in completed:
        return {"stage": "client-intake", "status": "ready"}

    if not (client_dir / "derived" / "client-profile.yaml").exists():
        return {"stage": "client-intake", "status": "blocked", "reason": "derived-client-profile-missing"}

    if "resolve-intelligence" not in completed:
        return {"stage": "resolve-intelligence", "status": "ready"}

    if not (client_dir / "resolved-intelligence.yaml").exists():
        return {"stage": "resolve-intelligence", "status": "blocked", "reason": "resolved-intelligence-missing"}

    if "resource-research" not in completed and not _is_skipped(state, "resource-research"):
        return {"stage": "resource-research", "status": "ready"}

    if "generate-directions" not in completed:
        return {"stage": "generate-directions", "status": "ready"}

    if not _directions_ready(client_dir):
        return {"stage": "generate-directions", "status": "blocked", "reason": "direction-artifacts-missing"}

    if "build-prototype" not in completed:
        if not _prototype_platform_installed(root):
            return {"stage": "build-prototype", "status": "blocked", "reason": "prototype-platform-not-installed"}
        return {"stage": "build-prototype", "status": "ready"}

    prototype_manifest = client_dir / "prototype" / "prototype-manifest.yaml"
    if not prototype_manifest.exists():
        return {"stage": "build-prototype", "status": "blocked", "reason": "prototype-manifest-missing"}

    if "visual-qa" not in completed:
        return {"stage": "visual-qa", "status": "ready"}

    qa_dir = client_dir / "prototype" / "qa"
    screenshot_manifest = qa_dir / "screenshot-manifest.yaml"
    findings_path = qa_dir / "visual-findings.yaml"
    if not screenshot_manifest.exists():
        return {"stage": "visual-qa", "status": "blocked", "reason": "screenshot-manifest-missing"}
    if not findings_path.exists():
        return {"stage": "visual-qa", "status": "blocked", "reason": "visual-findings-missing"}
    findings = _load_yaml(findings_path)
    findings_errors = validate_visual_findings(findings)
    if findings_errors:
        return {"stage": "visual-qa", "status": "blocked", "reason": "visual-findings-invalid"}
    if unresolved_critical_findings(findings):
        return {"stage": "visual-qa", "status": "blocked", "reason": "critical-visual-qa-findings"}

    if "client-review" not in completed:
        return {"stage": "client-review", "status": "ready"}

    approved = client_dir / "approved-experience.yaml"
    if not approved.exists():
        return {"stage": "client-review", "status": "blocked", "reason": "approved-experience-missing"}
    if validate_approved_experience(root, client_dir):
        return {"stage": "client-review", "status": "blocked", "reason": "approved-experience-invalid"}

    if "productionize" not in completed:
        return {"stage": "productionize", "status": "ready"}

    return {"stage": None, "status": "complete"}
