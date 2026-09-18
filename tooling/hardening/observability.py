"""H.2 observability gate (spec section 12, plan Task 6).

Requires evidence that the reference observability adapter was initialized,
that release/environment/client/candidate tags are present, that both handled
and unhandled exception capture are proven, and that redaction is proven.
Missing critical visibility is blocking (``high``); alert-tuning/dashboard
notes are advisory.

Evidence shape (JSON object)::

    {
      "adapter_initialized": true,
      "tags": {
        "release": "0.1.0+h2rc1",
        "environment": "staging",
        "client": "reference-commerce",
        "candidate": "sha256:..."
      },
      "exception_capture": {"handled": true, "unhandled": true},
      "redaction": {"proven": true},
      "alert_tuning": ["..."],
      "dashboard_notes": ["..."]
    }

``redaction`` may also be the bare boolean ``true``. The evaluator is pure and
offline.
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

AREA = "observability"
EVIDENCE_RELATIVE = Path("production") / "evidence" / "observability-evidence.json"

REQUIRED_TAGS: tuple[str, ...] = ("release", "environment", "client", "candidate")


def _blocking(id: str, severity: str, summary: str) -> dict[str, Any]:
    return make_finding(
        id=id,
        area=AREA,
        severity=severity,
        disposition="blocking",
        status="open",
        summary=summary,
        evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
    )


def evaluate_observability(
    root: Path,
    client_dir: Path,
    evidence: Mapping[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Return deterministic, sorted observability findings for *client_dir*."""
    if evidence is None:
        evidence = load_evidence(client_dir, EVIDENCE_RELATIVE)
    if evidence is None:
        return [missing_evidence_finding(AREA, EVIDENCE_RELATIVE)]
    if not isinstance(evidence, Mapping):
        return [_blocking("observability-evidence-invalid", "high", "observability evidence must be a mapping")]

    findings: list[dict[str, Any]] = []

    if evidence.get("adapter_initialized") is not True:
        findings.append(
            _blocking(
                "observability-adapter-not-initialized",
                "high",
                "reference observability adapter was not initialized",
            )
        )

    tags = evidence.get("tags")
    if not isinstance(tags, Mapping):
        tags = {}
    for tag in REQUIRED_TAGS:
        value = tags.get(tag)
        if not isinstance(value, str) or not value:
            findings.append(
                _blocking(
                    f"observability-tag-{tag}",
                    "high",
                    f"required observability tag {tag} is missing",
                )
            )

    capture = evidence.get("exception_capture")
    if not isinstance(capture, Mapping):
        capture = {}
    if capture.get("handled") is not True:
        findings.append(
            _blocking(
                "observability-capture-handled",
                "high",
                "handled exception capture is not proven",
            )
        )
    if capture.get("unhandled") is not True:
        findings.append(
            _blocking(
                "observability-capture-unhandled",
                "high",
                "unhandled exception capture is not proven",
            )
        )

    redaction = evidence.get("redaction")
    redaction_ok = redaction is True or (
        isinstance(redaction, Mapping) and redaction.get("proven") is True
    )
    if not redaction_ok:
        findings.append(
            _blocking(
                "observability-redaction",
                "high",
                "sensitive-data redaction is not proven",
            )
        )

    for key in ("alert_tuning", "dashboard_notes"):
        notes = evidence.get(key)
        if isinstance(notes, Sequence) and not isinstance(notes, (str, bytes)):
            for index, note in enumerate(notes):
                if not isinstance(note, str) or not note:
                    continue
                findings.append(
                    make_finding(
                        id=f"observability-{key}-{index}",
                        area=AREA,
                        severity="low",
                        disposition="advisory",
                        status="open",
                        summary=note,
                        evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                    )
                )

    return sort_findings(findings)
