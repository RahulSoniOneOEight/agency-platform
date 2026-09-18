"""H.2 hardening report aggregation (spec sections 10 and 23, Task 7).

The hardening report is the single canonical H.2A evidence artifact. It binds the
frozen release candidate identity to every gate result, keeps blocking and
advisory findings separate, and records whether the candidate is eligible to be
put forward for the human Milestone-G production authorization.

``eligible_for_authorization`` is true **only** when there are no open blocking
findings *and* the staging smoke report proves every critical journey passed.
Advisory findings are always retained in the report; they are never dropped.

Like every H.2 identity, ``report_identity`` is the canonical ``sha256:`` identity
over the report excluding ``report_identity`` itself, so the report is
self-verifying. The module is pure and offline.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from tooling.hardening.candidate import TARGET_ENVIRONMENT, canonical_identity
from tooling.hardening.findings import (
    AREAS,
    aggregate_gate,
    missing_evidence_finding,
)
from tooling.hardening.staging_smoke import smoke_report_path

REPORT_VERSION = 1
HARDENING_REPORT_NAME = "h2-hardening-report.json"
EVIDENCE_RELATIVE = Path("production") / "evidence"
GATE_EVIDENCE_RELATIVE = Path("production") / "hardening" / "gate-evidence.json"


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _canonical_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(value), encoding="utf-8", newline="\n")


def hardening_report_identity(report: Mapping[str, Any]) -> str:
    """Return the canonical identity of *report* excluding ``report_identity``."""
    body = {key: value for key, value in report.items() if key != "report_identity"}
    return canonical_identity(body)


def _gate_result(area: str, findings: Any) -> dict[str, Any]:
    if not isinstance(findings, list):
        findings = [missing_evidence_finding(area, GATE_EVIDENCE_RELATIVE)]
    aggregate = aggregate_gate(findings)
    return {
        "area": area,
        "findings": aggregate["findings"],
        "blocking_findings": aggregate["blocking_findings"],
        "advisory_findings": aggregate["advisory_findings"],
        "passed": aggregate["eligible"],
    }


def build_hardening_report(
    root: Path,
    client_dir: Path,
    candidate: Mapping[str, Any],
    gate_findings: Mapping[str, list[dict]],
    smoke_report: Mapping[str, Any],
) -> dict[str, Any]:
    """Aggregate the six gate findings and the staging smoke result.

    Returns the canonical hardening report. ``gate_results`` is deterministic and
    sorted by area; the report-level ``blocking_findings`` and
    ``advisory_findings`` are the sorted union of every gate's findings.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    candidate = candidate if isinstance(candidate, Mapping) else {}
    gate_findings = gate_findings if isinstance(gate_findings, Mapping) else {}
    smoke_report = smoke_report if isinstance(smoke_report, Mapping) else {}

    gate_results: list[dict[str, Any]] = []
    combined: list[dict[str, Any]] = []
    for area in sorted(AREAS):
        result = _gate_result(area, gate_findings.get(area))
        gate_results.append(result)
        combined.extend(result["findings"])

    aggregate = aggregate_gate(combined)

    client_id = candidate.get("client_id")
    report: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "client_id": client_id if isinstance(client_id, str) else client_dir.name,
        "target_environment": TARGET_ENVIRONMENT,
        "candidate_identity": candidate.get("candidate_identity"),
        "artifact_digest": candidate.get("artifact_digest"),
        "migration_set_identity": candidate.get("migration_set_identity"),
        "release_config_identity": candidate.get("release_config_identity"),
        "gate_results": gate_results,
        "blocking_findings": aggregate["blocking_findings"],
        "advisory_findings": aggregate["advisory_findings"],
        "staging_smoke_ref": {
            "ref": _relative(root, smoke_report_path(client_dir)),
            "report_identity": smoke_report.get("report_identity"),
            "deployment_id": smoke_report.get("deployment_id"),
            "artifact_digest": smoke_report.get("artifact_digest"),
            "candidate_identity": smoke_report.get("candidate_identity"),
            "critical_journeys_passed": bool(
                smoke_report.get("critical_journeys_passed")
            ),
        },
        "eligible_for_authorization": (
            not aggregate["blocking_findings"]
            and bool(smoke_report.get("critical_journeys_passed"))
        ),
    }
    report["report_identity"] = hardening_report_identity(report)
    return report


def hardening_report_path(client_dir: Path) -> Path:
    return Path(client_dir) / EVIDENCE_RELATIVE / HARDENING_REPORT_NAME


def load_hardening_report(client_dir: Path) -> Mapping[str, Any]:
    path = hardening_report_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def write_hardening_report(
    root: Path, client_dir: Path, report: Mapping[str, Any]
) -> Path:
    path = hardening_report_path(client_dir)
    _write_json(path, report)
    return path
