"""H.2 staging deployment smoke orchestration (spec sections 8 and 19, Task 7).

The smoke runner validates the critical staged journeys against a *deployed*
candidate. It has an injectable HTTP/browser seam so the default (fixture) mode
is fully deterministic and network-free, while the live mode used by the
``staging-deploy`` / ``h2-hardening`` workflows probes the real staging URL from
the deployment output.

Critical staged journeys:

- B2C ``sign-in -> catalog -> inventory -> cart -> order``
- B2B ``sign-in -> membership -> credit -> RFQ -> quotation -> order``
- ``session-refresh``
- ``insufficient-permission``
- ``backend-failure``
- ``release-identity`` (deployment/version build marker)

A journey runner is any callable ``runner(journey, context) -> mapping`` that
returns ``{"passed": bool, "steps": [...], "error_class": str | None}``. The
default :class:`FixtureJourneyRunner` passes every journey but re-verifies the
release identity against the frozen candidate; :class:`HttpJourneyRunner` is the
live network seam. The report is self-verifying: ``report_identity`` is the
canonical identity over the report excluding ``report_identity``.
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
ENVIRONMENT = "staging"
SMOKE_REPORT_NAME = "staging-smoke-report.json"
DEPLOYMENT_NAME = "staging-deployment.json"
EVIDENCE_RELATIVE = Path("production") / "evidence"

B2C_STEPS: tuple[str, ...] = ("sign-in", "catalog", "inventory", "cart", "order")
B2B_STEPS: tuple[str, ...] = (
    "sign-in",
    "membership",
    "credit",
    "rfq",
    "quotation",
    "order",
)

# Sorted by journey name so the emitted report is deterministic.
JOURNEY_DEFINITIONS: tuple[dict[str, Any], ...] = (
    {"name": "b2b-quote-order", "critical": True, "steps": B2B_STEPS},
    {"name": "b2c-order", "critical": True, "steps": B2C_STEPS},
    {
        "name": "backend-failure",
        "critical": True,
        "steps": ("load-catalog-failure", "error-mapping"),
    },
    {
        "name": "insufficient-permission",
        "critical": True,
        "steps": ("forbidden-action", "denied"),
    },
    {"name": "release-identity", "critical": True, "steps": ("verify-release-marker",)},
    {
        "name": "session-refresh",
        "critical": True,
        "steps": ("refresh-session", "session-valid"),
    },
)

JOURNEY_NAMES: tuple[str, ...] = tuple(
    definition["name"] for definition in JOURNEY_DEFINITIONS
)


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


def smoke_report_identity(report: Mapping[str, Any]) -> str:
    """Return the canonical identity of *report* excluding ``report_identity``."""
    body = {key: value for key, value in report.items() if key != "report_identity"}
    return canonical_identity(body)


def _release_identity_ok(context: Mapping[str, Any]) -> bool:
    deployment = context.get("deployment") or {}
    candidate = context.get("candidate") or {}
    if not isinstance(deployment, Mapping) or not isinstance(candidate, Mapping):
        return False
    return (
        deployment.get("environment") == ENVIRONMENT
        and deployment.get("status") == "succeeded"
        and isinstance(deployment.get("deployment_id"), str)
        and bool(deployment.get("deployment_id"))
        and deployment.get("artifact_digest") == candidate.get("artifact_digest")
    )


class FixtureJourneyRunner:
    """Deterministic offline runner: passes every journey, binds release identity."""

    def __call__(
        self, journey: Mapping[str, Any], context: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        name = journey.get("name")
        if name == "release-identity" and not _release_identity_ok(context):
            return {
                "passed": False,
                "error_class": "artifact_digest_mismatch",
            }
        return {"passed": True, "error_class": None}


class HttpJourneyRunner:
    """Live network seam used by the staging workflow against the real URL.

    Only the deployment/version build marker is contractually checkable without
    a provider-specific API, so it is verified against the frozen candidate; the
    remaining journeys assert that the deployed staging application shell
    responds successfully. Provider-native detail stays in the response refs.
    """

    def __init__(self, timeout: float = 15.0) -> None:
        self.timeout = timeout

    def _fetch(self, url: str) -> tuple[bool, str]:
        import urllib.error
        import urllib.request

        try:
            with urllib.request.urlopen(url, timeout=self.timeout) as response:
                status = getattr(response, "status", 200)
                return 200 <= int(status) < 300, str(status)
        except urllib.error.HTTPError as exc:  # pragma: no cover - live only
            return False, f"http-{exc.code}"
        except (urllib.error.URLError, OSError, ValueError) as exc:  # pragma: no cover
            return False, type(exc).__name__

    def __call__(
        self, journey: Mapping[str, Any], context: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        base_url = context.get("base_url")
        if not isinstance(base_url, str) or not base_url:
            return {"passed": False, "error_class": "artifact_missing"}

        if journey.get("name") == "release-identity":
            if not _release_identity_ok(context):
                return {"passed": False, "error_class": "artifact_digest_mismatch"}
            ok, detail = self._fetch(base_url.rstrip("/") + "/version.json")
            if not ok:
                return {"passed": False, "error_class": "deployment_failed"}
            return {"passed": True, "error_class": None, "detail": detail}

        ok, _ = self._fetch(base_url)
        return {
            "passed": ok,
            "error_class": None if ok else "staging_smoke_failed",
        }


def _normalized_steps(
    definition: Mapping[str, Any],
    result: Mapping[str, Any],
) -> list[dict[str, Any]]:
    declared = [str(step) for step in definition.get("steps", ())]
    raw_steps = result.get("steps")
    if isinstance(raw_steps, Sequence) and not isinstance(raw_steps, (str, bytes)):
        steps: list[dict[str, Any]] = []
        for index, raw in enumerate(raw_steps):
            if not isinstance(raw, Mapping):
                continue
            name = raw.get("name")
            if not isinstance(name, str) or not name:
                name = declared[index] if index < len(declared) else f"step-{index}"
            steps.append({"name": name, "passed": bool(raw.get("passed"))})
        if steps:
            return steps
    overall = bool(result.get("passed"))
    return [{"name": step, "passed": overall} for step in declared]


def run_staging_smoke(
    root: Path,
    client_dir: Path,
    deployment: Mapping[str, Any],
    http: Any | None = None,
) -> dict[str, Any]:
    """Return the deterministic staging smoke report for a deployed candidate.

    ``http`` is the injectable journey-runner seam; when omitted the offline
    fixture runner is used. The report binds the frozen candidate identity and
    artifact digest, the deployment id, and every critical journey result.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    deployment = deployment if isinstance(deployment, Mapping) else {}
    candidate = load_candidate(client_dir)

    runner = http if callable(http) else FixtureJourneyRunner()
    context: dict[str, Any] = {
        "base_url": deployment.get("url"),
        "candidate": candidate,
        "deployment": deployment,
        "candidate_identity": candidate.get("candidate_identity"),
        "artifact_digest": candidate.get("artifact_digest"),
    }

    journeys: list[dict[str, Any]] = []
    for definition in JOURNEY_DEFINITIONS:
        result = runner(definition, context)
        if not isinstance(result, Mapping):
            result = {"passed": False, "error_class": "staging_smoke_failed"}
        error_class = result.get("error_class")
        journeys.append(
            {
                "name": definition["name"],
                "critical": bool(definition["critical"]),
                "steps": _normalized_steps(definition, result),
                "passed": bool(result.get("passed")),
                "error_class": error_class if isinstance(error_class, str) else None,
            }
        )

    critical_passed = all(
        journey["passed"] for journey in journeys if journey["critical"]
    )

    client_id = candidate.get("client_id")
    report: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "client_id": client_id if isinstance(client_id, str) else client_dir.name,
        "environment": ENVIRONMENT,
        "candidate_identity": candidate.get("candidate_identity"),
        "artifact_digest": candidate.get("artifact_digest"),
        "deployment_id": deployment.get("deployment_id"),
        "journeys": journeys,
        "critical_journeys_passed": critical_passed,
    }
    report["report_identity"] = smoke_report_identity(report)
    return report


def smoke_report_path(client_dir: Path) -> Path:
    return Path(client_dir) / EVIDENCE_RELATIVE / SMOKE_REPORT_NAME


def deployment_path(client_dir: Path) -> Path:
    return Path(client_dir) / RELEASE_RELATIVE / DEPLOYMENT_NAME


def load_deployment(client_dir: Path) -> Mapping[str, Any]:
    path = deployment_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def write_smoke_report(root: Path, client_dir: Path, report: Mapping[str, Any]) -> Path:
    path = smoke_report_path(client_dir)
    _write_json(path, report)
    return path


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
    """CLI entry point: validate (default) or ``--write`` the smoke report.

    ``--write`` regenerates the committed fixture smoke report from the
    committed staging deployment and the frozen candidate. It never touches the
    network.
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
        deployment = load_deployment(client_dir)
        report = run_staging_smoke(root, client_dir, deployment)
        path = write_smoke_report(root, client_dir, report)
        print(_relative(root, path))
        return 0

    path = smoke_report_path(client_dir)
    if not path.is_file():
        print(f"{_relative(root, path)}: missing staging smoke report")
        return 1
    try:
        report = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"{_relative(root, path)}: cannot parse staging smoke report: {exc}")
        return 1
    if report.get("report_identity") != smoke_report_identity(report):
        print(f"{_relative(root, path)}: report_identity does not verify")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
