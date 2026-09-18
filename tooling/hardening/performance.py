"""H.2 performance budget gate (spec section 14, plan Task 6).

Compares injected staging measurements against the exact, repository-owned
budgets in ``production/hardening/performance-budget.yaml`` (Task 4). A value
**equal** to its maximum passes; a value **strictly greater** is a blocking
``high`` finding. ``baseline_regression_percent`` follows the same rule
(``> 20`` blocks).

Evidence shape (JSON object) is the measurement mapping itself::

    {
      "main_js_raw_bytes": 4200000,
      "web_build_total_bytes": 17500000,
      "first_contentful_paint_ms": 2500,
      "largest_contentful_paint_ms": 4000,
      "critical_screen_ready_ms": 4000,
      "critical_api_p95_ms": 900,
      "baseline_regression_percent": 12
    }

The evaluator is pure and offline: it only reads the committed budget policy.
"""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Any

import yaml

from tooling.hardening.findings import (
    load_evidence,
    make_finding,
    missing_evidence_finding,
    sort_findings,
)

AREA = "performance"
EVIDENCE_RELATIVE = Path("production") / "evidence" / "performance-measurements.json"
BUDGET_RELATIVE = Path("production") / "hardening" / "performance-budget.yaml"

# measurement key -> budget key in performance-budget.yaml
MEASUREMENT_BUDGETS: dict[str, str] = {
    "main_js_raw_bytes": "main_js_raw_bytes_max",
    "web_build_total_bytes": "web_build_total_bytes_max",
    "first_contentful_paint_ms": "first_contentful_paint_ms_max",
    "largest_contentful_paint_ms": "largest_contentful_paint_ms_max",
    "critical_screen_ready_ms": "critical_screen_ready_ms_max",
    "critical_api_p95_ms": "critical_api_p95_ms_max",
    "baseline_regression_percent": "baseline_regression_percent_max",
}


def _load_budgets(client_dir: Path) -> dict[str, Any] | None:
    path = Path(client_dir) / BUDGET_RELATIVE
    if not path.is_file():
        return None
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, yaml.YAMLError):
        return None
    return payload if isinstance(payload, Mapping) else None


def _budget_finding(budget_key: str, summary: str) -> dict[str, Any]:
    return make_finding(
        id=f"performance-budget-invalid-{budget_key}",
        area=AREA,
        severity="high",
        disposition="blocking",
        status="open",
        summary=summary,
        evidence_refs=[BUDGET_RELATIVE.as_posix()],
    )


def evaluate_performance(
    root: Path,
    client_dir: Path,
    measurements: Mapping[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Return deterministic, sorted performance findings for *client_dir*."""
    if measurements is None:
        measurements = load_evidence(client_dir, EVIDENCE_RELATIVE)
    if measurements is None:
        return [missing_evidence_finding(AREA, EVIDENCE_RELATIVE)]
    if not isinstance(measurements, Mapping):
        return [
            make_finding(
                id="performance-evidence-invalid",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary="performance measurements must be a mapping",
                evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
            )
        ]

    budgets = _load_budgets(client_dir)
    if budgets is None:
        return [
            make_finding(
                id="performance-budget-missing",
                area=AREA,
                severity="high",
                disposition="blocking",
                status="open",
                summary=(
                    "performance budget policy is missing or invalid at "
                    f"{BUDGET_RELATIVE.as_posix()}"
                ),
                evidence_refs=[BUDGET_RELATIVE.as_posix()],
            )
        ]

    findings: list[dict[str, Any]] = []
    for measurement, budget_key in MEASUREMENT_BUDGETS.items():
        maximum = budgets.get(budget_key)
        if isinstance(maximum, bool) or not isinstance(maximum, int):
            findings.append(
                _budget_finding(
                    budget_key,
                    f"budget {budget_key} must be an integer",
                )
            )
            continue

        if measurement not in measurements:
            findings.append(
                make_finding(
                    id=f"performance-measurement-missing-{measurement}",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=f"measurement {measurement} is missing",
                    evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                )
            )
            continue

        value = measurements[measurement]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            findings.append(
                make_finding(
                    id=f"performance-measurement-invalid-{measurement}",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=f"measurement {measurement} must be numeric",
                    evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                )
            )
            continue

        if value > maximum:
            findings.append(
                make_finding(
                    id=f"performance-{measurement}-over-budget",
                    area=AREA,
                    severity="high",
                    disposition="blocking",
                    status="open",
                    summary=(
                        f"{measurement}={value} exceeds budget {maximum}"
                    ),
                    evidence_refs=[
                        BUDGET_RELATIVE.as_posix(),
                        EVIDENCE_RELATIVE.as_posix(),
                    ],
                )
            )

    return sort_findings(findings)
