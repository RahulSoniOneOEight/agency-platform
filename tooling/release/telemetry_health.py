"""H.2 deterministic bounded telemetry health gate (Milestone H.2, Task 9).

Spec sections 17 and 19 (Gate 4) require immediate post-release operational health
to be validated without an indefinite human wait. The window is deterministically
represented by **exactly five ordered samples at 60-second spacing** (a four-minute
observation span). Live execution records the samples over the window; fixture and
unit mode supply five recorded samples immediately, so the evaluator itself never
sleeps or polls.

Each sample carries ``{index, at, deployment_reachable, release_version,
sentry_health_signal, critical_unhandled_errors, error_rate, smoke_passed}``.

Blocking conditions (spec section 19, acceptance criterion 33):

- the deployment is unreachable;
- the expected release version is not visible;
- the reference observability health signal failed;
- a critical unhandled error attributed to the release;
- the configured critical-error-rate threshold is breached;
- the production smoke did not pass.

Any blocking condition makes the outcome ``failed``; an otherwise clean window
with a ``degraded`` health signal is ``degraded``; otherwise ``healthy``. The
report is self-verifying over canonical JSON excluding ``report_identity``.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Mapping, Sequence
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from tooling.hardening.candidate import (
    CANDIDATE_NAME,
    RELEASE_RELATIVE,
    canonical_identity,
)

REPORT_VERSION = 1
ENVIRONMENT = "production"
TELEMETRY_REPORT_NAME = "telemetry-health-report.json"
EVIDENCE_RELATIVE = Path("production") / "evidence"

REQUIRED_SAMPLE_COUNT = 5
SAMPLE_SPACING_SECONDS = 60
DEFAULT_ERROR_RATE_THRESHOLD = 0.01
HEALTH_SIGNALS: tuple[str, ...] = ("healthy", "degraded", "failed")
OUTCOMES: tuple[str, ...] = ("healthy", "degraded", "failed")

SAMPLE_FIELDS: tuple[str, ...] = (
    "index",
    "at",
    "deployment_reachable",
    "release_version",
    "sentry_health_signal",
    "critical_unhandled_errors",
    "error_rate",
    "smoke_passed",
)

# Deterministic committed-fixture sample window.
FIXTURE_BASE_TIME = datetime(2026, 9, 18, 10, 5, 0, tzinfo=timezone.utc)


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


def _format_timestamp(value: datetime) -> str:
    return (
        value.astimezone(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


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


def telemetry_report_identity(report: Mapping[str, Any]) -> str:
    """Return the canonical identity of *report* excluding ``report_identity``."""
    body = {key: value for key, value in report.items() if key != "report_identity"}
    return canonical_identity(body)


def build_fixture_samples(candidate: Mapping[str, Any]) -> list[dict[str, Any]]:
    """Return the five healthy recorded fixture samples for *candidate*.

    The samples are supplied immediately; no sleeping or polling is involved.
    """
    version = candidate.get("build_version")
    release_version = version if isinstance(version, str) else ""
    samples: list[dict[str, Any]] = []
    for index in range(REQUIRED_SAMPLE_COUNT):
        at = FIXTURE_BASE_TIME + timedelta(
            seconds=index * SAMPLE_SPACING_SECONDS
        )
        samples.append(
            {
                "index": index,
                "at": _format_timestamp(at),
                "deployment_reachable": True,
                "release_version": release_version,
                "sentry_health_signal": "healthy",
                "critical_unhandled_errors": [],
                "error_rate": 0.0,
                "smoke_passed": True,
            }
        )
    return samples


def _error_rate_threshold(policy: Mapping[str, Any]) -> float:
    value = policy.get("error_rate_threshold")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return DEFAULT_ERROR_RATE_THRESHOLD
    return float(value)


def _critical_errors_attributed(errors: Any, release_version: Any) -> bool:
    """Whether *errors* contains a critical unhandled error for the release.

    Errors with an explicit ``release_version``/``release`` that names a
    different release are not attributed to this release; errors without release
    attribution count.
    """
    if errors is None or isinstance(errors, bool):
        return False
    if isinstance(errors, int):
        return errors > 0
    if isinstance(errors, str):
        return bool(errors)
    if isinstance(errors, Mapping):
        return True
    if isinstance(errors, Sequence):
        for error in errors:
            if isinstance(error, Mapping):
                attributed = error.get("release_version", error.get("release"))
                if attributed is not None and str(attributed) != str(release_version):
                    continue
            return True
        return False
    return bool(errors)


def evaluate_telemetry_health(
    root: Path,
    client_dir: Path,
    samples: Sequence[Mapping[str, Any]],
    candidate: Mapping[str, Any],
    policy: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Evaluate the bounded telemetry health window.

    Consumes recorded sample evidence only; sleeping/polling belongs to the live
    workflow wrapper, never to this deterministic evaluator.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    candidate = candidate if isinstance(candidate, Mapping) else {}
    policy = policy if isinstance(policy, Mapping) else {}
    threshold = _error_rate_threshold(policy)
    release_version = candidate.get("build_version")

    if isinstance(samples, Sequence) and not isinstance(samples, (str, bytes)):
        sample_list = list(samples)
    else:
        sample_list = []

    blocking: list[str] = []
    degraded = False

    if len(sample_list) != REQUIRED_SAMPLE_COUNT:
        blocking.append(
            f"sample_count: expected {REQUIRED_SAMPLE_COUNT} samples, "
            f"found {len(sample_list)}"
        )

    previous_time: datetime | None = None
    for position, sample in enumerate(sample_list):
        label = f"sample[{position}]"
        if not isinstance(sample, Mapping):
            blocking.append(f"{label}: must be an object")
            continue

        index = sample.get("index")
        if isinstance(index, bool) or not isinstance(index, int):
            blocking.append(f"{label}.index: must be an integer")
        elif index != position:
            blocking.append(f"{label}.index: expected {position}, found {index}")

        current_time = _parse_timestamp(sample.get("at"))
        if current_time is None:
            blocking.append(f"{label}.at: must be an ISO-8601 timestamp")
        else:
            if previous_time is not None:
                delta = (current_time - previous_time).total_seconds()
                if delta != SAMPLE_SPACING_SECONDS:
                    blocking.append(
                        f"{label}.at: expected {SAMPLE_SPACING_SECONDS}s spacing, "
                        f"found {delta:g}s"
                    )
            previous_time = current_time

        if sample.get("deployment_reachable") is not True:
            blocking.append(f"{label}: deployment unreachable")

        if sample.get("release_version") != release_version:
            blocking.append(f"{label}: release version mismatch")

        signal = sample.get("sentry_health_signal")
        if signal == "failed":
            blocking.append(f"{label}: failed health signal")
        elif signal == "degraded":
            degraded = True
        elif signal not in HEALTH_SIGNALS:
            blocking.append(f"{label}: unknown health signal")

        if _critical_errors_attributed(
            sample.get("critical_unhandled_errors"), release_version
        ):
            blocking.append(
                f"{label}: critical unhandled error attributed to the release"
            )

        error_rate = sample.get("error_rate")
        if isinstance(error_rate, bool) or not isinstance(error_rate, (int, float)):
            blocking.append(f"{label}.error_rate: must be a number")
        elif float(error_rate) > threshold:
            blocking.append(f"{label}: error rate above threshold")

        if sample.get("smoke_passed") is not True:
            blocking.append(f"{label}: smoke not passed")

    blocking_reasons = sorted(set(blocking))
    if blocking_reasons:
        outcome = "failed"
    elif degraded:
        outcome = "degraded"
    else:
        outcome = "healthy"

    client_id = candidate.get("client_id")
    environment = candidate.get("target_environment")
    report: dict[str, Any] = {
        "report_version": REPORT_VERSION,
        "client_id": client_id if isinstance(client_id, str) else client_dir.name,
        "environment": environment if isinstance(environment, str) else ENVIRONMENT,
        "candidate_identity": candidate.get("candidate_identity"),
        "artifact_digest": candidate.get("artifact_digest"),
        "samples": [
            dict(sample) if isinstance(sample, Mapping) else sample
            for sample in sample_list
        ],
        "sample_count": REQUIRED_SAMPLE_COUNT,
        "spacing_seconds": SAMPLE_SPACING_SECONDS,
        "outcome": outcome,
        "blocking_reasons": blocking_reasons,
    }
    report["report_identity"] = telemetry_report_identity(report)
    return report


def telemetry_report_path(client_dir: Path) -> Path:
    return Path(client_dir) / EVIDENCE_RELATIVE / TELEMETRY_REPORT_NAME


def load_telemetry_report(client_dir: Path) -> Mapping[str, Any]:
    """Return the committed telemetry health report, or ``{}`` when absent."""
    path = telemetry_report_path(client_dir)
    if not path.is_file():
        return {}
    try:
        payload = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, Mapping) else {}


def write_telemetry_report(
    root: Path, client_dir: Path, report: Mapping[str, Any]
) -> Path:
    path = telemetry_report_path(client_dir)
    _write_json(path, report)
    return path


def validate_telemetry_health(root: Path, client_dir: Path) -> list[str]:
    """Validate the committed telemetry health report (stable sorted errors)."""
    root = Path(root)
    client_dir = Path(client_dir)
    path = telemetry_report_path(client_dir)
    relative = _relative(root, path)
    if not path.is_file():
        return [f"{relative}: missing telemetry health report"]
    try:
        report = _load_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{relative}: cannot parse telemetry health report: {exc}"]
    if not isinstance(report, Mapping):
        return [f"{relative}: telemetry health report must be a JSON object"]

    errors: list[str] = []
    if report.get("report_identity") != telemetry_report_identity(report):
        errors.append(f"{relative}: report_identity does not verify")
    if report.get("sample_count") != REQUIRED_SAMPLE_COUNT:
        errors.append(
            f"{relative}: sample_count must be {REQUIRED_SAMPLE_COUNT}"
        )
    if report.get("spacing_seconds") != SAMPLE_SPACING_SECONDS:
        errors.append(
            f"{relative}: spacing_seconds must be {SAMPLE_SPACING_SECONDS}"
        )
    samples = report.get("samples")
    if not isinstance(samples, list) or len(samples) != REQUIRED_SAMPLE_COUNT:
        errors.append(
            f"{relative}: samples must contain exactly {REQUIRED_SAMPLE_COUNT} entries"
        )
    if report.get("outcome") not in OUTCOMES:
        errors.append(f"{relative}: outcome must be one of {OUTCOMES}")
    if not isinstance(report.get("blocking_reasons"), list):
        errors.append(f"{relative}: blocking_reasons must be a list")
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
    """CLI entry point: validate (default) or ``--write`` the health report."""
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
        report = evaluate_telemetry_health(
            root, client_dir, build_fixture_samples(candidate), candidate
        )
        path = write_telemetry_report(root, client_dir, report)
        print(_relative(root, path))
        return 0

    errors = validate_telemetry_health(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
