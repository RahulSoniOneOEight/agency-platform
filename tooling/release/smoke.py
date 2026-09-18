"""H.2 production smoke (Milestone H.2, Task 9; spec sections 17 and 19, Gate 3).

Gate 3 runs against the exact production deployment *after* the human G
authorization. It is intentionally small and side-effect controlled (spec section
19, acceptance criterion 32): it proves the deployment/version identity, the app
shell, an auth/session health check using a designated synthetic release-check
identity, a catalog/inventory read, and a permission-denied negative check -- and
it never creates an uncontrolled production order or payment side effect.

Safety contract
---------------
A smoke runner is any callable ``runner(check, context) -> mapping`` returning
``{"passed": bool, "detail": str, "mutations": [operation, ...]}``. A runner that
performs an order/payment mutation must declare it in ``mutations``. Any declared
mutation that is not explicitly allow-listed by the deployment's
``sandbox_safe_mutations`` is reported as an *uncontrolled mutation*, fails the
``no-uncontrolled-mutation`` check, and clears ``low_risk``. The default
:class:`FixtureProductionSmokeRunner` performs no mutation at all; the live
:class:`HttpProductionSmokeRunner` only issues read/negative GETs.

The report is self-verifying: ``report_identity`` is the canonical identity over
the report excluding ``report_identity`` itself. The module is pure and offline in
its default (fixture) mode.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from tooling.hardening.candidate import (
    CANDIDATE_NAME,
    RELEASE_RELATIVE,
    canonical_identity,
)

REPORT_VERSION = 1
ENVIRONMENT = "production"
SMOKE_REPORT_NAME = "production-smoke-report.json"
EVIDENCE_RELATIVE = Path("production") / "evidence"

SYNTHETIC_RELEASE_CHECK_IDENTITY = "release-check-synthetic"
MUTATION_SANDBOX_KEY = "sandbox_safe_mutations"

# Ordered runner-invoked checks. Every one is read-only/negative.
CHECK_DEFINITIONS: tuple[dict[str, Any], ...] = (
    {"id": "release-identity", "mutation": False},
    {"id": "app-shell", "mutation": False},
    {"id": "auth-session", "mutation": False},
    {"id": "catalog-inventory-read", "mutation": False},
    {"id": "permission-denied", "mutation": False},
)

# Derived safety check, appended after the runner checks.
MUTATION_CHECK_ID = "no-uncontrolled-mutation"

CHECK_IDS: tuple[str, ...] = tuple(
    definition["id"] for definition in CHECK_DEFINITIONS
) + (MUTATION_CHECK_ID,)

# Deterministic committed-fixture production deployment. H.2 never commits a
# production deployment *artifact* (that would claim a deployment authority H.2
# does not own); the reference proof synthesizes this exact deployment binding.
FIXTURE_DEPLOYMENT_ID = "production-deploy-0001"
FIXTURE_DEPLOYMENT_URL = "https://reference-commerce.example"
FIXTURE_DEPLOYMENT_PROVIDER = "cloudflare-pages"
FIXTURE_STARTED_AT = "2026-09-18T10:04:00.000Z"
FIXTURE_COMPLETED_AT = "2026-09-18T10:10:00.000Z"


def _relative(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _canonical_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(value), encoding="utf-8", newline="\n")


def load_candidate(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed release candidate, or ``{}`` when absent/invalid."""
    path = Path(client_dir) / RELEASE_RELATIVE / CANDIDATE_NAME
    if not path.is_file():
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def production_smoke_report_identity(report: Mapping[str, Any]) -> str:
    """Return the canonical identity of *report* excluding ``report_identity``."""
    body = {key: value for key, value in report.items() if key != "report_identity"}
    return canonical_identity(body)


def build_fixture_production_deployment(
    candidate: Mapping[str, Any],
) -> dict[str, Any]:
    """Return the deterministic production deployment bound to *candidate*."""
    return {
        "deployment_id": FIXTURE_DEPLOYMENT_ID,
        "environment": ENVIRONMENT,
        "provider": FIXTURE_DEPLOYMENT_PROVIDER,
        "status": "succeeded",
        "artifact_digest": candidate.get("artifact_digest"),
        "build_version": candidate.get("build_version"),
        "candidate_identity": candidate.get("candidate_identity"),
        "url": FIXTURE_DEPLOYMENT_URL,
        "started_at": FIXTURE_STARTED_AT,
        "completed_at": FIXTURE_COMPLETED_AT,
    }


def _sandbox_safe_mutations(deployment: Mapping[str, Any]) -> frozenset[str]:
    value = deployment.get(MUTATION_SANDBOX_KEY)
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return frozenset()
    return frozenset(item for item in value if isinstance(item, str) and item)


def _normalized_mutations(value: Any) -> list[str]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return []
    return [item for item in value if isinstance(item, str) and item]


def _release_identity_ok(context: Mapping[str, Any]) -> bool:
    deployment = context.get("deployment") or {}
    candidate = context.get("candidate") or {}
    if not isinstance(deployment, Mapping) or not isinstance(candidate, Mapping):
        return False
    return (
        deployment.get("environment") == ENVIRONMENT
        and deployment.get("status") == "succeeded"
        and deployment.get("artifact_digest") == candidate.get("artifact_digest")
        and deployment.get("build_version") == candidate.get("build_version")
    )


class FixtureProductionSmokeRunner:
    """Deterministic offline runner: passes every check, performs no mutation."""

    def __call__(
        self, check: Mapping[str, Any], context: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        if check.get("id") == "release-identity" and not _release_identity_ok(context):
            return {
                "passed": False,
                "detail": "production deployment identity does not match the candidate",
                "mutations": [],
            }
        return {"passed": True, "detail": "fixture", "mutations": []}


class HttpProductionSmokeRunner:
    """Live network seam used by the production workflow against the real URL.

    Only read/negative GETs are issued; the runner never calls an order/payment
    mutation endpoint. The auth/session check uses the designated synthetic
    release-check identity header.
    """

    def __init__(
        self,
        timeout: float = 15.0,
        release_check_identity: str = SYNTHETIC_RELEASE_CHECK_IDENTITY,
    ) -> None:
        self.timeout = timeout
        self.release_check_identity = release_check_identity

    def _fetch(
        self, url: str, headers: Mapping[str, str] | None = None
    ) -> tuple[bool, str, str]:
        import urllib.error
        import urllib.request

        request = urllib.request.Request(url, headers=dict(headers or {}))
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                status = getattr(response, "status", 200)
                ok = 200 <= int(status) < 300
                body = ""
                if ok:
                    try:
                        body = response.read().decode("utf-8", errors="replace")
                    except (OSError, ValueError):  # pragma: no cover - live only
                        body = ""
                return ok, str(status), body
        except urllib.error.HTTPError as exc:  # pragma: no cover - live only
            return False, str(exc.code), ""
        except (urllib.error.URLError, OSError, ValueError) as exc:  # pragma: no cover
            return False, type(exc).__name__, ""

    def __call__(
        self, check: Mapping[str, Any], context: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        base_url = context.get("base_url")
        if not isinstance(base_url, str) or not base_url:
            return {"passed": False, "detail": "missing deployment url", "mutations": []}
        base = base_url.rstrip("/")
        check_id = check.get("id")

        if check_id == "release-identity":
            ok, status, body = self._fetch(base + "/version.json")
            if not ok:
                return {
                    "passed": False,
                    "detail": f"version marker unreachable ({status})",
                    "mutations": [],
                }
            try:
                marker = json.loads(body)
            except (TypeError, ValueError):
                return {
                    "passed": False,
                    "detail": "version marker is not JSON",
                    "mutations": [],
                }
            actual = None
            if isinstance(marker, Mapping):
                actual = marker.get("build_version", marker.get("version"))
            expected = (context.get("candidate") or {}).get("build_version")
            passed = actual == expected
            return {
                "passed": passed,
                "detail": expected if passed else f"build version mismatch: {actual!r}",
                "mutations": [],
            }

        if check_id == "app-shell":
            ok, status, _ = self._fetch(base)
            return {"passed": ok, "detail": f"app shell {status}", "mutations": []}

        if check_id == "auth-session":
            ok, status, _ = self._fetch(
                base + "/api/session",
                {"X-Release-Check-Identity": self.release_check_identity},
            )
            return {"passed": ok, "detail": f"session {status}", "mutations": []}

        if check_id == "catalog-inventory-read":
            ok, status, _ = self._fetch(base + "/api/catalog")
            return {"passed": ok, "detail": f"catalog {status}", "mutations": []}

        if check_id == "permission-denied":
            _ok, status, _ = self._fetch(base + "/api/admin")
            denied = status in ("401", "403")
            return {"passed": denied, "detail": f"admin {status}", "mutations": []}

        return {"passed": False, "detail": "unknown check", "mutations": []}


def run_production_smoke(
    root: Path,
    client_dir: Path,
    deployment: Mapping[str, Any],
    http: Any | None = None,
) -> dict[str, Any]:
    """Return the deterministic low-risk production smoke report.

    ``http`` is the injectable runner seam; when omitted the offline fixture
    runner is used. Any order/payment mutation declared by the runner that is not
    allow-listed by the deployment's ``sandbox_safe_mutations`` becomes an
    uncontrolled mutation and fails the safety check.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    deployment = deployment if isinstance(deployment, Mapping) else {}
    candidate = load_candidate(client_dir)

    runner = http if callable(http) else FixtureProductionSmokeRunner()
    sandbox_safe = _sandbox_safe_mutations(deployment)
    context: dict[str, Any] = {
        "base_url": deployment.get("url"),
        "candidate": candidate,
        "deployment": deployment,
        "candidate_identity": candidate.get("candidate_identity"),
        "artifact_digest": candidate.get("artifact_digest"),
        "sandbox_safe_mutations": sorted(sandbox_safe),
    }

    checks: list[dict[str, Any]] = []
    declared_mutations: list[str] = []
    for definition in CHECK_DEFINITIONS:
        result = runner(definition, context)
        if not isinstance(result, Mapping):
            result = {"passed": False, "detail": "runner returned no result"}
        passed = bool(result.get("passed"))
        detail = result.get("detail")
        if not isinstance(detail, str) or not detail:
            detail = "" if passed else "check failed"
        checks.append(
            {
                "id": definition["id"],
                "status": "passed" if passed else "failed",
                "detail": detail,
            }
        )
        declared_mutations.extend(_normalized_mutations(result.get("mutations")))

    uncontrolled = sorted(
        {mutation for mutation in declared_mutations if mutation not in sandbox_safe}
    )
    if uncontrolled:
        mutation_detail = "uncontrolled mutation: " + ", ".join(uncontrolled)
    else:
        mutation_detail = "no uncontrolled order/payment mutation"
    checks.append(
        {
            "id": MUTATION_CHECK_ID,
            "status": "failed" if uncontrolled else "passed",
            "detail": mutation_detail,
        }
    )

    client_id = candidate.get("client_id")
    report: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "client_id": client_id if isinstance(client_id, str) else client_dir.name,
        "environment": ENVIRONMENT,
        "candidate_identity": candidate.get("candidate_identity"),
        "artifact_digest": candidate.get("artifact_digest"),
        "deployment_id": deployment.get("deployment_id"),
        "checks": checks,
        "low_risk": not uncontrolled,
        "uncontrolled_mutations": uncontrolled,
    }
    report["report_identity"] = production_smoke_report_identity(report)
    return report


def smoke_report_path(client_dir: Path) -> Path:
    return Path(client_dir) / EVIDENCE_RELATIVE / SMOKE_REPORT_NAME


def load_production_smoke_report(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed production smoke report, or ``{}`` when absent."""
    path = smoke_report_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def write_smoke_report(
    root: Path, client_dir: Path, report: Mapping[str, Any]
) -> Path:
    path = smoke_report_path(client_dir)
    _write_json(path, report)
    return path


def validate_production_smoke(root: Path, client_dir: Path) -> list[str]:
    """Validate the committed production smoke report (stable sorted errors)."""
    root = Path(root)
    client_dir = Path(client_dir)
    path = smoke_report_path(client_dir)
    relative = _relative(root, path)
    if not path.is_file():
        return [f"{relative}: missing production smoke report"]
    try:
        report = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{relative}: cannot parse production smoke report: {exc}"]
    if not isinstance(report, Mapping):
        return [f"{relative}: production smoke report must be a JSON object"]

    errors: list[str] = []
    if report.get("report_identity") != production_smoke_report_identity(report):
        errors.append(f"{relative}: report_identity does not verify")
    if report.get("environment") != ENVIRONMENT:
        errors.append(f"{relative}: environment must be {ENVIRONMENT}")
    checks = report.get("checks")
    if not isinstance(checks, list):
        errors.append(f"{relative}: checks must be a list")
    else:
        for check in checks:
            if not isinstance(check, Mapping):
                errors.append(f"{relative}: checks entries must be objects")
            elif check.get("status") != "passed":
                errors.append(
                    f"{relative}: check {check.get('id')} did not pass"
                )
    if report.get("low_risk") is not True:
        errors.append(f"{relative}: low_risk must be true")
    if report.get("uncontrolled_mutations"):
        errors.append(f"{relative}: uncontrolled_mutations must be empty")
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
    """CLI entry point: validate (default) or ``--write`` the smoke report."""
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
        candidate = load_candidate(client_dir)
        deployment = build_fixture_production_deployment(candidate)
        report = run_production_smoke(root, client_dir, deployment)
        path = write_smoke_report(root, client_dir, report)
        print(_relative(root, path))
        return 0

    errors = validate_production_smoke(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
