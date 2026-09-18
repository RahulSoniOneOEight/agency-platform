"""Deterministic H.1 production-foundation evidence report (Milestone H.1, Task 9).

The report is the aggregated, self-verifying evidence artifact for the H.1
production foundation. It is built **only** from canonical repository artifacts:
the dev/staging/production environment configs, the provider-neutral port
interfaces, the Supabase and deterministic fake adapters, the versioned
migrations, and the committed integration-scenarios fixture. It records ids,
versions, counts, statuses, identities, and references, and it never copies an
approval, QA finding, or authorization body (R9). It contains no subjective
score.

Determinism
-----------
Every value is derived deterministically. ``report_identity`` is
``"sha256:" + sha256`` over the canonical (sorted, compact) JSON of the report
*excluding* ``report_identity`` itself, so the report is self-verifying and a
fresh build is byte-identical on every platform (LF newlines).

Authority boundary
------------------
H.1 is production implementation only. The report references the F machine
report and the G release candidate / authorization by identity and ref only, and
its ``authority_checks`` explicitly record that H.1 created no
``ProductionAuthorization`` and performed no production deployment. The
``production-foundation`` validator verifies config, migrations, report
freshness, and production-app contract evidence, but it can neither authorize
nor deploy.

Normal CI never requires production credentials or a live Supabase project: the
validator reads text only.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from tooling.production.sync_app_config import sync_app_config
from tooling.production.validate_config import (
    REQUIRED_ENVIRONMENTS,
    validate_production_config,
)
from tooling.production.validate_migrations import validate_migrations


REPORT_VERSION = 1

EVIDENCE_RELATIVE = Path("production") / "evidence"
REPORT_NAME = "h1-foundation-report.json"
FIXTURE_RELATIVE = Path("production") / "fixtures" / "integration-scenarios.json"
CONFIG_RELATIVE = Path("production") / "config"

REFERENCE_REPORT_REL = (
    Path("client-projects")
    / "reference-commerce"
    / "reference-e2e"
    / "report"
    / "reference-report.json"
)
RELEASE_CANDIDATE_REL = (
    Path("client-projects") / "reference-commerce" / "release" / "candidate.json"
)
PRODUCTION_AUTHORIZATION_REL = (
    Path("client-projects")
    / "reference-commerce"
    / "release"
    / "production-authorizations"
    / "production"
    / "authorization-v0001.json"
)

MIGRATIONS_RELATIVE = Path("supabase") / "migrations"
PORTS_RELATIVE = (
    Path("packages") / "agency_production_core" / "lib" / "src" / "ports"
)
SUPABASE_ADAPTER_RELATIVE = (
    Path("packages") / "agency_supabase_adapter" / "lib" / "src"
)
FAKE_ADAPTERS_RELATIVE = (
    Path("packages") / "agency_integration_adapters" / "lib" / "src" / "fake"
)
DETERMINISTIC_BOUNDARIES_REF = (
    Path("apps")
    / "production_app"
    / "lib"
    / "runtime"
    / "deterministic_boundaries.dart"
)

APP_CONTRACT_TESTS: tuple[str, ...] = (
    "apps/production_app/test/reference_commerce_b2c_production_path_test.dart",
    "apps/production_app/test/reference_commerce_b2b_production_path_test.dart",
    "apps/production_app/test/production_failure_states_test.dart",
)

REQUIRED_REPORT_KEYS: tuple[str, ...] = (
    "report_version",
    "client_id",
    "environments",
    "ports",
    "adapters",
    "migrations",
    "b2c_path",
    "b2b_path",
    "failure_scenarios",
    "authority_checks",
    "report_identity",
)

_PORT_DECL = re.compile(r"abstract\s+interface\s+class\s+(\w+)")
_CLASS_DECL = re.compile(r"final class (\w+)([^{]*)\{", re.DOTALL)
_MIGRATION_NAME = re.compile(r"^(?P<version>\d{12,14})_(?P<name>[a-z0-9_]+)\.sql$")
_MIGRATION_CLASS = re.compile(r"^--\s*migration-class:\s*(\S+)\s*$", re.MULTILINE)


def _canonical_json(value: Any) -> str:
    """Return the canonical compact JSON form used for every report identity."""
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    )


def _reference_hash(value: Any) -> str:
    return "sha256:" + hashlib.sha256(
        _canonical_json(value).encode("utf-8")
    ).hexdigest()


def h1_report_identity(report: Mapping[str, Any]) -> str:
    """Return the self-verifying ``sha256:`` identity of an H.1 report."""
    body = {key: value for key, value in report.items() if key != "report_identity"}
    return _reference_hash(body)


def canonical_report(report: Mapping[str, Any]) -> str:
    """Return the canonical pretty JSON byte form of an H.1 report (LF newlines)."""
    return json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _normalized_bytes(path: Path) -> bytes:
    """Read *path* with CRLF normalized to LF (platform-independent freshness)."""
    return path.read_bytes().replace(b"\r\n", b"\n")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _discover_ports(root: Path) -> list[dict[str, str]]:
    ports_dir = root / PORTS_RELATIVE
    ports: list[dict[str, str]] = []
    if not ports_dir.is_dir():
        return ports
    for path in sorted(ports_dir.glob("*.dart")):
        source = path.read_text(encoding="utf-8")
        for match in _PORT_DECL.finditer(source):
            ports.append({"name": match.group(1), "ref": _relative(root, path)})
    return sorted(ports, key=lambda entry: entry["name"])


def _discover_adapters(root: Path) -> dict[str, list[dict[str, Any]]]:
    ports = {entry["name"] for entry in _discover_ports(root)}

    def scan(directory: Path) -> list[dict[str, Any]]:
        entries: list[dict[str, Any]] = []
        if not directory.is_dir():
            return entries
        for path in sorted(directory.rglob("*.dart")):
            source = path.read_text(encoding="utf-8")
            for match in _CLASS_DECL.finditer(source):
                header = match.group(2)
                if "implements" not in header:
                    continue
                clause = header.split("implements", 1)[1]
                implemented = sorted(
                    port
                    for port in ports
                    if re.search(rf"\b{re.escape(port)}\b", clause)
                )
                if not implemented:
                    continue
                entries.append(
                    {
                        "name": match.group(1),
                        "implements": implemented,
                        "ref": _relative(root, path),
                    }
                )
        return sorted(entries, key=lambda entry: entry["name"])

    return {
        "supabase": scan(root / SUPABASE_ADAPTER_RELATIVE),
        "fake_integrations": scan(root / FAKE_ADAPTERS_RELATIVE),
        "deterministic": [
            {
                "name": "DeterministicCommerceBoundaries",
                "implements": sorted(ports),
                "ref": DETERMINISTIC_BOUNDARIES_REF.as_posix(),
            }
        ],
    }


def _discover_migrations(root: Path) -> list[dict[str, Any]]:
    migrations_dir = root / MIGRATIONS_RELATIVE
    entries: list[dict[str, Any]] = []
    if not migrations_dir.is_dir():
        return entries
    for path in sorted(migrations_dir.glob("*.sql")):
        match = _MIGRATION_NAME.match(path.name)
        if match is None:
            continue
        normalized = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        header = _MIGRATION_CLASS.search(normalized)
        entries.append(
            {
                "version": match.group("version"),
                "name": match.group("name"),
                "migration_class": header.group(1) if header else None,
                "ref": _relative(root, path),
                "identity": "sha256:"
                + hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
            }
        )
    return sorted(entries, key=lambda entry: entry["version"])


def _environments(root: Path, client_dir: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for environment in REQUIRED_ENVIRONMENTS:
        path = client_dir / CONFIG_RELATIVE / f"{environment}.json"
        payload = _load_json(path)
        entries.append(
            {
                "environment": environment,
                "ref": _relative(root, path),
                "api_base_url": payload.get("api_base_url"),
                "supabase_configured": bool(
                    str(payload.get("supabase_url") or "").strip()
                )
                and bool(str(payload.get("supabase_anon_key") or "").strip()),
                "analytics_enabled": bool(payload.get("analytics_enabled")),
                "feature_flags": dict(
                    sorted((payload.get("feature_flags") or {}).items())
                ),
                "integration_modes": dict(
                    sorted((payload.get("integration_modes") or {}).items())
                ),
                "app_version": payload.get("app_version"),
                "config_identity": _reference_hash(payload),
            }
        )
    return entries


def _authority_checks(root: Path) -> dict[str, Any]:
    f_report = _load_json(root / REFERENCE_REPORT_REL)
    candidate = _load_json(root / RELEASE_CANDIDATE_REL)
    authorization = _load_json(root / PRODUCTION_AUTHORIZATION_REL)
    return {
        "h1_creates_production_authorization": False,
        "h1_performs_production_deployment": False,
        "f_machine_report": {
            "ref": REFERENCE_REPORT_REL.as_posix(),
            "report_identity": f_report.get("report_identity"),
        },
        "g_release_candidate": {
            "ref": RELEASE_CANDIDATE_REL.as_posix(),
            "identity": _reference_hash(candidate),
        },
        "g_production_authorization": {
            "ref": PRODUCTION_AUTHORIZATION_REL.as_posix(),
            "identity": _reference_hash(authorization),
        },
    }


def build_h1_report(root: Path, client_dir: Path) -> dict[str, Any]:
    """Aggregate the deterministic H.1 production-foundation report.

    Raises ``OSError``/``ValueError`` when a canonical artifact is missing or
    malformed; the validator reports that as an error rather than masking it.
    """
    root = Path(root)
    client_dir = Path(client_dir)

    fixture = _load_json(client_dir / FIXTURE_RELATIVE)

    report: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "client_id": fixture.get("client_id") or client_dir.name,
        "environments": _environments(root, client_dir),
        "ports": _discover_ports(root),
        "adapters": _discover_adapters(root),
        "migrations": _discover_migrations(root),
        "b2c_path": fixture.get("b2c_path"),
        "b2b_path": fixture.get("b2b_path"),
        "failure_scenarios": list(fixture.get("failure_scenarios") or []),
        "authority_checks": _authority_checks(root),
    }
    report["report_identity"] = h1_report_identity(report)
    return report


def _app_contract_evidence_errors(root: Path, client_dir: Path) -> list[str]:
    errors: list[str] = []
    fixture_path = client_dir / FIXTURE_RELATIVE
    relative = _relative(root, fixture_path)
    if not fixture_path.is_file():
        errors.append(f"{relative}: missing integration-scenarios fixture")
    else:
        try:
            fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            errors.append(f"{relative}: cannot parse integration-scenarios fixture: {exc}")
        else:
            for key in ("b2c_path", "b2b_path", "failure_scenarios"):
                if not fixture.get(key):
                    errors.append(f"{relative}: missing {key}")

    for relative in APP_CONTRACT_TESTS:
        if not (root / relative).is_file():
            errors.append(f"{relative}: missing production-app contract test")
    return errors


def validate_h1_report(root: Path, client_dir: Path) -> list[str]:
    """Return deterministic, stable-sorted H.1 report errors (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)
    report_path = client_dir / EVIDENCE_RELATIVE / REPORT_NAME
    relative = _relative(root, report_path)

    if not report_path.is_file():
        return [f"{relative}: missing H.1 foundation report"]

    try:
        committed = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{relative}: cannot parse H.1 foundation report: {exc}"]

    if not isinstance(committed, dict):
        return [f"{relative}: H.1 foundation report must be a JSON object"]

    errors: list[str] = []
    missing = [key for key in REQUIRED_REPORT_KEYS if key not in committed]
    if missing:
        errors.append(f"{relative}: missing required keys: {', '.join(missing)}")
    if committed.get("report_version") != REPORT_VERSION:
        errors.append(f"{relative}: report_version must be {REPORT_VERSION}")
    if committed.get("report_identity") != h1_report_identity(committed):
        errors.append(f"{relative}: report_identity does not verify")
    if committed.get("client_id") != client_dir.name:
        errors.append(f"{relative}: client_id must be {client_dir.name!r}")

    checks = committed.get("authority_checks")
    if not isinstance(checks, Mapping):
        errors.append(f"{relative}: authority_checks must be an object")
    else:
        if checks.get("h1_creates_production_authorization") is not False:
            errors.append(f"{relative}: H.1 must not create ProductionAuthorization")
        if checks.get("h1_performs_production_deployment") is not False:
            errors.append(f"{relative}: H.1 must not deploy production")

    try:
        fresh = build_h1_report(root, client_dir)
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        errors.append(
            f"{relative}: cannot build fresh H.1 foundation report: "
            f"{type(exc).__name__}: {exc}"
        )
    else:
        if _normalized_bytes(report_path) != canonical_report(fresh).encode("utf-8"):
            errors.append(
                f"{relative}: H.1 foundation report is stale "
                "(bytes differ from a fresh build)"
            )

    return sorted(set(errors))


def validate_production_foundation(root: Path, client_dir: Path) -> list[str]:
    """Compose the stage-08 ``production-foundation`` validator.

    Verifies the client-safe environment configs, the byte-fresh app config
    assets, the versioned migrations, the production-app contract evidence, and
    the freshness/identity of the H.1 foundation report. It never creates a
    ``ProductionAuthorization`` and never deploys.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []
    errors.extend(validate_production_config(root, client_dir))
    errors.extend(sync_app_config(root, client_dir, check=True))
    errors.extend(validate_migrations(root))
    errors.extend(_app_contract_evidence_errors(root, client_dir))
    errors.extend(validate_h1_report(root, client_dir))
    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate (default) or ``--write`` the H.1 report."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    write = "--write" in arguments
    positional = [argument for argument in arguments if not argument.startswith("--")]

    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    if write:
        report = build_h1_report(root, client_dir)
        target = client_dir / EVIDENCE_RELATIVE / REPORT_NAME
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(canonical_report(report), encoding="utf-8", newline="\n")
        print(_relative(root, target))
        return 0

    errors = validate_h1_report(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
