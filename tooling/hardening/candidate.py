"""Deterministic H.2 release-candidate identity and artifact integrity (Task 5).

A release candidate binds every release-relevant input so the exact artifact
that passes staging hardening is the exact artifact that can later be
authorized and promoted (spec sections 7-9). This module builds that binding
without any network, Flutter, or credential dependency, so normal CI can
validate the committed reference candidate deterministically.

Identities
----------
Every identity is ``"sha256:" + sha256`` over the canonical compact JSON of the
value (``json.dumps(value, sort_keys=True, separators=(",", ":"),
ensure_ascii=True)``, UTF-8). This mirrors the Dart convention in
``packages/agency_operations_core/lib/src/release/release_candidate.dart``
exactly, so the Python ``candidate_identity`` equals the Dart
``candidateIdentity`` for the same field values (proved by the shared golden
vectors in ``tooling/validation/test_h2_candidate.py``).

- **candidate identity** — over exactly the nine canonical candidate fields
  (snake_case), matching Dart.
- **migration-set identity** — over the ordered ``migration_set_entries`` list of
  ``{"path", "sha256"}`` pairs for the CRLF-normalized ``supabase/migrations/*.sql``
  files (the plan's ordered ``(path, normalized content hash)`` convention). The
  pairs are embedded in the candidate so ``verify_candidate_artifact`` — which has
  no filesystem access — can recompute the identity instead of trusting it.
- **release-config identity** — over the canonical production client-safe
  config; it must equal the production ``config_identity`` recorded in the H.1
  foundation report.
- **artifact digest** — over the canonical artifact manifest excluding the
  digest field itself.

The artifact manifest hashes the **raw bytes** of every file in the deployable
directory in POSIX-relative-path order. It deliberately does not claim ZIP byte
reproducibility across platforms; the canonical file-manifest is the identity.

The committed reference candidate is generated from a committed deterministic
artifact fixture tree (``production/release/artifact-fixture``) so PR CI stays
credential-free (ruling R10). The ``candidate-build`` workflow builds the real
Flutter Web artifact and uploads a real manifest/candidate without committing
them.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

RELEASE_RELATIVE = Path("production") / "release"
CANDIDATE_NAME = "candidate.json"
MANIFEST_NAME = "artifact-manifest.json"
ARTIFACT_FIXTURE_NAME = "artifact-fixture"
CONFIG_RELATIVE = Path("production") / "config"
PRODUCTION_CONFIG_NAME = "production.json"
H1_REPORT_RELATIVE = Path("production") / "evidence" / "h1-foundation-report.json"
MIGRATIONS_RELATIVE = Path("supabase") / "migrations"
# R13: H.2 binds the *existing* F review/approval evidence as the approved
# experience authority. reference-commerce has no ``approved-experience.yaml``;
# H.2 must never create one (that would create approval authority it does not
# own). The authoritative artifact is the F review/approval evidence.
APPROVAL_EVIDENCE_RELATIVE = (
    Path("reference-e2e") / "evidence" / "review-approval-evidence.json"
)

TARGET_ENVIRONMENT = "production"

# Deterministic synthetic revision for the committed reference fixture (the
# H.2 plan commit, used as the branch base). The candidate-build workflow
# substitutes the real ``github.sha``.
FIXTURE_SOURCE_SHA = "b3b18ff1877e72447381c3e7bdfaf31889616f78"
FIXTURE_BUILD_VERSION = "0.1.0+h2rc1"

CANONICAL_FIELDS: tuple[str, ...] = (
    "client_id",
    "target_environment",
    "source_sha",
    "artifact_digest",
    "build_version",
    "migration_set",
    "release_config_identity",
    "approved_experience_ref",
    "h1_foundation_report_ref",
)

# Derived binding fields emitted alongside the nine canonical fields. They are
# not part of the canonical candidate identity (which must stay byte-equal to
# the Dart ``candidateIdentity``) but the schema requires them and
# ``verify_candidate_artifact`` validates them.
DERIVED_FIELDS: tuple[str, ...] = (
    "candidate_identity",
    "migration_set_identity",
    "migration_set_entries",
)

CANDIDATE_KEYS: frozenset[str] = frozenset(CANONICAL_FIELDS) | frozenset(
    DERIVED_FIELDS
)

# Top-level fields the schema constrains with ``minLength: 1``.
_NON_EMPTY_FIELDS: tuple[str, ...] = (
    "client_id",
    "target_environment",
    "build_version",
    "approved_experience_ref",
    "h1_foundation_report_ref",
)

_SOURCE_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def canonical_identity(value: Any) -> str:
    """Return the cross-language canonical ``sha256:`` identity of *value*.

    Byte-for-byte equal to the Dart ``canonicalJsonHash`` convention for the
    same value: recursive key sort, compact separators, ``ensure_ascii``
    escaping, UTF-8.
    """
    canonical = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    )
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


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


def _sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def build_artifact_manifest(artifact_path: Path) -> dict[str, Any]:
    """Return the canonical manifest of every file under *artifact_path*.

    Entries are sorted by POSIX-relative path; each entry records the
    ``sha256:`` digest of the file's raw bytes. ``artifact_digest`` is the
    canonical identity over the manifest *excluding* ``artifact_digest``.
    """
    artifact_path = Path(artifact_path)
    entries: list[dict[str, str]] = []
    if artifact_path.is_dir():
        for path in sorted(artifact_path.rglob("*")):
            if not path.is_file():
                continue
            entries.append(
                {
                    "path": path.relative_to(artifact_path).as_posix(),
                    "sha256": _sha256_bytes(path.read_bytes()),
                }
            )
    entries.sort(key=lambda entry: entry["path"])
    manifest: dict[str, Any] = {"entries": entries}
    manifest["artifact_digest"] = canonical_identity(manifest)
    return manifest


def _migration_entries(root: Path) -> list[dict[str, str]]:
    """Return ordered ``{path, sha256}`` pairs for the versioned migrations."""
    migrations_dir = Path(root) / MIGRATIONS_RELATIVE
    entries: list[dict[str, str]] = []
    if not migrations_dir.is_dir():
        return entries
    for path in sorted(migrations_dir.glob("*.sql")):
        normalized = path.read_bytes().replace(b"\r\n", b"\n")
        entries.append(
            {
                "path": _relative(Path(root), path),
                "sha256": _sha256_bytes(normalized),
            }
        )
    return entries


def _release_config_identity(client_dir: Path) -> str:
    payload = _load_json(Path(client_dir) / CONFIG_RELATIVE / PRODUCTION_CONFIG_NAME)
    return canonical_identity(payload)


def build_candidate(
    root: Path,
    client_dir: Path,
    artifact_path: Path,
    source_sha: str,
    build_version: str,
) -> dict[str, Any]:
    """Build the canonical release candidate for an artifact.

    Returns the nine canonical candidate fields plus ``candidate_identity``
    (over the nine fields, matching Dart), ``migration_set_entries`` (the
    ordered ``{path, sha256}`` pairs embedded so the identity is recomputable
    without filesystem access), and ``migration_set_identity`` (over
    ``migration_set_entries``).
    """
    root = Path(root)
    client_dir = Path(client_dir)
    artifact_path = Path(artifact_path)

    manifest = build_artifact_manifest(artifact_path)
    migration_entries = _migration_entries(root)

    fields: dict[str, Any] = {
        "client_id": client_dir.name,
        "target_environment": TARGET_ENVIRONMENT,
        "source_sha": source_sha,
        "artifact_digest": manifest["artifact_digest"],
        "build_version": build_version,
        "migration_set": [entry["path"] for entry in migration_entries],
        "release_config_identity": _release_config_identity(client_dir),
        "approved_experience_ref": _relative(
            root, client_dir / APPROVAL_EVIDENCE_RELATIVE
        ),
        "h1_foundation_report_ref": _relative(root, client_dir / H1_REPORT_RELATIVE),
    }

    candidate: dict[str, Any] = dict(fields)
    candidate["candidate_identity"] = canonical_identity(fields)
    candidate["migration_set_entries"] = migration_entries
    candidate["migration_set_identity"] = canonical_identity(migration_entries)
    return candidate


def _candidate_fields(candidate: Mapping[str, Any]) -> dict[str, Any]:
    return {field: candidate.get(field) for field in CANONICAL_FIELDS}


def _validate_relative_path(
    value: Any, label: str, errors: list[str]
) -> str | None:
    """Validate a POSIX relative path, appending stable errors on failure.

    Returns the path when valid, else ``None``. Rejects empty/non-string,
    absolute paths, backslashes, and ``..`` segments (the schema and every
    manifest docstring claim POSIX relative paths).
    """
    if not isinstance(value, str) or not value:
        errors.append(f"{label}: must be a non-empty POSIX relative path")
        return None
    if value.startswith("/"):
        errors.append(
            f"{label}: must be a POSIX relative path (absolute paths are not allowed)"
        )
        return None
    if "\\" in value:
        errors.append(
            f"{label}: must be a POSIX relative path (backslashes are not allowed)"
        )
        return None
    if ".." in value.split("/"):
        errors.append(
            f"{label}: must be a POSIX relative path ('..' segments are not allowed)"
        )
        return None
    return value


def _entry_errors(entries: Any, errors: list[str]) -> None:
    if not isinstance(entries, list) or not entries:
        errors.append(
            "artifact_manifest.entries: must be a non-empty list of entries"
        )
        return

    paths: list[str] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, Mapping):
            errors.append(f"artifact_manifest.entries[{index}]: must be an object")
            continue
        path = _validate_relative_path(
            entry.get("path"), f"artifact_manifest.entries[{index}].path", errors
        )
        if path is not None:
            paths.append(path)
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not _SHA256_RE.match(digest):
            errors.append(
                f"artifact_manifest.entries[{index}].sha256: invalid sha256 digest"
            )

    if len(paths) == len(entries) and paths != sorted(paths):
        errors.append("artifact_manifest.entries: paths must be sorted")
    if len(paths) != len(set(paths)):
        errors.append("artifact_manifest.entries: paths must be unique")


def _migration_entry_errors(entries: Any, errors: list[str]) -> None:
    """Validate ``candidate.migration_set_entries`` ordering and shape."""
    if not isinstance(entries, list) or not entries:
        errors.append(
            "candidate.migration_set_entries: must be a non-empty list of entries"
        )
        return

    paths: list[str] = []
    for index, entry in enumerate(entries):
        label = f"candidate.migration_set_entries[{index}]"
        if not isinstance(entry, Mapping):
            errors.append(f"{label}: must be an object")
            continue
        path = _validate_relative_path(entry.get("path"), f"{label}.path", errors)
        if path is not None:
            paths.append(path)
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not _SHA256_RE.match(digest):
            errors.append(f"{label}.sha256: invalid sha256 digest")

    if len(paths) == len(entries) and paths != sorted(paths):
        errors.append("candidate.migration_set_entries: paths must be sorted")
    if len(paths) != len(set(paths)):
        errors.append("candidate.migration_set_entries: paths must be unique")


def verify_candidate_artifact(
    candidate: Mapping[str, Any], artifact_manifest: Mapping[str, Any]
) -> list[str]:
    """Return stable sorted errors binding *candidate* to *artifact_manifest*.

    ``[]`` means the candidate is internally consistent, the manifest is
    well-formed and sorted, and the artifact digest matches.
    """
    if not isinstance(candidate, Mapping):
        return ["candidate: must be an object"]
    if not isinstance(artifact_manifest, Mapping):
        return ["artifact_manifest: must be an object"]

    errors: list[str] = []

    for field in CANONICAL_FIELDS:
        if field not in candidate:
            errors.append(f"candidate.{field}: missing required candidate field")

    for field in sorted(set(candidate) - CANDIDATE_KEYS):
        errors.append(f"candidate.{field}: unknown top-level candidate field")

    for field in _NON_EMPTY_FIELDS:
        value = candidate.get(field)
        if not isinstance(value, str) or not value:
            errors.append(f"candidate.{field}: must be a non-empty string")

    source_sha = candidate.get("source_sha")
    if not isinstance(source_sha, str) or not _SOURCE_SHA_RE.match(source_sha):
        errors.append("candidate.source_sha: must be 40 lowercase hex characters")

    artifact_digest = candidate.get("artifact_digest")
    if not isinstance(artifact_digest, str) or not _SHA256_RE.match(artifact_digest):
        errors.append("candidate.artifact_digest: must match ^sha256:[0-9a-f]{64}$")

    release_config_identity = candidate.get("release_config_identity")
    if not isinstance(release_config_identity, str) or not _SHA256_RE.match(
        release_config_identity
    ):
        errors.append(
            "candidate.release_config_identity: must match ^sha256:[0-9a-f]{64}$"
        )

    migration_set = candidate.get("migration_set")
    if not isinstance(migration_set, list) or not migration_set:
        errors.append("candidate.migration_set: must be a non-empty list of paths")
    else:
        valid_paths: list[str] = []
        for index, path in enumerate(migration_set):
            checked = _validate_relative_path(
                path, f"candidate.migration_set[{index}]", errors
            )
            if checked is not None:
                valid_paths.append(checked)
        if len(valid_paths) == len(migration_set) and valid_paths != sorted(valid_paths):
            errors.append("candidate.migration_set: paths must be sorted")
        if len(valid_paths) != len(set(valid_paths)):
            errors.append("candidate.migration_set: paths must be unique")

    migration_entries = candidate.get("migration_set_entries")
    _migration_entry_errors(migration_entries, errors)

    declared_migration_identity = candidate.get("migration_set_identity")
    if not isinstance(declared_migration_identity, str) or not _SHA256_RE.match(
        declared_migration_identity
    ):
        errors.append(
            "candidate.migration_set_identity: must match ^sha256:[0-9a-f]{64}$"
        )
    elif isinstance(migration_entries, list):
        if declared_migration_identity != canonical_identity(migration_entries):
            errors.append(
                "candidate.migration_set_identity: does not match the "
                "recomputed migration set identity"
            )

    if isinstance(migration_set, list) and isinstance(migration_entries, list):
        entry_paths = [
            entry.get("path")
            for entry in migration_entries
            if isinstance(entry, Mapping)
        ]
        if entry_paths != migration_set:
            errors.append(
                "candidate.migration_set_entries: paths must match "
                "candidate.migration_set"
            )

    declared_identity = candidate.get("candidate_identity")
    if not isinstance(declared_identity, str) or not _SHA256_RE.match(
        declared_identity
    ):
        errors.append(
            "candidate.candidate_identity: must match ^sha256:[0-9a-f]{64}$"
        )
    elif declared_identity != canonical_identity(_candidate_fields(candidate)):
        errors.append(
            "candidate.candidate_identity: does not match the recomputed "
            "candidate identity"
        )

    entries = artifact_manifest.get("entries")
    _entry_errors(entries, errors)

    manifest_digest = artifact_manifest.get("artifact_digest")
    if not isinstance(manifest_digest, str) or not _SHA256_RE.match(manifest_digest):
        errors.append(
            "artifact_manifest.artifact_digest: must match ^sha256:[0-9a-f]{64}$"
        )
    else:
        if isinstance(entries, list):
            if manifest_digest != canonical_identity({"entries": entries}):
                errors.append(
                    "artifact_manifest.artifact_digest: does not match the "
                    "recomputed manifest identity"
                )
        if manifest_digest != artifact_digest:
            errors.append(
                "artifact_manifest.artifact_digest: does not match "
                "candidate.artifact_digest"
            )

    return sorted(set(errors))


def _h1_config_errors(
    root: Path, client_dir: Path, candidate: Mapping[str, Any]
) -> list[str]:
    report_path = Path(client_dir) / H1_REPORT_RELATIVE
    relative = _relative(Path(root), report_path)
    if not report_path.is_file():
        return [f"{relative}: missing H.1 foundation report"]
    try:
        report = _load_json(report_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{relative}: cannot parse H.1 foundation report: {exc}"]

    environments = report.get("environments")
    if not isinstance(environments, list):
        return [f"{relative}: environments must be a list"]
    production = next(
        (
            entry
            for entry in environments
            if isinstance(entry, Mapping)
            and entry.get("environment") == TARGET_ENVIRONMENT
        ),
        None,
    )
    if production is None:
        return [f"{relative}: missing {TARGET_ENVIRONMENT} environment entry"]
    if production.get("config_identity") != candidate.get("release_config_identity"):
        return [
            f"{relative}: production config_identity does not match "
            "candidate.release_config_identity"
        ]
    return []


def validate_candidate(root: Path, client_dir: Path) -> list[str]:
    """Validate the committed candidate + manifest against the fixture.

    Returns stable sorted errors; ``[]`` means the committed reference
    candidate is internally consistent, matches the committed artifact fixture,
    binds the repository migration set, and carries the H.1 production config
    identity.
    """
    root = Path(root)
    client_dir = Path(client_dir)
    release_dir = client_dir / RELEASE_RELATIVE
    candidate_path = release_dir / CANDIDATE_NAME
    manifest_path = release_dir / MANIFEST_NAME
    fixture_path = release_dir / ARTIFACT_FIXTURE_NAME
    candidate_rel = _relative(root, candidate_path)
    manifest_rel = _relative(root, manifest_path)

    errors: list[str] = []
    if not candidate_path.is_file():
        errors.append(f"{candidate_rel}: missing release candidate")
    if not manifest_path.is_file():
        errors.append(f"{manifest_rel}: missing artifact manifest")
    if errors:
        return sorted(set(errors))

    try:
        candidate = _load_json(candidate_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{candidate_rel}: cannot parse release candidate: {exc}"]
    try:
        manifest = _load_json(manifest_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"{manifest_rel}: cannot parse artifact manifest: {exc}"]

    if not isinstance(candidate, Mapping):
        return [f"{candidate_rel}: release candidate must be a JSON object"]
    if not isinstance(manifest, Mapping):
        return [f"{manifest_rel}: artifact manifest must be a JSON object"]

    errors.extend(verify_candidate_artifact(candidate, manifest))

    if candidate.get("source_sha") != FIXTURE_SOURCE_SHA:
        errors.append(
            f"{candidate_rel}: source_sha does not match the pinned fixture "
            "source SHA"
        )
    if candidate.get("build_version") != FIXTURE_BUILD_VERSION:
        errors.append(
            f"{candidate_rel}: build_version does not match the pinned fixture "
            "build version"
        )

    try:
        fresh_manifest = build_artifact_manifest(fixture_path)
    except (OSError, UnicodeError) as exc:
        errors.append(f"{manifest_rel}: cannot rebuild artifact manifest: {exc}")
    else:
        if manifest != fresh_manifest:
            errors.append(
                f"{manifest_rel}: does not match the committed artifact fixture"
            )

    source_sha = candidate.get("source_sha")
    build_version = candidate.get("build_version")
    if isinstance(source_sha, str) and isinstance(build_version, str):
        try:
            expected = build_candidate(
                root, client_dir, fixture_path, source_sha, build_version
            )
        except (
            OSError,
            UnicodeError,
            ValueError,
            KeyError,
            TypeError,
            json.JSONDecodeError,
        ) as exc:
            errors.append(f"{candidate_rel}: cannot rebuild release candidate: {exc}")
        else:
            for field in sorted(set(candidate) | set(expected)):
                if candidate.get(field) != expected.get(field):
                    errors.append(
                        f"{candidate_rel}: {field} does not match the "
                        "fixture-derived candidate"
                    )

    errors.extend(_h1_config_errors(root, client_dir, candidate))
    return sorted(set(errors))


def _parse_arguments(
    arguments: list[str],
) -> tuple[bool, str | None, str | None, str | None, list[str]]:
    write = False
    source_sha: str | None = None
    build_version: str | None = None
    artifact: str | None = None
    positional: list[str] = []

    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--write":
            write = True
        elif argument in ("--source-sha", "--build-version", "--artifact"):
            index += 1
            if index >= len(arguments):
                raise SystemExit(f"{argument} requires a value")
            value = arguments[index]
            if argument == "--source-sha":
                source_sha = value
            elif argument == "--build-version":
                build_version = value
            else:
                artifact = value
        elif argument.startswith("--"):
            raise SystemExit(f"unknown option: {argument}")
        else:
            positional.append(argument)
        index += 1

    return write, source_sha, build_version, artifact, positional


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate (default) or ``--write`` candidate + manifest.

    ``--write`` regenerates the committed fixture candidate/manifest from the
    fixture artifact and the committed H.1 report. ``--artifact``,
    ``--source-sha``, and ``--build-version`` override the fixture defaults so
    the candidate-build workflow can bind the real build.
    """
    arguments = list(sys.argv[1:] if argv is None else argv)
    write, source_sha, build_version, artifact, positional = _parse_arguments(
        arguments
    )

    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    if write:
        artifact_path = (
            Path(artifact)
            if artifact
            else client_dir / RELEASE_RELATIVE / ARTIFACT_FIXTURE_NAME
        )
        if not artifact_path.is_absolute():
            artifact_path = root / artifact_path

        manifest = build_artifact_manifest(artifact_path)
        candidate = build_candidate(
            root,
            client_dir,
            artifact_path,
            source_sha or FIXTURE_SOURCE_SHA,
            build_version or FIXTURE_BUILD_VERSION,
        )
        release_dir = client_dir / RELEASE_RELATIVE
        _write_json(release_dir / MANIFEST_NAME, manifest)
        _write_json(release_dir / CANDIDATE_NAME, candidate)
        print(_relative(root, release_dir / MANIFEST_NAME))
        print(_relative(root, release_dir / CANDIDATE_NAME))
        return 0

    errors = validate_candidate(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
