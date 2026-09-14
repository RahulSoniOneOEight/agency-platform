from __future__ import annotations

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
