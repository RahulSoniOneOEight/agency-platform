"""H.2 accessibility gate (spec section 15, plan Task 6).

Critical journeys are exactly the six from
``production/hardening/accessibility-policy.yaml`` (with a canonical fallback
constant). A critical journey missing required ``keyboard``/``focus``/
``semantics`` evidence is blocking; a non-critical manual-review issue is
advisory.

Evidence shape (JSON object)::

    {
      "journeys": {
        "sign-in": {
          "keyboard": true,
          "focus": true,
          "semantics": true,
          "labels": true,
          "contrast": true
        },
        ...
      },
      "manual_review": [
        {
          "id": "a11y-1",
          "journey": "catalog",
          "severity": "medium",
          "summary": "...",
          "refs": ["..."]
        }
      ]
    }

``keyboard``/``focus``/``semantics`` are required checks (blocking when absent
or false). ``labels``/``contrast`` are advisory checks on critical journeys. A
manual-review issue on a critical journey is blocking; elsewhere it is
advisory.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

import yaml

from tooling.hardening.findings import (
    SEVERITIES,
    load_evidence,
    make_finding,
    missing_evidence_finding,
    sort_findings,
)

AREA = "accessibility"
EVIDENCE_RELATIVE = Path("production") / "evidence" / "accessibility-evidence.json"
POLICY_RELATIVE = Path("production") / "hardening" / "accessibility-policy.yaml"

CRITICAL_JOURNEYS: tuple[str, ...] = (
    "sign-in",
    "catalog",
    "product-detail",
    "cart-order",
    "b2b-account-credit",
    "rfq-quotation-order",
)

REQUIRED_CHECKS: tuple[str, ...] = ("keyboard", "focus", "semantics")
ADVISORY_CHECKS: tuple[str, ...] = ("labels", "contrast")


def _critical_journeys(client_dir: Path) -> tuple[str, ...]:
    path = Path(client_dir) / POLICY_RELATIVE
    if not path.is_file():
        return CRITICAL_JOURNEYS
    try:
        policy = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, yaml.YAMLError):
        return CRITICAL_JOURNEYS
    if not isinstance(policy, Mapping):
        return CRITICAL_JOURNEYS
    journeys = policy.get("critical_journeys")
    if not isinstance(journeys, Sequence) or isinstance(journeys, (str, bytes)):
        return CRITICAL_JOURNEYS
    names = tuple(name for name in journeys if isinstance(name, str) and name)
    return names or CRITICAL_JOURNEYS


def _refs(value: object) -> list[str]:
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, Sequence):
        return [ref for ref in value if isinstance(ref, str) and ref]
    return []


def evaluate_accessibility(
    root: Path,
    client_dir: Path,
    evidence: Mapping[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Return deterministic, sorted accessibility findings for *client_dir*."""
    if evidence is None:
        evidence = load_evidence(client_dir, EVIDENCE_RELATIVE)
    if evidence is None:
        return [missing_evidence_finding(AREA, EVIDENCE_RELATIVE)]
    if not isinstance(evidence, Mapping):
        return [
            make_finding(
                id="accessibility-evidence-invalid",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary="accessibility evidence must be a mapping",
                evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
            )
        ]

    critical = _critical_journeys(client_dir)
    journeys = evidence.get("journeys")
    if not isinstance(journeys, Mapping):
        journeys = {}

    findings: list[dict[str, Any]] = []

    for journey in critical:
        entry = journeys.get(journey)
        if not isinstance(entry, Mapping):
            findings.append(
                make_finding(
                    id=f"accessibility-{journey}-missing",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=(
                        f"critical journey {journey} has no accessibility evidence"
                    ),
                    evidence_refs=[journey],
                )
            )
            continue

        for check in REQUIRED_CHECKS:
            if entry.get(check) is not True:
                findings.append(
                    make_finding(
                        id=f"accessibility-{journey}-{check}",
                        area=AREA,
                        severity="high",
                        disposition="blocking",
                        status="open",
                        summary=(
                            f"critical journey {journey} missing/failed "
                            f"required {check} evidence"
                        ),
                        evidence_refs=[journey, check],
                    )
                )

        for check in ADVISORY_CHECKS:
            if entry.get(check) is not True:
                findings.append(
                    make_finding(
                        id=f"accessibility-{journey}-{check}",
                        area=AREA,
                        severity="medium",
                        disposition="advisory",
                        status="open",
                        summary=(
                            f"critical journey {journey} has no {check} evidence"
                        ),
                        evidence_refs=[journey, check],
                    )
                )

    manual = evidence.get("manual_review")
    if isinstance(manual, Sequence) and not isinstance(manual, (str, bytes)):
        for index, raw in enumerate(manual):
            if not isinstance(raw, Mapping):
                continue
            native_id = raw.get("id")
            if not isinstance(native_id, str) or not native_id:
                native_id = f"entry-{index}"
            journey = raw.get("journey")
            journey_name = journey if isinstance(journey, str) else ""
            on_critical = journey_name in critical
            severity = str(raw.get("severity", "")).lower()
            if severity not in SEVERITIES:
                severity = "medium"
            summary = raw.get("summary")
            if not isinstance(summary, str) or not summary:
                summary = f"manual accessibility review {native_id}"
            findings.append(
                make_finding(
                    id=f"accessibility-manual-{native_id}",
                    area=AREA,
                    severity=severity if on_critical else "medium",
                    disposition="blocking" if on_critical else "advisory",
                    status="open",
                    summary=summary,
                    evidence_refs=_refs(raw.get("refs"))
                    + ([journey_name] if journey_name else []),
                )
            )

    return sort_findings(findings)
