"""Apply/record staging migration evidence for the exact H.2 candidate.

This module is deliberately network-free. The GitHub Actions staging workflow
owns the actual psql execution; this module verifies that the candidate-bound
migration files still match their recorded hashes and writes the evidence that
the H.2 migration gate consumes after psql and post-apply verification succeed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping

from tooling.hardening.candidate import CANDIDATE_NAME, RELEASE_RELATIVE

EVIDENCE_RELATIVE = Path("production") / "evidence" / "migration-evidence.json"
_CLASS_HEADER = re.compile(r"^--\s*migration-class:\s*(\S+)\s*$", re.MULTILINE)


def _sha256_normalized(path: Path) -> str:
    data = path.read_bytes().replace(b"\r\n", b"\n")
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _load_candidate(client_dir: Path) -> Mapping[str, Any]:
    path = client_dir / RELEASE_RELATIVE / CANDIDATE_NAME
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, Mapping):
        raise ValueError("release candidate must be a JSON object")
    return payload


def verify_candidate_migration_files(root: Path, client_dir: Path) -> list[str]:
    """Return stable errors if candidate migration files no longer match."""
    root = Path(root)
    client_dir = Path(client_dir)
    candidate = _load_candidate(client_dir)
    entries = candidate.get("migration_set_entries")
    migration_set = candidate.get("migration_set")
    errors: list[str] = []

    if not isinstance(entries, list) or not entries:
        return ["candidate.migration_set_entries: missing or empty"]
    if not isinstance(migration_set, list) or not migration_set:
        return ["candidate.migration_set: missing or empty"]

    entry_paths: list[str] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, Mapping):
            errors.append(f"candidate.migration_set_entries[{index}]: must be an object")
            continue
        rel = entry.get("path")
        declared = entry.get("sha256")
        if not isinstance(rel, str) or not rel:
            errors.append(f"candidate.migration_set_entries[{index}].path: invalid")
            continue
        entry_paths.append(rel)
        path = root / rel
        if not path.is_file():
            errors.append(f"{rel}: migration file missing")
            continue
        actual = _sha256_normalized(path)
        if actual != declared:
            errors.append(f"{rel}: sha256 does not match candidate")

    if entry_paths != migration_set:
        errors.append("candidate migration_set paths do not match migration_set_entries")
    return sorted(set(errors))


def migration_plan(root: Path, client_dir: Path) -> list[str]:
    """Return candidate-bound migration paths after integrity verification."""
    errors = verify_candidate_migration_files(root, client_dir)
    if errors:
        raise ValueError("; ".join(errors))
    candidate = _load_candidate(client_dir)
    return [str(path) for path in candidate["migration_set"]]


def _migration_classes(root: Path, migration_paths: list[str]) -> dict[str, str]:
    classes: dict[str, str] = {}
    for rel in migration_paths:
        text = (Path(root) / rel).read_text(encoding="utf-8").replace("\r\n", "\n")
        match = _CLASS_HEADER.search(text)
        classes[rel] = match.group(1) if match else "unknown"
    return classes


def build_success_evidence(
    root: Path,
    client_dir: Path,
    *,
    verification_checks: list[str],
) -> dict[str, Any]:
    """Build the migration-gate evidence after real staging verification."""
    root = Path(root)
    client_dir = Path(client_dir)
    candidate = _load_candidate(client_dir)
    plan = migration_plan(root, client_dir)
    classes = _migration_classes(root, plan)

    recovery_treatment: dict[str, dict[str, str]] = {}
    for path, migration_class in classes.items():
        if migration_class in {"transformative", "destructive"}:
            recovery_treatment[path] = {
                "treatment": "manual-review-required-before-production"
            }

    return {
        "migration_set_identity": candidate.get("migration_set_identity"),
        "migration_set_entries": candidate.get("migration_set_entries"),
        "migration_classes": classes,
        "staging_apply": {
            "ok": True,
            "applied_migrations": plan,
        },
        "post_apply_verification": {
            "ok": True,
            "checks": list(verification_checks),
        },
        "recovery_treatment": recovery_treatment,
        "optimization_recommendations": [],
    }


def write_success_evidence(
    root: Path,
    client_dir: Path,
    *,
    verification_checks: list[str],
) -> Path:
    evidence = build_success_evidence(
        root, client_dir, verification_checks=verification_checks
    )
    path = Path(client_dir) / EVIDENCE_RELATIVE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("client", nargs="?", default="client-projects/reference-commerce")
    parser.add_argument("--print-plan", action="store_true")
    parser.add_argument("--write-success-evidence", action="store_true")
    parser.add_argument("--verification-check", action="append", default=[])
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[2]
    client_dir = Path(args.client)
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    errors = verify_candidate_migration_files(root, client_dir)
    if errors:
        for error in errors:
            print(error)
        return 1

    if args.print_plan:
        for path in migration_plan(root, client_dir):
            print(path)

    if args.write_success_evidence:
        path = write_success_evidence(
            root,
            client_dir,
            verification_checks=list(args.verification_check),
        )
        print(path.relative_to(root).as_posix())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
