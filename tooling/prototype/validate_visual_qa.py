from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

from .screenshot_manifest import InvalidCaptureJob, normalize_manifest

REQUIRED_FINDING_FIELDS = ("severity", "screen", "direction", "viewport", "issue", "status")
ALLOWED_SEVERITY = {"low", "medium", "high", "critical"}
ALLOWED_STATUS = {"open", "resolved", "accepted"}


def validate_visual_findings(data: dict) -> list[str]:
    errors: list[str] = []
    if not data.get("client_id"):
        errors.append("visual QA requires client_id")
    findings = data.get("findings")
    if not isinstance(findings, list):
        return errors + ["visual QA findings must be a list"]
    for index, finding in enumerate(findings):
        if not isinstance(finding, dict):
            errors.append(f"finding {index} must be an object")
            continue
        for field in REQUIRED_FINDING_FIELDS:
            if not finding.get(field):
                errors.append(f"finding {index} missing field: {field}")
        if finding.get("severity") not in ALLOWED_SEVERITY:
            errors.append(f"finding {index} has invalid severity")
        if finding.get("status") not in ALLOWED_STATUS:
            errors.append(f"finding {index} has invalid status")
    return errors


def unresolved_critical_findings(data: dict) -> list[dict]:
    return [
        item
        for item in data.get("findings", [])
        if isinstance(item, dict)
        and item.get("severity") == "critical"
        and item.get("status") == "open"
    ]


def validate_client_visual_qa(client_dir: Path) -> list[str]:
    """Validate a client's governed QA artifacts.

    Checks the deterministic screenshot manifest (v1 or v2) and, when present,
    the legacy ``visual-findings.yaml`` compatibility artifact. v2 ``QAFinding``
    records under ``prototype/qa/findings/`` are validated by the D.2 contracts
    (``tooling.visual_qa.qa_contracts``).
    """
    errors: list[str] = []
    client_dir = Path(client_dir)
    qa_dir = client_dir / "prototype" / "qa"

    manifest_path = qa_dir / "screenshot-manifest.yaml"
    if not manifest_path.exists():
        errors.append(f"{client_dir}: missing screenshot manifest")
    else:
        try:
            data = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            errors.append(f"{manifest_path}: invalid screenshot manifest yaml: {exc}")
        else:
            try:
                normalize_manifest(data)
            except InvalidCaptureJob as exc:
                errors.append(f"{manifest_path}: invalid screenshot manifest: {exc}")

    findings_path = qa_dir / "visual-findings.yaml"
    if findings_path.exists():
        try:
            data = yaml.safe_load(findings_path.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            errors.append(f"{findings_path}: invalid visual findings yaml: {exc}")
        else:
            if isinstance(data, dict):
                errors.extend(
                    f"{findings_path}: {error}"
                    for error in validate_visual_findings(data)
                )
            else:
                errors.append(f"{findings_path}: visual findings must be a mapping")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="validate_visual_qa",
        description="Validate a client's governed visual-QA artifacts.",
    )
    parser.add_argument(
        "client_dir",
        nargs="?",
        default="client-projects/examples/prototype-demo",
        help="Client project directory to validate.",
    )
    args = parser.parse_args(argv)
    errors = validate_client_visual_qa(Path(args.client_dir))
    if errors:
        print("Visual QA validation failed.")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"Visual QA validation passed: {args.client_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
