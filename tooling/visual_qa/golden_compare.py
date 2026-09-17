"""Governed golden-baseline metadata and deterministic comparison policy.

Golden comparison is **deterministic regression detection, not aesthetic
judgment**. This module owns:

- the stable ``baseline_id`` identity of a governed baseline;
- the governed baseline index (versioned metadata that requires history);
- a pure comparison function that produces a [GoldenComparison] record and
  **never** writes, rewrites, or "heals" a baseline;
- reviewer-only authorization for baseline creation/update.

A golden mismatch fails the deterministic QA check according to CI policy,
produces diff/evidence metadata, and may produce a `QAFinding` — but it never
auto-updates the baseline.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from .errors import (
    GoldenBaselineMissing,
    InvalidBaselineIndex,
    UnauthorizedBaselineUpdate,
)

BASELINE_INDEX_VERSION = 1

ALLOWED_SURFACES = ("prototype", "widgetbook")

# Deterministic CI policy: which baseline results hard-fail a run.
GATING_RESULTS = ("mismatch", "missing_baseline")

REVIEWER_ROLES = ("reviewer",)


def baseline_id(job: dict) -> str:
    """Stable identity of the baseline a capture job is compared against."""
    payload = {
        "client_id": job["client_id"],
        "surface": job["surface"],
        "screen": job.get("screen"),
        "story": job.get("story"),
        "state": job["state"],
        "direction": job.get("direction"),
        "mix_ref": job.get("mix_ref"),
        "viewport": {
            "width": job["viewport"]["width"],
            "height": job["viewport"]["height"],
        },
        "fixture_version": job["fixture_version"],
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return "baseline:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class GoldenBaseline:
    """Immutable, reviewer-accepted visual baseline metadata."""

    baseline_id: str
    client_id: str
    surface: str
    state: str
    fixture_version: str
    content_hash: str
    path: str
    accepted_by: str
    accepted_at: str
    source_commit_sha: str
    viewport: dict
    screen: str | None = None
    story: str | None = None
    direction: str | None = None
    mix_ref: str | None = None
    gating: bool = True

    def __post_init__(self) -> None:
        if self.surface not in ALLOWED_SURFACES:
            raise InvalidBaselineIndex(f"unknown baseline surface: {self.surface}")
        if not self.baseline_id.startswith("baseline:"):
            raise InvalidBaselineIndex("baseline_id must be prefixed with 'baseline:'")
        for label, value in (
            ("client_id", self.client_id),
            ("state", self.state),
            ("fixture_version", self.fixture_version),
            ("content_hash", self.content_hash),
            ("path", self.path),
            ("accepted_by", self.accepted_by),
            ("accepted_at", self.accepted_at),
            ("source_commit_sha", self.source_commit_sha),
        ):
            if not isinstance(value, str) or not value.strip():
                raise InvalidBaselineIndex(f"baseline requires {label}")
        if not isinstance(self.viewport, dict) or not (
            self.viewport.get("width") and self.viewport.get("height")
        ):
            raise InvalidBaselineIndex("baseline requires a viewport")

    @classmethod
    def from_capture_job(
        cls,
        job: dict,
        *,
        content_hash: str,
        path: str,
        accepted_by: str,
        accepted_at: str,
    ) -> "GoldenBaseline":
        return cls(
            baseline_id=baseline_id(job),
            client_id=job["client_id"],
            surface=job["surface"],
            screen=job.get("screen"),
            story=job.get("story"),
            state=job["state"],
            direction=job.get("direction"),
            mix_ref=job.get("mix_ref"),
            viewport=dict(job["viewport"]),
            fixture_version=job["fixture_version"],
            source_commit_sha=job.get("source_commit_sha", ""),
            content_hash=content_hash,
            path=path,
            accepted_by=accepted_by,
            accepted_at=accepted_at,
        )

    def to_json(self) -> dict:
        return {
            "baseline_id": self.baseline_id,
            "client_id": self.client_id,
            "surface": self.surface,
            "screen": self.screen,
            "story": self.story,
            "state": self.state,
            "direction": self.direction,
            "mix_ref": self.mix_ref,
            "viewport": dict(self.viewport),
            "fixture_version": self.fixture_version,
            "source_commit_sha": self.source_commit_sha,
            "content_hash": self.content_hash,
            "path": self.path,
            "accepted_by": self.accepted_by,
            "accepted_at": self.accepted_at,
            "gating": self.gating,
        }

    @classmethod
    def from_json(cls, payload: object) -> "GoldenBaseline":
        if not isinstance(payload, dict):
            raise InvalidBaselineIndex("baseline must be a mapping")
        return cls(
            baseline_id=payload.get("baseline_id", ""),
            client_id=payload.get("client_id", ""),
            surface=payload.get("surface", ""),
            screen=payload.get("screen"),
            story=payload.get("story"),
            state=payload.get("state", ""),
            direction=payload.get("direction"),
            mix_ref=payload.get("mix_ref"),
            viewport=payload.get("viewport") or {},
            fixture_version=payload.get("fixture_version", ""),
            source_commit_sha=payload.get("source_commit_sha", ""),
            content_hash=payload.get("content_hash", ""),
            path=payload.get("path", ""),
            accepted_by=payload.get("accepted_by", ""),
            accepted_at=payload.get("accepted_at", ""),
            gating=bool(payload.get("gating", True)),
        )


@dataclass(frozen=True)
class GoldenComparison:
    """Result of comparing one capture against its governed baseline."""

    baseline_id: str
    capture_id: str
    result: str  # match | mismatch | missing_baseline
    compared_at: str
    baseline_content_hash: str | None = None
    candidate_content_hash: str | None = None
    diff_ref: str | None = None
    evidence_ref: str | None = None

    def to_json(self) -> dict:
        return {
            "baseline_id": self.baseline_id,
            "capture_id": self.capture_id,
            "result": self.result,
            "compared_at": self.compared_at,
            "baseline_content_hash": self.baseline_content_hash,
            "candidate_content_hash": self.candidate_content_hash,
            "diff_ref": self.diff_ref,
            "evidence_ref": self.evidence_ref,
        }

    @property
    def is_gating_failure(self) -> bool:
        return self.result in GATING_RESULTS


def compare_to_baseline(
    baseline: GoldenBaseline | None,
    artifact: dict,
    *,
    compared_at: str,
) -> GoldenComparison:
    """Compare a capture artifact to its baseline. Never writes anything."""
    capture_id = artifact["capture_id"]
    candidate_hash = artifact["content_hash"]
    if baseline is None:
        return GoldenComparison(
            baseline_id=baseline_id(artifact),
            capture_id=capture_id,
            result="missing_baseline",
            compared_at=compared_at,
            candidate_content_hash=candidate_hash,
            evidence_ref=artifact.get("path"),
        )
    if baseline.content_hash == candidate_hash:
        return GoldenComparison(
            baseline_id=baseline.baseline_id,
            capture_id=capture_id,
            result="match",
            compared_at=compared_at,
            baseline_content_hash=baseline.content_hash,
            candidate_content_hash=candidate_hash,
        )
    return GoldenComparison(
        baseline_id=baseline.baseline_id,
        capture_id=capture_id,
        result="mismatch",
        compared_at=compared_at,
        baseline_content_hash=baseline.content_hash,
        candidate_content_hash=candidate_hash,
        diff_ref=f"{baseline.baseline_id}.diff.png",
        evidence_ref=artifact.get("path"),
    )


def load_baseline_index(path: Path) -> dict:
    """Load and validate a governed baseline index."""
    path = Path(path)
    if not path.exists():
        return {"version": BASELINE_INDEX_VERSION, "baselines": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidBaselineIndex(f"cannot read baseline index: {error}") from error
    return validate_baseline_index(data)


def validate_baseline_index(data: object) -> dict:
    if not isinstance(data, dict):
        raise InvalidBaselineIndex("baseline index must be a mapping")
    if data.get("version") != BASELINE_INDEX_VERSION:
        raise InvalidBaselineIndex("unsupported baseline index version")
    baselines = data.get("baselines")
    if not isinstance(baselines, list):
        raise InvalidBaselineIndex("baseline index requires a baselines list")
    seen: set[str] = set()
    for entry in baselines:
        baseline = GoldenBaseline.from_json(entry)
        if baseline.baseline_id in seen:
            raise InvalidBaselineIndex(
                f"duplicate baseline id: {baseline.baseline_id}"
            )
        seen.add(baseline.baseline_id)
    return data


def find_baseline(index: dict, job: dict) -> GoldenBaseline | None:
    """Return the baseline matching *job*, or None when none is governed."""
    wanted = baseline_id(job)
    for entry in index.get("baselines", []):
        baseline = GoldenBaseline.from_json(entry)
        if baseline.baseline_id == wanted:
            return baseline
    return None


def authorize_baseline_update(actor: dict) -> None:
    """Baseline create/update is an explicit reviewer-controlled action."""
    role = actor.get("role") if isinstance(actor, dict) else None
    actor_id = actor.get("id") if isinstance(actor, dict) else None
    if role not in REVIEWER_ROLES or not actor_id:
        raise UnauthorizedBaselineUpdate(
            "baseline updates require an identified reviewer"
        )


def require_baseline(baseline: GoldenBaseline | None) -> GoldenBaseline:
    if baseline is None:
        raise GoldenBaselineMissing("no governed baseline for this capture job")
    return baseline
