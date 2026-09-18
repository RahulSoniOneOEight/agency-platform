"""H.2 analytics gate (spec section 13, plan Task 6).

Requires every governed critical event name to be emitted with a governed
``name`` and a ``parameters`` mapping. A missing/invalid required event is
blocking; an unknown/experimental extra event is advisory.

Evidence may be a bare list of event objects, or an object carrying an
optional environment::

    {
      "environment": "staging",
      "events": [
        {"name": "sign_in", "parameters": {"method": "password"}},
        ...
      ]
    }

Every event's ``environment`` (or the envelope ``environment``) is attached to
the finding evidence refs when present. The evaluator is pure and offline.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from tooling.hardening.findings import (
    load_evidence,
    make_finding,
    missing_evidence_finding,
    sort_findings,
)

AREA = "analytics"
EVIDENCE_RELATIVE = Path("production") / "evidence" / "analytics-events.json"

GOVERNED_EVENTS: tuple[str, ...] = (
    "sign_in",
    "catalog_view",
    "product_view",
    "cart_created",
    "cart_updated",
    "checkout_or_order_start",
    "order_created",
    "business_account_selected",
    "credit_viewed",
    "rfq_created",
    "quotation_viewed",
    "quotation_converted",
)


def _environment_refs(environment: object) -> list[str]:
    return [environment] if isinstance(environment, str) and environment else []


def evaluate_analytics(
    root: Path,
    client_dir: Path,
    emitted_events: Sequence[Mapping[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Return deterministic, sorted analytics findings for *client_dir*."""
    environment: object = None
    if emitted_events is None:
        loaded = load_evidence(client_dir, EVIDENCE_RELATIVE)
        if loaded is None:
            return [missing_evidence_finding(AREA, EVIDENCE_RELATIVE)]
        if isinstance(loaded, Mapping):
            environment = loaded.get("environment")
            emitted_events = loaded.get("events")
        else:
            emitted_events = loaded

    if not isinstance(emitted_events, Sequence) or isinstance(
        emitted_events, (str, bytes)
    ):
        return [
            make_finding(
                id="analytics-events-invalid",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary="emitted analytics events must be a sequence",
                evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
            )
        ]

    findings: list[dict[str, Any]] = []
    seen: set[str] = set()

    for index, raw in enumerate(emitted_events):
        if not isinstance(raw, Mapping):
            findings.append(
                make_finding(
                    id=f"analytics-event-{index}-invalid",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=f"emitted event at index {index} must be an object",
                    evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                )
            )
            continue

        name = raw.get("name")
        if not isinstance(name, str) or not name:
            findings.append(
                make_finding(
                    id=f"analytics-event-{index}-invalid-name",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=f"emitted event at index {index} has no governed name",
                    evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                )
            )
            continue

        event_environment = raw.get("environment", environment)
        refs = [name] + _environment_refs(event_environment)

        if not isinstance(raw.get("parameters"), Mapping):
            findings.append(
                make_finding(
                    id=f"analytics-event-{name}-parameters",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=f"governed event {name} is missing a parameters mapping",
                    evidence_refs=refs,
                )
            )

        if name in GOVERNED_EVENTS:
            seen.add(name)
        else:
            findings.append(
                make_finding(
                    id=f"analytics-event-extra-{name}",
                    area=AREA,
                    severity="low",
                    disposition="advisory",
                    status="open",
                    summary=f"unknown/experimental analytics event {name}",
                    evidence_refs=refs,
                )
            )

    for name in GOVERNED_EVENTS:
        if name not in seen:
            findings.append(
                make_finding(
                    id=f"analytics-event-missing-{name}",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=f"required governed event {name} was not emitted",
                    evidence_refs=[name] + _environment_refs(environment),
                )
            )

    return sort_findings(findings)
