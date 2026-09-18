"""Composed deterministic validator for the reference-commerce client (F.3 Task 10).

``validate_reference_client`` composes the existing reference-client validators
(fixture, scenario, assertions, review/approval/QA evidence, change evidence,
resume evidence) and adds the aggregated-report checks: the committed machine and
human reports must byte-match a fresh deterministic build, the machine report
must validate against its schema and verify its own ``report_identity``, and
every evidence reference must resolve.

It is Flutter-free (RF17), reads only canonical artifacts and committed evidence
(RF6), never mutates authority, and never needs a live credential (RF9).

Documented CI command::

    py -3.12 -m tooling.reference_client.validate_reference_client client-projects/reference-commerce
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Mapping

import yaml
from jsonschema import Draft202012Validator

from tooling.reference_client.assertions import (
    evaluate_assertions,
    validate_assertions,
)
from tooling.reference_client.change_scenarios import validate_change_evidence
from tooling.reference_client.evidence import load_evidence, validate_evidence
from tooling.reference_client.fixture import (
    FIXTURE_RELATIVE,
    fixture_identity,
    load_fixture,
    validate_fixture,
)
from tooling.reference_client.report import (
    CHANGE_EVIDENCE_NAME,
    EVIDENCE_DIR_RELATIVE,
    HUMAN_REPORT_NAME,
    MACHINE_REPORT_NAME,
    REPORT_DIR_RELATIVE,
    REPORT_VERSION,
    RESUME_EVIDENCE_NAME,
    REVIEW_EVIDENCE_NAME,
    build_machine_report,
    canonical_report,
    machine_report_identity,
    render_human_report,
)
from tooling.reference_client.scenario import (
    REQUIRED_SCENARIO_IDS,
    validate_scenario,
)

MACHINE_SCHEMA_RELATIVE = (
    Path("client-projects")
    / "schema"
    / "reference-client-machine-report.schema.json"
)

DEFAULT_CLIENT_DIR = Path("client-projects") / "reference-commerce"

_SHA256_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
_COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")

_GROUP_TITLES: tuple[tuple[str, str], ...] = (
    ("fixture", "Fixture errors"),
    ("scenario", "Scenario errors"),
    ("assertions", "Assertion errors"),
    ("review-evidence", "Review/approval/QA evidence errors"),
    ("change-evidence", "Change-scenario evidence errors"),
    ("resume-evidence", "Resume evidence errors"),
    ("report", "Report errors"),
)


def _schema_errors(root: Path, report: Mapping[str, Any]) -> list[str]:
    schema_path = root / MACHINE_SCHEMA_RELATIVE
    if not schema_path.exists():
        return [f"{schema_path}: missing machine-report schema"]
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(report), key=lambda error: list(error.path))
    return [
        f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
        for error in errors
    ]


def _approval_errors(
    report: Mapping[str, Any], change_evidence: Any
) -> list[str]:
    errors: list[str] = []
    approvals = report.get("approvals")
    if not isinstance(approvals, list) or not approvals:
        return ["approvals must be a non-empty list"]

    versions: list[int] = []
    for index, entry in enumerate(approvals):
        if not isinstance(entry, Mapping):
            errors.append(f"approvals[{index}] must be a mapping")
            continue
        version = entry.get("version")
        if isinstance(version, bool) or not isinstance(version, int):
            errors.append(f"approvals[{index}].version must be an integer")
        else:
            versions.append(version)
        review_round = entry.get("review_round")
        if (
            isinstance(review_round, bool)
            or not isinstance(review_round, int)
            or review_round < 1
        ):
            errors.append(
                f"approvals[{index}].review_round must be an integer >= 1"
            )
        review_state_hash = entry.get("review_state_hash")
        if not isinstance(review_state_hash, str) or not _SHA256_PATTERN.match(
            review_state_hash
        ):
            errors.append(
                f"approvals[{index}].review_state_hash must be a sha256 reference"
            )
        source_commit_sha = entry.get("source_commit_sha")
        if not isinstance(source_commit_sha, str) or not _COMMIT_PATTERN.match(
            source_commit_sha
        ):
            errors.append(
                f"approvals[{index}].source_commit_sha must be a 40-hex commit"
            )

    if versions:
        if versions[0] != 1:
            errors.append("approval versions must start at 1")
        for index in range(1, len(versions)):
            if versions[index] <= versions[index - 1]:
                errors.append("approval versions must be strictly increasing")
                break

    contract = None
    if isinstance(change_evidence, Mapping):
        candidate = change_evidence.get("contract_change")
        if isinstance(candidate, Mapping):
            contract = candidate
    if contract is not None:
        v2_version = contract.get("v2_version")
        v2_supersedes = contract.get("v2_supersedes")
        if isinstance(v2_version, int) and not isinstance(v2_version, bool):
            if v2_supersedes != v2_version - 1:
                errors.append("approval v2 supersedes relationship is inconsistent")
            if versions and v2_version != max(versions):
                errors.append(
                    "approval v2 version does not match the recorded approvals"
                )
    return errors


def _qa_errors(report: Mapping[str, Any]) -> list[str]:
    qa = report.get("qa")
    if not isinstance(qa, Mapping):
        return ["qa must be a mapping"]
    errors: list[str] = []
    if not qa.get("findings"):
        errors.append("qa finding evidence is missing")
    if not qa.get("promotions"):
        errors.append("qa promotion evidence is missing")
    return errors


def validate_reference_client(root: Path, client_dir: Path) -> list[str]:
    """Return deterministic, stable-sorted reference-client errors (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)
    errors: list[str] = []

    errors.extend(f"fixture: {error}" for error in validate_fixture(root, client_dir))
    errors.extend(f"scenario: {error}" for error in validate_scenario(root, client_dir))
    errors.extend(
        f"assertions: {error}" for error in validate_assertions(root, client_dir)
    )

    try:
        results = evaluate_assertions(root, client_dir)
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, yaml.YAMLError) as exc:
        errors.append(f"assertions: cannot evaluate: {type(exc).__name__}: {exc}")
        results = []
    for result in results:
        if not result.passed:
            errors.append(
                f"assertions: assertion {result.id} failed: {result.detail}"
            )

    review_path = client_dir / EVIDENCE_DIR_RELATIVE / REVIEW_EVIDENCE_NAME
    change_path = client_dir / EVIDENCE_DIR_RELATIVE / CHANGE_EVIDENCE_NAME
    resume_path = client_dir / EVIDENCE_DIR_RELATIVE / RESUME_EVIDENCE_NAME

    review_evidence: Any = None
    if not review_path.exists():
        errors.append(
            f"review-evidence: {review_path}: missing QA/review evidence"
        )
    else:
        try:
            review_evidence = load_evidence(review_path)
            errors.extend(
                f"review-evidence: {error}"
                for error in validate_evidence(root, client_dir, review_evidence)
            )
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append(f"review-evidence: {review_path}: {exc}")

    change_evidence: Any = None
    if not change_path.exists():
        errors.append(f"change-evidence: {change_path}: missing change evidence")
    else:
        try:
            change_evidence = load_evidence(change_path)
            errors.extend(
                f"change-evidence: {error}"
                for error in validate_change_evidence(
                    root, client_dir, change_evidence
                )
            )
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append(f"change-evidence: {change_path}: {exc}")

    resume_evidence: Any = None
    if not resume_path.exists():
        errors.append(f"resume-evidence: {resume_path}: missing resume evidence")
    else:
        try:
            resume_evidence = load_evidence(resume_path)
            from tooling.reference_client.scenario import validate_resume_evidence

            errors.extend(
                f"resume-evidence: {error}"
                for error in validate_resume_evidence(resume_evidence)
            )
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append(f"resume-evidence: {resume_path}: {exc}")

    errors.extend(
        _report_errors(
            root,
            client_dir,
            review_evidence,
            change_evidence,
            review_path,
            change_path,
        )
    )

    return sorted(set(errors))


def _report_errors(
    root: Path,
    client_dir: Path,
    review_evidence: Any,
    change_evidence: Any,
    review_path: Path,
    change_path: Path,
) -> list[str]:
    errors: list[str] = []
    report_dir = client_dir / REPORT_DIR_RELATIVE
    machine_path = report_dir / MACHINE_REPORT_NAME
    human_path = report_dir / HUMAN_REPORT_NAME

    fresh: dict[str, Any] | None = None
    try:
        fresh = build_machine_report(root, client_dir)
    except (OSError, UnicodeError, ValueError, KeyError, TypeError, yaml.YAMLError) as exc:
        errors.append(
            f"report: cannot build fresh machine report: {type(exc).__name__}: {exc}"
        )

    if not machine_path.exists():
        errors.append(f"report: {machine_path}: missing machine report")
    else:
        try:
            committed = json.loads(machine_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            errors.append(f"report: {machine_path}: cannot parse: {exc}")
        else:
            errors.extend(
                f"report: {error}" for error in _schema_errors(root, committed)
            )
            if committed.get("report_version") != REPORT_VERSION:
                errors.append(
                    f"report: report_version must be {REPORT_VERSION}"
                )
            if committed.get("report_identity") != machine_report_identity(committed):
                errors.append("report: report_identity does not verify")
            for ref in committed.get("evidence_refs") or []:
                if not isinstance(ref, str) or not (root / ref).exists():
                    errors.append(
                        f"report: referenced evidence does not exist: {ref!r}"
                    )
            if committed.get("scenario_ids") != list(REQUIRED_SCENARIO_IDS):
                errors.append(
                    "report: scenario_ids do not match the required scenario ids"
                )
            if isinstance(review_evidence, Mapping):
                if committed.get("source_commit_sha") != review_evidence.get(
                    "source_commit_sha"
                ):
                    errors.append(
                        "report: source_commit_sha does not match the review evidence"
                    )
            try:
                expected_identity = fixture_identity(
                    load_fixture(client_dir / FIXTURE_RELATIVE)
                )
            except (OSError, UnicodeError, ValueError, yaml.YAMLError):
                expected_identity = None
            if (
                expected_identity is not None
                and committed.get("fixture_identity") != expected_identity
            ):
                errors.append(
                    "report: fixture_identity does not match the canonical fixture"
                )
            errors.extend(
                f"report: {error}"
                for error in _approval_errors(committed, change_evidence)
            )
            errors.extend(
                f"report: {error}" for error in _qa_errors(committed)
            )
            if fresh is not None:
                if machine_path.read_bytes() != canonical_report(fresh).encode("utf-8"):
                    errors.append(
                        "report: committed machine report is stale "
                        "(bytes differ from a fresh build)"
                    )

    if not human_path.exists():
        errors.append(f"report: {human_path}: missing human report")
    elif fresh is not None:
        expected_human = render_human_report(fresh).encode("utf-8")
        if human_path.read_bytes() != expected_human:
            errors.append(
                "report: committed human report is stale "
                "(bytes differ from a fresh render)"
            )

    return errors


def _group_errors(errors: list[str]) -> list[tuple[str, list[str]]]:
    buckets: dict[str, list[str]] = {}
    for error in errors:
        prefix = error.split(":", 1)[0]
        buckets.setdefault(prefix, []).append(error)
    grouped: list[tuple[str, list[str]]] = []
    for prefix, title in _GROUP_TITLES:
        if prefix in buckets:
            grouped.append((title, buckets.pop(prefix)))
    for prefix in sorted(buckets):
        grouped.append((f"{prefix} errors", buckets[prefix]))
    return grouped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tooling.reference_client.validate_reference_client",
        description=(
            "Validate the reference-commerce fixture, evidence, and reports "
            "deterministically (Flutter-free, credential-free)."
        ),
    )
    parser.add_argument(
        "client_dir",
        nargs="?",
        default=str(DEFAULT_CLIENT_DIR),
        help="Client project directory (default: client-projects/reference-commerce).",
    )
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[2]
    client_dir = Path(args.client_dir)
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    errors = validate_reference_client(root, client_dir)
    if errors:
        print("Reference client validation failed.")
        for title, items in _group_errors(errors):
            print(f"{title}:")
            for item in items:
                print(f"- {item}")
        return 1

    print(
        "Reference client validation passed: fixture, scenario, assertions, "
        "review/approval/QA evidence, change evidence, resume evidence, and "
        "the machine/human reports are valid and byte-fresh."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
