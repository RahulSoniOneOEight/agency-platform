"""Shared finding and gate-aggregation helpers for the H.2 hardening gates.

Every operational hardening gate (security, performance, accessibility,
analytics, observability, migrations) produces the same normalized finding
contract so the hardening report can aggregate them uniformly:

- ``SEVERITIES``: ``info``, ``low``, ``medium``, ``high``, ``critical``
- ``DISPOSITIONS``: ``advisory``, ``blocking``
- ``STATUSES``: ``open``, ``closed``, ``waived``
- ``AREAS``: ``security``, ``performance``, ``accessibility``, ``analytics``,
  ``observability``, ``migrations``

A finding is exactly the seven keys produced by :func:`make_finding`. Gate
aggregation (:func:`aggregate_gate`) blocks only when a finding is both
``disposition == "blocking"`` and ``status == "open"``; closed or waived
findings never block, and advisory findings never block.

All helpers here are pure and offline: they never touch the network, a
scanner, or a database. Evidence is injectable so tests stay deterministic.
"""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

SEVERITIES: tuple[str, ...] = ("info", "low", "medium", "high", "critical")
DISPOSITIONS: tuple[str, ...] = ("advisory", "blocking")
STATUSES: tuple[str, ...] = ("open", "closed", "waived")
AREAS: tuple[str, ...] = (
    "security",
    "performance",
    "accessibility",
    "analytics",
    "observability",
    "migrations",
)

FINDING_KEYS: tuple[str, ...] = (
    "id",
    "area",
    "severity",
    "disposition",
    "status",
    "summary",
    "evidence_refs",
)


def _require_enum(value: object, allowed: tuple[str, ...], label: str) -> str:
    if value not in allowed:
        raise ValueError(f"{label} must be one of {list(allowed)}; got {value!r}")
    return str(value)


def _clean_refs(evidence_refs: object) -> list[str]:
    if evidence_refs is None:
        return []
    if isinstance(evidence_refs, str):
        evidence_refs = [evidence_refs]
    if not isinstance(evidence_refs, Sequence):
        raise ValueError("evidence_refs must be a sequence of strings")
    refs: list[str] = []
    for ref in evidence_refs:
        if not isinstance(ref, str) or not ref:
            raise ValueError("evidence_refs entries must be non-empty strings")
        refs.append(ref)
    return sorted(set(refs))


def make_finding(
    id: str,
    area: str,
    severity: str,
    disposition: str,
    status: str,
    summary: str,
    evidence_refs: object = (),
) -> dict[str, Any]:
    """Return a normalized finding with exactly the seven contract keys.

    Every enum is validated; an invalid value raises ``ValueError`` so a
    malformed evaluator cannot silently emit an out-of-contract finding.
    ``evidence_refs`` is stored as a sorted, de-duplicated list.
    """
    if not isinstance(id, str) or not id:
        raise ValueError("id must be a non-empty string")
    _require_enum(area, AREAS, "area")
    _require_enum(severity, SEVERITIES, "severity")
    _require_enum(disposition, DISPOSITIONS, "disposition")
    _require_enum(status, STATUSES, "status")
    if not isinstance(summary, str) or not summary:
        raise ValueError("summary must be a non-empty string")
    return {
        "id": id,
        "area": area,
        "severity": severity,
        "disposition": disposition,
        "status": status,
        "summary": summary,
        "evidence_refs": _clean_refs(evidence_refs),
    }


def finding_sort_key(finding: Mapping[str, Any]) -> tuple[str, str]:
    """Deterministic ordering key for findings: ``(area, id)``."""
    return (str(finding.get("area", "")), str(finding.get("id", "")))


def sort_findings(findings: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """Return a new list of findings sorted by ``(area, id)``."""
    return sorted((dict(finding) for finding in findings), key=finding_sort_key)


def aggregate_gate(findings: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Aggregate findings into a gate decision.

    Returns ``{"blocking_findings", "advisory_findings", "eligible",
    "findings"}``. A finding is blocking only when its disposition is
    ``blocking`` *and* its status is ``open``; a closed/waived blocking
    finding never blocks. Advisory findings are reported for visibility and
    never block. ``eligible`` is true when there are no blocking findings.
    """
    ordered = sort_findings(findings)
    blocking = [
        finding
        for finding in ordered
        if finding["disposition"] == "blocking" and finding["status"] == "open"
    ]
    advisory = [
        finding for finding in ordered if finding["disposition"] == "advisory"
    ]
    return {
        "blocking_findings": blocking,
        "advisory_findings": advisory,
        "eligible": not blocking,
        "findings": ordered,
    }


def load_evidence(client_dir: Path, relative: Path) -> Any | None:
    """Load injectable evidence JSON from ``client_dir / relative``.

    Returns the parsed value, or ``None`` when the file is absent or cannot be
    parsed. Callers translate ``None`` into a blocking ``*_evidence_missing``
    finding, so a gate can never pass on missing evidence.
    """
    path = Path(client_dir) / relative
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None


def missing_evidence_finding(area: str, relative: Path) -> dict[str, Any]:
    """Return the blocking finding used when a gate has no evidence at all."""
    return make_finding(
        id=f"{area}-evidence-missing",
        area=area,
        severity="high",
        disposition="blocking",
        status="open",
        summary=f"{area} gate evidence is missing at {Path(relative).as_posix()}",
        evidence_refs=[Path(relative).as_posix()],
    )
