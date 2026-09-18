"""H.2 exact-candidate -> G authorization bridge (Milestone H.2, Task 8).

The production release pipeline must never deploy unless the frozen H.2 candidate
matches a valid Milestone-G ``ProductionAuthorization`` exactly. This module is
the single bridge that proves that match:

1. It delegates **all** G authorization-validity semantics to the existing
   ``tooling.production_authorization.release_gate.verify_release_gate`` (no G
   comparison is duplicated, weakened, or reimplemented). G's own exceptions
   propagate unchanged.
2. It then verifies the H.2-only bindings that G does not model: the H.2
   migration-set identity, the H.1 production config identity, the H.1 report
   reference, the committed H.2 hardening report, and the committed artifact
   manifest digest.

Any H.2-specific mismatch raises :class:`H2AuthorizationBridgeError`.

Authority boundary: this module imports ``ProductionAuthorization`` only as a
type annotation and never constructs one; it never imports the G authorization
coordinator or the authorization repository's ``create`` path. H.2 cannot create
or mutate the human G authority.
"""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Any

from tooling.hardening.candidate import canonical_identity
from tooling.production.report import h1_report_identity
from tooling.production_authorization.models import (
    ProductionAuthorization,
    ReleaseCandidate,
)
from tooling.production_authorization.release_gate import verify_release_gate
from tooling.production_authorization.validity import AuthorizationEvent

from tooling.release.evidence import (
    load_artifact_manifest,
    load_h1_report,
    load_hardening_report,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
CLIENT_PROJECTS = "client-projects"
PRODUCTION_ENVIRONMENT = "production"

HARDENING_REPORT_FIELDS: tuple[str, ...] = (
    "candidate_identity",
    "artifact_digest",
    "migration_set_identity",
    "release_config_identity",
)


class H2AuthorizationBridgeError(Exception):
    """Raised when an H.2-specific candidate binding does not match.

    G authorization-validity failures are deliberately *not* wrapped: they are
    raised by the existing release gate with their own G exception types.
    """

    code = "h2_authorization_bridge_error"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message

    def __str__(self) -> str:
        return f"{type(self).__name__}({self.code}): {self.message}"


def _client_dir_for(h2_candidate: Mapping[str, Any]) -> Path:
    client_id = h2_candidate.get("client_id")
    if not isinstance(client_id, str) or not client_id:
        raise H2AuthorizationBridgeError(
            "H.2 candidate client_id is required to resolve the committed evidence"
        )
    return REPO_ROOT / CLIENT_PROJECTS / client_id


def _g_binding_errors(
    h2_candidate: Mapping[str, Any], g_candidate: ReleaseCandidate
) -> list[str]:
    errors: list[str] = []
    if h2_candidate.get("source_sha") != g_candidate.source_commit_sha:
        errors.append(
            "h2 source_sha does not match the authorized G candidate source commit SHA"
        )
    if h2_candidate.get("artifact_digest") != g_candidate.build_hash:
        errors.append(
            "h2 artifact_digest does not match the authorized G candidate build hash"
        )
    if h2_candidate.get("target_environment") != g_candidate.environment:
        errors.append(
            "h2 target_environment does not match the authorized G candidate environment"
        )
    return errors


def _migration_set_errors(h2_candidate: Mapping[str, Any]) -> list[str]:
    entries = h2_candidate.get("migration_set_entries")
    declared = h2_candidate.get("migration_set_identity")
    if not isinstance(entries, list) or not entries:
        return ["h2 migration_set_entries must be a non-empty list"]
    if declared != canonical_identity(entries):
        return [
            "h2 migration_set_identity does not match the recomputed migration "
            "set identity"
        ]
    return []


def _h1_report_errors(h2_candidate: Mapping[str, Any]) -> list[str]:
    ref = h2_candidate.get("h1_foundation_report_ref")
    if not isinstance(ref, str) or not ref:
        return ["h2 h1_foundation_report_ref is required"]
    report = load_h1_report(REPO_ROOT, ref)
    if not report:
        return [f"H.1 foundation report is missing or invalid: {ref}"]

    errors: list[str] = []
    if report.get("report_identity") != h1_report_identity(report):
        errors.append("H.1 foundation report identity does not verify")

    environments = report.get("environments")
    production = None
    if isinstance(environments, list):
        production = next(
            (
                entry
                for entry in environments
                if isinstance(entry, Mapping)
                and entry.get("environment") == PRODUCTION_ENVIRONMENT
            ),
            None,
        )
    if production is None:
        errors.append("H.1 foundation report has no production environment entry")
    elif production.get("config_identity") != h2_candidate.get(
        "release_config_identity"
    ):
        errors.append(
            "h2 release_config_identity does not match the H.1 production config "
            "identity"
        )
    return errors


def _hardening_report_errors(
    h2_candidate: Mapping[str, Any], client_dir: Path
) -> list[str]:
    report = load_hardening_report(client_dir)
    if not report:
        return ["committed H.2 hardening report is missing or invalid"]
    errors: list[str] = []
    for field in HARDENING_REPORT_FIELDS:
        if report.get(field) != h2_candidate.get(field):
            errors.append(
                f"committed H.2 hardening report {field} does not match the "
                "H.2 candidate"
            )
    return errors


def _artifact_manifest_errors(
    h2_candidate: Mapping[str, Any], client_dir: Path
) -> list[str]:
    manifest = load_artifact_manifest(client_dir)
    if not manifest:
        return ["committed artifact manifest is missing or invalid"]
    if manifest.get("artifact_digest") != h2_candidate.get("artifact_digest"):
        return [
            "artifact manifest artifact_digest does not match the H.2 candidate "
            "artifact digest"
        ]
    return []


def verify_h2_authorized_candidate(
    h2_candidate: Mapping[str, Any],
    g_candidate: ReleaseCandidate,
    authorization: ProductionAuthorization,
    invalidation_events: tuple[AuthorizationEvent, ...] = (),
) -> None:
    """Verify the H.2 candidate against the exact G authorization.

    G validity is delegated in full to the existing release gate; only the
    H.2-specific bindings are checked here. Returns ``None`` when every binding
    matches, raises :class:`H2AuthorizationBridgeError` on an H.2 mismatch, and
    lets the release gate's own exceptions propagate for G validity failures.
    """
    verify_release_gate(authorization, g_candidate, invalidation_events)

    if not isinstance(h2_candidate, Mapping):
        raise H2AuthorizationBridgeError("H.2 candidate must be a mapping")

    client_dir = _client_dir_for(h2_candidate)
    errors: list[str] = []
    errors.extend(_g_binding_errors(h2_candidate, g_candidate))
    errors.extend(_migration_set_errors(h2_candidate))
    errors.extend(_h1_report_errors(h2_candidate))
    errors.extend(_hardening_report_errors(h2_candidate, client_dir))
    errors.extend(_artifact_manifest_errors(h2_candidate, client_dir))

    if errors:
        raise H2AuthorizationBridgeError("; ".join(sorted(set(errors))))
