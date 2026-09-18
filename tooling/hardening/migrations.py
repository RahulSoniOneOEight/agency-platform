"""H.2 migration readiness gate (spec section 16, plan Task 6).

Requires the exact migration-set identity bound to the frozen release
candidate, staging-apply evidence, post-apply verification, and a recovery
treatment for every ``transformative``/``destructive`` migration. It never
executes SQL and never contacts a database.

Evidence shape (JSON object)::

    {
      "migration_set_identity": "sha256:...",
      "migration_set_entries": [{"path": "...", "sha256": "sha256:..."}],
      "migration_classes": {"supabase/migrations/x.sql": "destructive"},
      "staging_apply": {"ok": true},
      "post_apply_verification": {"ok": true},
      "recovery_treatment": {
        "supabase/migrations/x.sql": {"treatment": "reverse-migration"}
      },
      "optimization_recommendations": ["..."]
    }

``migration_set_identity`` is compared with the candidate's committed
``migration_set_identity``; ``migration_set_entries`` (when supplied) must
match the candidate entries exactly. ``migration_classes`` are *unioned* with
the classes parsed from the repository migration headers (useful for staged
evidence without editing migrations), and a declared class can never downgrade
a ``transformative``/``destructive`` repository header, so a migration that
requires recovery treatment cannot escape it. Missing/invalid identity,
staging apply, post-apply verification, or recovery treatment is blocking;
optimization recommendations are advisory.
"""

from __future__ import annotations

import json
import re
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from tooling.hardening.candidate import (
    CANDIDATE_NAME,
    MIGRATIONS_RELATIVE,
    RELEASE_RELATIVE,
)
from tooling.hardening.findings import (
    load_evidence,
    make_finding,
    missing_evidence_finding,
    sort_findings,
)

AREA = "migrations"
EVIDENCE_RELATIVE = Path("production") / "evidence" / "migration-evidence.json"

TRANSFORMATIVE_CLASSES: tuple[str, ...] = ("transformative", "destructive")

_CLASS_HEADER = re.compile(r"^--\s*migration-class:\s*(\S+)\s*$", re.MULTILINE)


def _blocking(id: str, summary: str, refs: Sequence[str] = ()) -> dict[str, Any]:
    return make_finding(
        id=id,
        area=AREA,
        severity="high",
        disposition="blocking",
        status="open",
        summary=summary,
        evidence_refs=list(refs),
    )


def _load_candidate(client_dir: Path) -> Mapping[str, Any] | None:
    path = Path(client_dir) / RELEASE_RELATIVE / CANDIDATE_NAME
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, Mapping) else None


def _repo_migration_classes(root: Path) -> dict[str, str]:
    migrations_dir = Path(root) / MIGRATIONS_RELATIVE
    classes: dict[str, str] = {}
    if not migrations_dir.is_dir():
        return classes
    for path in sorted(migrations_dir.glob("*.sql")):
        text = path.read_text(encoding="utf-8", errors="replace")
        headers = _CLASS_HEADER.findall(text)
        if headers:
            classes[path.relative_to(Path(root)).as_posix()] = headers[0]
    return classes


def _has_treatment(value: object) -> bool:
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, Mapping):
        for key in ("treatment", "description", "plan", "recovery"):
            candidate = value.get(key)
            if isinstance(candidate, str) and candidate.strip():
                return True
    return False


def _slug(path: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", path.lower()).strip("-")


def evaluate_migrations(
    root: Path,
    client_dir: Path,
    evidence: Mapping[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Return deterministic, sorted migration findings for *client_dir*."""
    if evidence is None:
        evidence = load_evidence(client_dir, EVIDENCE_RELATIVE)
    if evidence is None:
        return [missing_evidence_finding(AREA, EVIDENCE_RELATIVE)]
    if not isinstance(evidence, Mapping):
        return [
            _blocking(
                "migrations-evidence-invalid",
                "migration evidence must be a mapping",
                [EVIDENCE_RELATIVE.as_posix()],
            )
        ]

    findings: list[dict[str, Any]] = []

    candidate = _load_candidate(client_dir)
    if candidate is None:
        findings.append(
            _blocking(
                "migrations-candidate-missing",
                "release candidate is missing or invalid; migration identity "
                "cannot be verified",
            )
        )
    else:
        candidate_identity = candidate.get("migration_set_identity")
        declared_identity = evidence.get("migration_set_identity")
        if declared_identity != candidate_identity:
            findings.append(
                _blocking(
                    "migrations-identity-mismatch",
                    "migration set identity does not match the release candidate",
                    [EVIDENCE_RELATIVE.as_posix()],
                )
            )
        entries = evidence.get("migration_set_entries")
        if isinstance(entries, Sequence) and not isinstance(
            entries, (str, bytes)
        ):
            if list(entries) != list(candidate.get("migration_set_entries", [])):
                findings.append(
                    _blocking(
                        "migrations-entries-mismatch",
                        "migration set entries do not match the release candidate",
                        [EVIDENCE_RELATIVE.as_posix()],
                    )
                )

    staging = evidence.get("staging_apply")
    if not (isinstance(staging, Mapping) and staging.get("ok") is True):
        findings.append(
            _blocking(
                "migrations-staging-apply",
                "staging migration application is not proven",
                [EVIDENCE_RELATIVE.as_posix()],
            )
        )

    post_apply = evidence.get("post_apply_verification")
    if not (isinstance(post_apply, Mapping) and post_apply.get("ok") is True):
        findings.append(
            _blocking(
                "migrations-post-apply-verification",
                "post-migration verification is not proven",
                [EVIDENCE_RELATIVE.as_posix()],
            )
        )

    classes = _repo_migration_classes(root)
    declared_classes = evidence.get("migration_classes")
    if isinstance(declared_classes, Mapping):
        for raw_path, raw_value in declared_classes.items():
            path = str(raw_path)
            value = str(raw_value)
            existing = classes.get(path)
            if (
                existing in TRANSFORMATIVE_CLASSES
                and value not in TRANSFORMATIVE_CLASSES
            ):
                continue
            classes[path] = value

    treatments = evidence.get("recovery_treatment")
    if not isinstance(treatments, Mapping):
        treatments = {}

    for path in sorted(classes):
        if classes[path] not in TRANSFORMATIVE_CLASSES:
            continue
        if not _has_treatment(treatments.get(path)):
            findings.append(
                _blocking(
                    f"migrations-recovery-{_slug(path)}",
                    f"{classes[path]} migration {path} has no recovery treatment",
                    [path],
                )
            )

    recommendations = evidence.get("optimization_recommendations")
    if isinstance(recommendations, Sequence) and not isinstance(
        recommendations, (str, bytes)
    ):
        for index, recommendation in enumerate(recommendations):
            if not isinstance(recommendation, str) or not recommendation:
                continue
            findings.append(
                make_finding(
                    id=f"migrations-optimization-{index}",
                    area=AREA,
                    severity="low",
                    disposition="advisory",
                    status="open",
                    summary=recommendation,
                    evidence_refs=[EVIDENCE_RELATIVE.as_posix()],
                )
            )

    return sort_findings(findings)
