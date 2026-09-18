"""H.2 security hardening gate (spec sections 10-11, plan Task 6).

Consumes *static* security/scanner evidence; it never runs a remote scanner,
contacts a provider, or executes SQL. Provider-native scanner severity is
preserved in the emitted finding severity (it is never remapped), while the
release *disposition* is derived from the hardening policy.

Evidence shape (JSON object)::

    {
      "findings": [
        {
          "id": "GHSA-xxxx",                 # stable scanner identifier
          "severity": "critical|high|medium|low|info",
          "status": "open|closed|waived",
          "release_relevant": true,
          "summary": "human summary",
          "refs": ["https://..."]            # optional
        }
      ],
      "secret_leak": false,                  # committed secret-like config
      "rls_validation": {"ok": true},        # RLS/auth policy validation
      "production_debug_enabled": false      # production debug/dev-mode guard
    }

Rules:

- open ``critical``/``high`` release-relevant finding -> blocking
- an open ``critical``/``high`` finding that omits/``null``s
  ``release_relevant`` is treated as release-relevant (fail closed) and also
  emits a deterministic blocking ``security-classification-missing`` finding
- any other open finding (medium/low/info or explicitly non-release-relevant)
  -> advisory
- a ``findings`` key that is present but not a list -> blocking
  ``security-evidence-invalid``
- closed/waived findings never block
- ``secret_leak: true`` -> blocking (critical)
- ``rls_validation.ok == false`` -> blocking (high)
- ``production_debug_enabled: true`` -> blocking (high)
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from tooling.hardening.findings import (
    SEVERITIES,
    STATUSES,
    load_evidence,
    make_finding,
    missing_evidence_finding,
    sort_findings,
)

AREA = "security"
EVIDENCE_RELATIVE = Path("production") / "evidence" / "security-evidence.json"
BLOCKING_SEVERITIES: tuple[str, ...] = ("critical", "high")


def _refs(value: object) -> list[str]:
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, Sequence):
        return [ref for ref in value if isinstance(ref, str) and ref]
    return []


def _scanner_findings(index: int, raw: object) -> list[dict[str, Any]]:
    if not isinstance(raw, Mapping):
        return [
            make_finding(
                id=f"security-scanner-{index}-invalid",
                area=AREA,
                severity="info",
                disposition="advisory",
                status="open",
                summary=f"malformed scanner finding entry at index {index}",
            )
        ]

    native_id = raw.get("id")
    if not isinstance(native_id, str) or not native_id:
        native_id = f"entry-{index}"

    native_severity = str(raw.get("severity", "")).strip().lower()
    severity = native_severity if native_severity in SEVERITIES else "info"

    native_status = str(raw.get("status", "open")).strip().lower()
    status = native_status if native_status in STATUSES else "open"

    raw_release_relevant = raw.get("release_relevant")
    classification_missing = (
        status == "open"
        and severity in BLOCKING_SEVERITIES
        and raw_release_relevant is None
    )
    release_relevant = (
        True if classification_missing else bool(raw_release_relevant)
    )
    blocking = (
        status == "open"
        and release_relevant
        and severity in BLOCKING_SEVERITIES
    )
    disposition = "blocking" if blocking else "advisory"

    summary = raw.get("summary")
    if not isinstance(summary, str) or not summary:
        summary = f"scanner finding {native_id}"

    refs = _refs(raw.get("refs"))
    emitted = [
        make_finding(
            id=f"security-scanner-{native_id}",
            area=AREA,
            severity=severity,
            disposition=disposition,
            status=status,
            summary=f"{summary} [native severity: {severity}]",
            evidence_refs=refs,
        )
    ]
    if classification_missing:
        emitted.append(
            make_finding(
                id=f"security-classification-missing-{native_id}",
                area=AREA,
                severity=severity,
                disposition="blocking",
                status="open",
                summary=(
                    f"open {severity} scanner finding {native_id} omits "
                    "release_relevant; treated as release-relevant"
                ),
                evidence_refs=refs,
            )
        )
    return emitted


def evaluate_security(
    root: Path,
    client_dir: Path,
    evidence: Mapping[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Return deterministic, sorted security findings for *client_dir*."""
    if evidence is None:
        evidence = load_evidence(client_dir, EVIDENCE_RELATIVE)
    if evidence is None:
        return [missing_evidence_finding(AREA, EVIDENCE_RELATIVE)]
    if not isinstance(evidence, Mapping):
        return [
            make_finding(
                id="security-evidence-invalid",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary="security evidence must be a mapping",
                evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
            )
        ]

    findings: list[dict[str, Any]] = []

    if "findings" in evidence:
        raw_findings = evidence.get("findings")
        if isinstance(raw_findings, Sequence) and not isinstance(
            raw_findings, (str, bytes)
        ):
            for index, raw in enumerate(raw_findings):
                findings.extend(_scanner_findings(index, raw))
        else:
            findings.append(
                make_finding(
                    id="security-evidence-invalid",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary="security evidence findings must be a list",
                    evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                )
            )

    if evidence.get("secret_leak") is True:
        findings.append(
            make_finding(
                id="security-secret-leak",
                area=AREA,
                severity="critical",
                disposition="blocking",
                status="open",
                summary="committed secret-like configuration detected",
            )
        )

    rls_validation = evidence.get("rls_validation")
    if isinstance(rls_validation, Mapping) and rls_validation.get("ok") is False:
        findings.append(
            make_finding(
                id="security-rls-validation",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary="RLS/auth policy validation failed",
            )
        )

    if evidence.get("production_debug_enabled") is True:
        findings.append(
            make_finding(
                id="security-production-debug",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary="production debug/dev-mode is enabled",
            )
        )

    return sort_findings(findings)
