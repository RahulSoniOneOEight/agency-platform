"""Governed H.2 production recovery coordinator (Milestone H.2, Task 10).

A failed production release must recover through a *pre-authorized* path
(spec section 17, acceptance criteria 19-21 and 38):

- **Application rollback** may target only the previous-known-good
  artifact/deployment identified by the ReleaseRecord chain. A target artifact
  digest that differs from the previous-known-good digest is a new release
  candidate, never a rollback (acceptance criterion 21).
- **Database reversal** is permitted only when the exact migration metadata
  says ``reversible == true`` *and* the committed recovery policy allows it.
  Otherwise the decision resolves to a forward recovery migration or a manual
  halt. Blind database rollback is prohibited (acceptance criterion 19).
- **Previous-known-good application rollback** is supported only through this
  governed recovery flow (acceptance criterion 20).

The module is provider-neutral and offline. Decision logic only reads mappings;
deployment and migration mechanics sit behind narrow protocols
(:class:`DeploymentPort`, :class:`MigrationExecutor`) so tests inject fakes and
no provider SDK is imported. Nothing here creates or mutates a
``ProductionAuthorization``.

Identities
----------
``decision_identity`` and ``report_identity`` are ``"sha256:" + sha256`` over
the canonical compact JSON of the value (``json.dumps(value, sort_keys=True,
separators=(",", ":"), ensure_ascii=True)``, UTF-8) excluding the identity field
itself. This mirrors the repository canonical-hash convention, so the decision
and the report are self-verifying and deterministic.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any, Protocol

import yaml

from tooling.hardening.candidate import canonical_identity
from tooling.release.release_record import (
    load_release_record,
    release_record_identity,
)

REPORT_NAME = "recovery-report.json"
EVIDENCE_RELATIVE = Path("production") / "evidence"
HARDENING_RELATIVE = Path("production") / "hardening"
RECOVERY_POLICY_NAME = "recovery-policy.yaml"
REPORT_VERSION = 1

ACTION_APPLICATION_ROLLBACK = "application_rollback"
ACTION_DATABASE_REVERSE = "database_reverse_migration"
ACTION_FORWARD_RECOVERY = "forward_recovery_migration"
ACTION_MANUAL_HALT = "manual_halt"

ACTIONS: tuple[str, ...] = (
    ACTION_APPLICATION_ROLLBACK,
    ACTION_DATABASE_REVERSE,
    ACTION_FORWARD_RECOVERY,
    ACTION_MANUAL_HALT,
)

OUTCOMES: tuple[str, ...] = (
    "permitted",
    "denied",
    "forward_recovery_required",
    "manual_halt_required",
)

MIGRATION_ACTIONS: tuple[str, ...] = ("none", "reverse", "forward")

VERIFICATION_RESULTS: tuple[str, ...] = ("passed", "failed", "not_run")

# The committed recovery policy declares modes in kebab-case; the decision uses
# the snake_case action names above.
MODE_TO_ACTION: dict[str, str] = {
    "application-rollback": ACTION_APPLICATION_ROLLBACK,
    "database-reverse-migration": ACTION_DATABASE_REVERSE,
    "forward-recovery-migration": ACTION_FORWARD_RECOVERY,
    "manual-halt": ACTION_MANUAL_HALT,
}

# Stable reason tokens (machine-readable, never provider detail).
REASON_PREVIOUS_KNOWN_GOOD = "previous_known_good_rollback_permitted"
REASON_NEW_ARTIFACT = "new_artifact_is_new_candidate"
REASON_APPLICATION_ROLLBACK_NOT_AUTHORIZED = (
    "application_rollback_not_authorized"
)
REASON_DATABASE_REVERSE_NOT_AUTHORIZED = (
    "database_reverse_migration_not_authorized"
)
REASON_MIGRATION_NOT_REVERSIBLE = "migration_not_reversible"
REASON_FORWARD_RECOVERY_PERMITTED = "forward_recovery_permitted"
REASON_FORWARD_RECOVERY_NOT_ALLOWED = "forward_recovery_not_allowed"
REASON_MANUAL_HALT_PERMITTED = "manual_halt_always_permitted"
REASON_NO_PREVIOUS_KNOWN_GOOD = "no_previous_known_good"

FIXTURE_DEPLOYMENT_ID = "production-deploy-rollback-0001"


class DeploymentPort(Protocol):
    """Narrow provider-neutral deployment port used by recovery."""

    def rollbackToKnownGood(self, target: Mapping[str, Any]) -> Mapping[str, Any]:
        """Redeploy the exact previous-known-good artifact/deployment."""
        ...


class MigrationExecutor(Protocol):
    """Narrow provider-neutral migration executor used by recovery."""

    def applyForwardMigration(self, migration: Any) -> Mapping[str, Any]:
        """Apply a forward recovery migration."""
        ...

    def reverseMigration(self, migration: Any) -> Mapping[str, Any]:
        """Apply the exact reverse of a reversible migration."""
        ...


class RecoveryReport(dict):
    """An immutable recovery report.

    A ``dict`` subclass (so it is JSON-serializable and satisfies the
    ``-> dict[str, Any]`` interface) whose mutating methods are disabled. The
    canonical ``report_identity`` makes any tampering detectable regardless.
    """

    def _immutable(self, *args: Any, **kwargs: Any) -> None:
        raise TypeError("RecoveryReport is immutable")

    __setitem__ = _immutable
    __delitem__ = _immutable
    __ior__ = _immutable
    clear = _immutable
    pop = _immutable
    popitem = _immutable
    setdefault = _immutable
    update = _immutable


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _text(value: Any) -> str | None:
    return value if isinstance(value, str) and value else None


def _as_mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return []
    return [item for item in value if isinstance(item, str) and item]


def _normalize_action(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    candidate = value.strip().lower()
    if candidate in ACTIONS:
        return candidate
    if candidate in MODE_TO_ACTION:
        return MODE_TO_ACTION[candidate]
    return None


def _policy_modes(policy: Mapping[str, Any]) -> set[str]:
    modes = policy.get("modes")
    if not isinstance(modes, Sequence) or isinstance(modes, (str, bytes)):
        return set()
    names: set[str] = set()
    for entry in modes:
        if isinstance(entry, str):
            names.add(entry)
        elif isinstance(entry, Mapping) and isinstance(entry.get("name"), str):
            names.add(entry["name"])
    return names


def _policy_view(policy: Mapping[str, Any]) -> dict[str, Any]:
    """Normalize the committed recovery policy into decision gates.

    The committed policy is a mapping whose ``modes`` list is authoritative:
    a mode is only available when it is declared, and the per-section flags
    (``previous_known_good_only``, ``requires_reversible_flag``,
    ``blind_rollback_prohibited``, ``new_artifact_is_new_candidate``) may only
    tighten, never loosen, that gate.
    """
    policy = _as_mapping(policy)
    allowed = {
        MODE_TO_ACTION[mode]
        for mode in _policy_modes(policy)
        if mode in MODE_TO_ACTION
    }
    application = _as_mapping(policy.get("application_rollback"))
    database = _as_mapping(policy.get("database_reversal"))
    return {
        "allowed_modes": allowed,
        "allow_application_rollback": (
            ACTION_APPLICATION_ROLLBACK in allowed
            and application.get("previous_known_good_only", True) is not False
        ),
        "allow_database_reverse": (
            ACTION_DATABASE_REVERSE in allowed
            and database.get("requires_reversible_flag", True) is not False
            and database.get("blind_rollback_prohibited", True) is not False
        ),
        "forward_recovery_required": ACTION_FORWARD_RECOVERY in allowed,
        "new_artifact_is_new_candidate": (
            policy.get("new_artifact_is_new_candidate", True) is not False
        ),
    }


def _request_view(release_record: Mapping[str, Any]) -> dict[str, Any]:
    """Read the requested recovery from the failed release mapping.

    The failed release may carry a nested ``recovery`` block (the recovery
    request) and/or flat keys. Both are accepted so a plain ReleaseRecord works
    (defaulting to a previous-known-good application rollback) and a recovery
    request can name an explicit action, target, and migration metadata.
    """
    request = _as_mapping(release_record.get("recovery"))

    def pick(*keys: str) -> Any:
        for key in keys:
            if key in request:
                return request[key]
        for key in keys:
            if key in release_record:
                return release_record[key]
        return None

    return {
        "action": pick("action", "recovery_action"),
        "target_artifact_digest": pick(
            "target_artifact_digest", "target_digest"
        ),
        "migration_path": pick("migration_path"),
        "migration_reversible": pick("migration_reversible"),
        "migration_metadata": pick("migration_metadata"),
    }


def _migration_reversible(
    release_record: Mapping[str, Any], request: Mapping[str, Any]
) -> bool:
    """Whether the *exact* migration metadata explicitly marks reversal safe.

    An explicit ``migration_reversible`` boolean wins. Otherwise the
    ``migration_metadata`` mapping must explicitly mark ``reversible: true``
    for the named migration, or for every migration in the release set. Missing
    or ambiguous metadata is *not* reversible — blind rollback is prohibited.
    """
    explicit = request.get("migration_reversible")
    if isinstance(explicit, bool):
        return explicit

    metadata = _as_mapping(request.get("migration_metadata"))
    if not metadata:
        return False

    def entry_reversible(entry: Any) -> bool:
        return isinstance(entry, Mapping) and entry.get("reversible") is True

    path = _text(request.get("migration_path"))
    if path:
        return entry_reversible(metadata.get(path))

    migration_set = _string_list(release_record.get("migration_set"))
    if not migration_set:
        return False
    return all(entry_reversible(metadata.get(migration)) for migration in migration_set)


def _decision(
    *,
    action: str,
    outcome: str,
    reason: str,
    failed_release_id: str,
    previous_known_good_release_id: str | None,
    target_artifact_digest: str | None,
    migration_action: str,
    migration_path: str | None = None,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "action": action,
        "outcome": outcome,
        "reason": reason,
        "permitted": outcome == "permitted",
        "failed_release_id": failed_release_id,
        "previous_known_good_release_id": previous_known_good_release_id,
        "target_artifact_digest": target_artifact_digest,
        "migration_action": migration_action,
        "migration_path": migration_path,
    }
    body["decision_identity"] = canonical_identity(body)
    return body


def plan_recovery(
    release_record: Mapping[str, Any],
    recovery_policy: Mapping[str, Any],
    previous_known_good: Mapping[str, Any] | None,
) -> dict[str, Any]:
    """Return the deterministic, governed recovery decision for a failed release.

    ``release_record`` is the failed release (optionally carrying a ``recovery``
    request block); ``recovery_policy`` is the parsed committed
    ``recovery-policy.yaml``; ``previous_known_good`` is the previous-known-good
    ReleaseRecord (the only authorized rollback target).

    The returned mapping carries ``action``, ``outcome``, ``reason``,
    ``permitted``, ``previous_known_good_release_id``,
    ``target_artifact_digest``, ``migration_action``, ``failed_release_id`` and
    a self-verifying ``decision_identity``.
    """
    release_record = _as_mapping(release_record)
    policy = _policy_view(recovery_policy)
    known_good = _as_mapping(previous_known_good)

    failed_release_id = _text(release_record.get("release_id")) or "unknown-release"
    authorized_digest = _text(known_good.get("artifact_digest"))
    known_good_id = _text(known_good.get("release_id")) or _text(
        release_record.get("previous_known_good_release_id")
    )

    request = _request_view(release_record)
    requested = _normalize_action(request.get("action"))
    if requested is None:
        requested = (
            ACTION_APPLICATION_ROLLBACK if known_good else ACTION_MANUAL_HALT
        )

    target_digest = _text(request.get("target_artifact_digest"))
    if target_digest is None:
        target_digest = authorized_digest
    migration_path = _text(request.get("migration_path"))

    def resolve_forward_or_halt(base_reason: str) -> dict[str, Any]:
        if policy["forward_recovery_required"]:
            return _decision(
                action=ACTION_FORWARD_RECOVERY,
                outcome="forward_recovery_required",
                reason=base_reason,
                failed_release_id=failed_release_id,
                previous_known_good_release_id=known_good_id,
                target_artifact_digest=target_digest,
                migration_action="forward",
                migration_path=migration_path,
            )
        return _decision(
            action=ACTION_MANUAL_HALT,
            outcome="manual_halt_required",
            reason=base_reason,
            failed_release_id=failed_release_id,
            previous_known_good_release_id=known_good_id,
            target_artifact_digest=target_digest,
            migration_action="none",
        )

    if requested == ACTION_APPLICATION_ROLLBACK:
        if not policy["allow_application_rollback"]:
            return resolve_forward_or_halt(
                REASON_APPLICATION_ROLLBACK_NOT_AUTHORIZED
            )
        if authorized_digest is None:
            return resolve_forward_or_halt(REASON_NO_PREVIOUS_KNOWN_GOOD)
        if target_digest != authorized_digest:
            return _decision(
                action=ACTION_APPLICATION_ROLLBACK,
                outcome="denied",
                reason=REASON_NEW_ARTIFACT,
                failed_release_id=failed_release_id,
                previous_known_good_release_id=known_good_id,
                target_artifact_digest=target_digest,
                migration_action="none",
            )
        return _decision(
            action=ACTION_APPLICATION_ROLLBACK,
            outcome="permitted",
            reason=REASON_PREVIOUS_KNOWN_GOOD,
            failed_release_id=failed_release_id,
            previous_known_good_release_id=known_good_id,
            target_artifact_digest=target_digest,
            migration_action="none",
        )

    if requested == ACTION_DATABASE_REVERSE:
        if not policy["allow_database_reverse"]:
            return resolve_forward_or_halt(
                REASON_DATABASE_REVERSE_NOT_AUTHORIZED
            )
        if not _migration_reversible(release_record, request):
            return resolve_forward_or_halt(REASON_MIGRATION_NOT_REVERSIBLE)
        return _decision(
            action=ACTION_DATABASE_REVERSE,
            outcome="permitted",
            reason="reversible_migration_reverse_permitted",
            failed_release_id=failed_release_id,
            previous_known_good_release_id=known_good_id,
            target_artifact_digest=target_digest,
            migration_action="reverse",
            migration_path=migration_path,
        )

    if requested == ACTION_FORWARD_RECOVERY:
        if not policy["forward_recovery_required"]:
            return _decision(
                action=ACTION_MANUAL_HALT,
                outcome="manual_halt_required",
                reason=REASON_FORWARD_RECOVERY_NOT_ALLOWED,
                failed_release_id=failed_release_id,
                previous_known_good_release_id=known_good_id,
                target_artifact_digest=target_digest,
                migration_action="none",
            )
        return _decision(
            action=ACTION_FORWARD_RECOVERY,
            outcome="permitted",
            reason=REASON_FORWARD_RECOVERY_PERMITTED,
            failed_release_id=failed_release_id,
            previous_known_good_release_id=known_good_id,
            target_artifact_digest=target_digest,
            migration_action="forward",
            migration_path=migration_path,
        )

    # Manual halt: always permitted, executes nothing.
    return _decision(
        action=ACTION_MANUAL_HALT,
        outcome="permitted",
        reason=REASON_MANUAL_HALT_PERMITTED,
        failed_release_id=failed_release_id,
        previous_known_good_release_id=known_good_id,
        target_artifact_digest=target_digest,
        migration_action="none",
    )


def _normalize_result(result: Any, **extra: Any) -> dict[str, Any]:
    mapping = _as_mapping(result)
    normalized: dict[str, Any] = {
        "attempted": True,
        "ok": mapping.get("ok") is True,
    }
    for key, value in extra.items():
        normalized[key] = value
    deployment_id = mapping.get("deployment_id") or mapping.get("id")
    if deployment_id is not None:
        normalized["deployment_id"] = deployment_id
    return normalized


def recovery_report_identity(report: Mapping[str, Any]) -> str:
    """Return the canonical identity over the report excluding itself."""
    body = {
        key: value for key, value in report.items() if key != "report_identity"
    }
    return canonical_identity(body)


def decision_identity(decision: Mapping[str, Any]) -> str:
    """Return the canonical identity over the decision excluding itself."""
    body = {
        key: value
        for key, value in decision.items()
        if key != "decision_identity"
    }
    return canonical_identity(body)


def execute_recovery(
    decision: Mapping[str, Any],
    deployment_port: Any,
    migration_executor: Any,
) -> dict[str, Any]:
    """Execute a governed recovery decision and return an immutable report.

    Application rollback calls ``deployment_port.rollbackToKnownGood`` and only
    when the decision permits it. Database reversal calls the migration
    executor's reverse path only when the decision permits it — otherwise no
    reverse SQL is ever executed. Forward recovery calls the forward migration
    executor. Manual halt executes nothing.
    """
    decision = _as_mapping(decision)
    action = decision.get("action")
    permitted = decision.get("permitted") is True
    target_digest = _text(decision.get("target_artifact_digest"))
    known_good_id = _text(decision.get("previous_known_good_release_id"))

    deployment_result: dict[str, Any] = {"attempted": False, "ok": False}
    migration_result: dict[str, Any] = {"attempted": False, "ok": False}

    if action == ACTION_APPLICATION_ROLLBACK and permitted:
        target = {
            "release_id": known_good_id,
            "artifact_digest": target_digest,
            "action": ACTION_APPLICATION_ROLLBACK,
        }
        raw = deployment_port.rollbackToKnownGood(target)
        deployment_result = _normalize_result(
            raw,
            target_release_id=known_good_id,
            target_artifact_digest=target_digest,
        )
    elif action == ACTION_DATABASE_REVERSE and permitted:
        migration = {
            "path": _text(decision.get("migration_path")),
            "migration_action": "reverse",
        }
        raw = migration_executor.reverseMigration(migration)
        migration_result = _normalize_result(
            raw, direction="reverse", migration=migration
        )
    elif action == ACTION_FORWARD_RECOVERY:
        migration = {
            "path": _text(decision.get("migration_path")),
            "migration_action": "forward",
        }
        raw = migration_executor.applyForwardMigration(migration)
        migration_result = _normalize_result(
            raw, direction="forward", migration=migration
        )

    if deployment_result["attempted"]:
        verification_result = "passed" if deployment_result["ok"] else "failed"
    elif migration_result["attempted"]:
        verification_result = "passed" if migration_result["ok"] else "failed"
    else:
        verification_result = "not_run"

    body: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "fixture_mode": False,
        "failed_release_id": decision.get("failed_release_id"),
        "reason": decision.get("reason"),
        "action": action,
        "outcome": decision.get("outcome"),
        "permitted": permitted,
        "previous_known_good_release_id": known_good_id,
        "target_artifact_digest": target_digest,
        "migration_action": decision.get("migration_action"),
        "decision": dict(decision),
        "deployment_result": deployment_result,
        "migration_result": migration_result,
        "verification_result": verification_result,
    }
    body["report_identity"] = canonical_identity(body)
    return RecoveryReport(body)


def recovery_report_path(client_dir: Path) -> Path:
    return Path(client_dir) / EVIDENCE_RELATIVE / REPORT_NAME


def recovery_policy_path(client_dir: Path) -> Path:
    return Path(client_dir) / HARDENING_RELATIVE / RECOVERY_POLICY_NAME


def load_recovery_policy(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed recovery policy mapping, or ``{}`` when invalid."""
    path = recovery_policy_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, yaml.YAMLError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def load_recovery_report(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed recovery report, or ``{}`` when absent/invalid."""
    path = recovery_report_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def write_recovery_report(
    root: Path, client_dir: Path, report: Mapping[str, Any]
) -> Path:
    path = recovery_report_path(client_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return path


def _failed_release_snapshot(known_good: Mapping[str, Any]) -> dict[str, Any]:
    """Derive the deterministic failed-release reference from the known good.

    The committed ReleaseRecord is the real healthy previous-known-good. The
    reference failure is a self-verifying synthetic ReleaseRecord whose
    ``previous_known_good_release_id`` points at it and whose artifact digest is
    a *new* candidate digest (the failed release is not the known good).
    """
    failed = dict(known_good)
    failed["release_id"] = f"{known_good.get('release_id')}-recovery-failure"
    failed["artifact_digest"] = canonical_identity(
        {"failed_release_of": known_good.get("release_id")}
    )
    failed["release_status"] = "failed"
    failed["incident_or_advisory_refs"] = ["telemetry_health_failed"]
    failed["rollback_or_recovery_ref"] = EVIDENCE_RELATIVE.joinpath(
        REPORT_NAME
    ).as_posix()
    failed["previous_known_good_release_id"] = known_good.get("release_id")
    failed["release_identity"] = release_record_identity(failed)
    return failed


def build_reference_recovery_report(
    root: Path, client_dir: Path
) -> dict[str, Any]:
    """Build the deterministic reference recovery report (fixture mode).

    Exercises a governed application rollback to the committed
    previous-known-good release. The database migrations are explicitly *not*
    reversible in the reference metadata, and the selected action is an
    application rollback, so the report never implies a blind database rollback.
    """
    root = Path(root)
    client_dir = Path(client_dir)

    known_good = load_release_record(client_dir)
    if not known_good:
        raise ValueError(
            "committed release record is required as the previous-known-good"
        )
    policy = load_recovery_policy(client_dir)
    if not policy:
        raise ValueError("committed recovery policy is missing or invalid")

    failed = _failed_release_snapshot(known_good)
    request = {
        "action": ACTION_APPLICATION_ROLLBACK,
        "target_artifact_digest": known_good.get("artifact_digest"),
        "migration_path": None,
        "migration_metadata": {
            path: {"reversible": False}
            for path in _string_list(failed.get("migration_set"))
        },
    }
    plan_input = dict(failed)
    plan_input["recovery"] = request
    decision = plan_recovery(plan_input, policy, known_good)

    deployment_port = _FixtureDeploymentPort()
    migration_executor = _FixtureMigrationExecutor()
    report = execute_recovery(decision, deployment_port, migration_executor)

    body: dict[str, Any] = dict(report)
    body.update(
        {
            "fixture_mode": True,
            "failed_release": failed,
            "previous_known_good": known_good,
            "request": request,
            "policy_ref": HARDENING_RELATIVE.joinpath(
                RECOVERY_POLICY_NAME
            ).as_posix(),
            "deployment_port": deployment_port.name,
            "migration_executor": migration_executor.name,
        }
    )
    body["report_identity"] = recovery_report_identity(body)
    return body


class _FixtureDeploymentPort:
    """Deterministic offline deployment port for the reference fixture."""

    name = "fixture"

    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []

    def rollbackToKnownGood(
        self, target: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        self.calls.append(dict(target))
        return {
            "ok": True,
            "deployment_id": FIXTURE_DEPLOYMENT_ID,
            "artifact_digest": target.get("artifact_digest"),
        }


class _FixtureMigrationExecutor:
    """Deterministic offline migration executor for the reference fixture."""

    name = "fixture"

    def __init__(self) -> None:
        self.forward_calls: list[Any] = []
        self.reverse_calls: list[Any] = []

    def applyForwardMigration(self, migration: Any) -> Mapping[str, Any]:
        self.forward_calls.append(migration)
        return {"ok": True, "direction": "forward"}

    def reverseMigration(self, migration: Any) -> Mapping[str, Any]:
        self.reverse_calls.append(migration)
        return {"ok": True, "direction": "reverse"}


def _snapshot_errors(
    label: str, snapshot: Any, *, expected_status: str
) -> list[str]:
    errors: list[str] = []
    if not isinstance(snapshot, Mapping):
        return [f"{label}: must be a ReleaseRecord object"]
    declared = snapshot.get("release_identity")
    if not isinstance(declared, str) or not declared:
        errors.append(f"{label}: release_identity is missing")
    elif declared != release_record_identity(snapshot):
        errors.append(f"{label}: release_identity does not verify")
    if snapshot.get("release_status") != expected_status:
        errors.append(
            f"{label}: release_status must be {expected_status!r}"
        )
    if not _text(snapshot.get("release_id")):
        errors.append(f"{label}: release_id is missing")
    return errors


def validate_recovery(root: Path, client_dir: Path) -> list[str]:
    """Validate the committed recovery report and its governed bindings.

    Returns stable sorted errors; ``[]`` means the report exists, parses,
    self-verifies its identity, embeds a self-verifying failed ReleaseRecord
    whose previous-known-good is the committed ReleaseRecord, and records the
    exact decision re-derived from the committed recovery policy.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    report_path = recovery_report_path(client_dir)
    relative = _relative(root, report_path)

    if not report_path.is_file():
        return [f"{relative}: missing recovery report"]
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{relative}: cannot parse recovery report: {exc}"]
    if not isinstance(report, Mapping):
        return [f"{relative}: recovery report must be a JSON object"]

    errors: list[str] = []

    if report.get("report_version") != REPORT_VERSION:
        errors.append(
            f"{relative}: report_version must be {REPORT_VERSION}"
        )
    if report.get("report_identity") != recovery_report_identity(report):
        errors.append(f"{relative}: report_identity does not verify")

    failed = report.get("failed_release")
    known_good = report.get("previous_known_good")
    errors.extend(
        f"{relative}: {error}"
        for error in _snapshot_errors(
            "failed_release", failed, expected_status="failed"
        )
    )
    errors.extend(
        f"{relative}: {error}"
        for error in _snapshot_errors(
            "previous_known_good", known_good, expected_status="healthy"
        )
    )

    committed = load_release_record(client_dir)
    if not committed:
        errors.append(
            f"{relative}: committed release record is missing or invalid"
        )
    elif isinstance(known_good, Mapping):
        if known_good.get("release_id") != committed.get("release_id"):
            errors.append(
                f"{relative}: previous_known_good release_id does not match the "
                "committed release record"
            )
        if known_good.get("artifact_digest") != committed.get("artifact_digest"):
            errors.append(
                f"{relative}: previous_known_good artifact_digest does not match "
                "the committed release record"
            )

    if isinstance(failed, Mapping) and isinstance(known_good, Mapping):
        if failed.get("previous_known_good_release_id") != known_good.get(
            "release_id"
        ):
            errors.append(
                f"{relative}: failed_release previous_known_good_release_id does "
                "not reference the previous-known-good release"
            )

    decision = report.get("decision")
    if not isinstance(decision, Mapping):
        errors.append(f"{relative}: decision must be a JSON object")
    else:
        if decision.get("decision_identity") != decision_identity(decision):
            errors.append(f"{relative}: decision_identity does not verify")
        if decision.get("permitted") != (
            decision.get("outcome") == "permitted"
        ):
            errors.append(
                f"{relative}: decision permitted must match its outcome"
            )
        if decision.get("action") not in ACTIONS:
            errors.append(
                f"{relative}: decision action must be one of {list(ACTIONS)}"
            )
        if decision.get("outcome") not in OUTCOMES:
            errors.append(
                f"{relative}: decision outcome must be one of {list(OUTCOMES)}"
            )
        if decision.get("migration_action") not in MIGRATION_ACTIONS:
            errors.append(
                f"{relative}: decision migration_action must be one of "
                f"{list(MIGRATION_ACTIONS)}"
            )
        for field in (
            "failed_release_id",
            "reason",
            "action",
            "outcome",
            "previous_known_good_release_id",
            "target_artifact_digest",
            "migration_action",
        ):
            if report.get(field) != decision.get(field):
                errors.append(
                    f"{relative}: {field} does not match the recorded decision"
                )

    if report.get("verification_result") not in VERIFICATION_RESULTS:
        errors.append(
            f"{relative}: verification_result must be one of "
            f"{list(VERIFICATION_RESULTS)}"
        )

    policy = load_recovery_policy(client_dir)
    if not policy:
        errors.append(
            f"{relative}: committed recovery policy is missing or invalid"
        )
    elif isinstance(failed, Mapping) and isinstance(decision, Mapping):
        plan_input = dict(failed)
        plan_input["recovery"] = report.get("request")
        rederived = plan_recovery(plan_input, policy, known_good)
        if rederived != decision:
            errors.append(
                f"{relative}: recorded decision does not match the governed "
                "decision re-derived from the committed recovery policy"
            )

    deployment_result = report.get("deployment_result")
    migration_result = report.get("migration_result")
    if not isinstance(deployment_result, Mapping):
        errors.append(f"{relative}: deployment_result must be an object")
    if not isinstance(migration_result, Mapping):
        errors.append(f"{relative}: migration_result must be an object")
    if isinstance(decision, Mapping):
        reverse_executed = (
            isinstance(migration_result, Mapping)
            and migration_result.get("direction") == "reverse"
        )
        if reverse_executed and not (
            decision.get("action") == ACTION_DATABASE_REVERSE
            and decision.get("permitted") is True
        ):
            errors.append(
                f"{relative}: reverse migration was executed without a "
                "permitted reversible database reversal (blind rollback "
                "prohibited)"
            )
        if decision.get("action") == ACTION_MANUAL_HALT:
            if isinstance(deployment_result, Mapping) and deployment_result.get(
                "attempted"
            ):
                errors.append(
                    f"{relative}: manual halt must not execute a deployment"
                )
            if isinstance(migration_result, Mapping) and migration_result.get(
                "attempted"
            ):
                errors.append(
                    f"{relative}: manual halt must not execute a migration"
                )

    return sorted(set(errors))


def _parse_arguments(arguments: list[str]) -> tuple[bool, list[str]]:
    write = False
    positional: list[str] = []
    for argument in arguments:
        if argument == "--write":
            write = True
        elif argument.startswith("--"):
            raise SystemExit(f"unknown option: {argument}")
        else:
            positional.append(argument)
    return write, positional


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate (default) or ``--write`` the recovery report.

    ``--write`` deterministically regenerates the committed reference recovery
    report from the committed release record and recovery policy. It never
    deploys anything and never contacts a provider.
    """
    arguments = list(sys.argv[1:] if argv is None else argv)
    write, positional = _parse_arguments(arguments)
    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    if write:
        report = build_reference_recovery_report(root, client_dir)
        path = write_recovery_report(root, client_dir, report)
        print(_relative(root, path))
        return 0

    errors = validate_recovery(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
