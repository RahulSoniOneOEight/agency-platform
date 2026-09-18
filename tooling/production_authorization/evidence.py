from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .eligibility import evaluate_eligibility
from .errors import (
    InvalidReleaseCandidate,
    ProductionAuthorizationEvidenceMissing,
    ProductionAuthorizationEvidenceStale,
)
from .models import ReleaseCandidate


def load_release_candidate(path: Path) -> ReleaseCandidate:
    path = Path(path)
    if not path.exists():
        raise ProductionAuthorizationEvidenceMissing(
            f"release candidate does not exist: {path}"
        )
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise InvalidReleaseCandidate(f"cannot parse release candidate: {exc}") from exc
    if not isinstance(raw, dict):
        raise InvalidReleaseCandidate("release candidate must be a JSON object")
    return ReleaseCandidate.from_dict(raw)


def evidence_freshness_errors(candidate: ReleaseCandidate) -> list[str]:
    """Return only stale/missing/failed evidence-related eligibility reasons."""
    evidence_prefixes = (
        "qa_",
        "validation_",
        "validator_",
        "security_",
        "rollback_",
        "migration_",
        "release_notes_",
    )
    return [
        reason.code
        for reason in evaluate_eligibility(candidate).reasons
        if reason.code.startswith(evidence_prefixes)
    ]


def require_fresh_evidence(candidate: ReleaseCandidate) -> None:
    errors = evidence_freshness_errors(candidate)
    if errors:
        raise ProductionAuthorizationEvidenceStale(
            "candidate release evidence is not fresh/passing: " + ", ".join(errors)
        )


def load_json_object(path: Path) -> dict[str, Any]:
    path = Path(path)
    if not path.exists():
        raise ProductionAuthorizationEvidenceMissing(f"evidence is missing: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ProductionAuthorizationEvidenceMissing(
            f"evidence cannot be parsed: {path}: {exc}"
        ) from exc
    if not isinstance(value, dict):
        raise ProductionAuthorizationEvidenceMissing(
            f"evidence must be a JSON object: {path}"
        )
    return value
