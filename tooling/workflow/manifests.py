"""Frozen per-attempt execution manifests.

Each stage attempt produces one create-only manifest under
``workflow/executions/<run-id>/attempt-<n>.yaml``. The manifest is the evidence
tier of the two-tier completion model: it records the inputs, outputs,
checkpoints, validator evidence, rulings, and deviations observed while an
attempt ran. Once an attempt completes or fails the manifest is frozen and can
never be rewritten.
"""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator


MANIFEST_STATUSES = ("in_progress", "completed", "failed")
VALIDATOR_STATUSES = ("passed", "failed")

EXECUTIONS_DIR_NAME = "executions"

_SCHEMA_RELATIVE = (
    Path("client-projects") / "schema" / "workflow-execution-manifest.schema.json"
)
_SCHEMA_PATH = Path(__file__).resolve().parents[2] / _SCHEMA_RELATIVE


class ManifestError(RuntimeError):
    """Raised when an execution manifest cannot be loaded or written."""


class ManifestImmutable(ManifestError):
    """Raised when a frozen manifest is mutated or overwritten."""


class ArtifactManifestMismatch(ManifestError):
    """Raised when one artifact path is recorded with two different hashes."""


class StageCompletionGateFailed(ManifestError):
    """Raised when completion is attempted without the required validator evidence."""


@dataclass(frozen=True)
class ArtifactRef:
    path: str
    sha256: str
    authority: str | None = None


@dataclass(frozen=True)
class CheckpointRecord:
    name: str
    at: str


@dataclass(frozen=True)
class ValidatorEvidence:
    name: str
    status: str
    at: str
    evidence_ref: str | None = None


@dataclass(frozen=True)
class ExecutionManifest:
    run_id: str
    client_id: str
    stage: str
    attempt: int
    source_commit_sha: str
    started_at: str
    status: str = "in_progress"
    inputs: tuple[ArtifactRef, ...] = ()
    outputs: tuple[ArtifactRef, ...] = ()
    checkpoints: tuple[CheckpointRecord, ...] = ()
    validators: tuple[ValidatorEvidence, ...] = ()
    rulings: tuple[Mapping[str, Any], ...] = ()
    deviations: tuple[Mapping[str, Any], ...] = ()
    completed_at: str | None = None
    failure_reason: str | None = None

    @classmethod
    def start(
        cls,
        *,
        run_id: str,
        client_id: str,
        stage: str,
        attempt: int,
        source_commit_sha: str,
        started_at: str,
        inputs: Sequence[ArtifactRef] = (),
    ) -> "ExecutionManifest":
        return cls(
            run_id=run_id,
            client_id=client_id,
            stage=stage,
            attempt=attempt,
            source_commit_sha=source_commit_sha,
            started_at=started_at,
            status="in_progress",
            inputs=tuple(inputs),
        )

    def _ensure_mutable(self) -> None:
        if self.status != "in_progress":
            raise ManifestImmutable(
                f"manifest {self.run_id}/attempt-{self.attempt} is {self.status} and frozen"
            )

    def with_checkpoint(self, name: str, *, at: str) -> "ExecutionManifest":
        self._ensure_mutable()
        return replace(self, checkpoints=self.checkpoints + (CheckpointRecord(name=name, at=at),))

    def with_output(self, ref: ArtifactRef) -> "ExecutionManifest":
        self._ensure_mutable()
        for existing in self.outputs:
            if existing.path == ref.path:
                if existing.sha256 != ref.sha256:
                    raise ArtifactManifestMismatch(
                        f"artifact {ref.path!r} already recorded with sha256 {existing.sha256}"
                    )
                return self
        return replace(self, outputs=self.outputs + (ref,))

    def with_validators(
        self, results: Sequence[ValidatorEvidence]
    ) -> "ExecutionManifest":
        self._ensure_mutable()
        return replace(self, validators=self.validators + tuple(results))

    def with_ruling(self, record: Mapping[str, Any]) -> "ExecutionManifest":
        self._ensure_mutable()
        return replace(self, rulings=self.rulings + (dict(record),))

    def with_deviation(self, record: Mapping[str, Any]) -> "ExecutionManifest":
        self._ensure_mutable()
        return replace(self, deviations=self.deviations + (dict(record),))

    def complete(
        self, *, at: str, required_validators: Sequence[str]
    ) -> "ExecutionManifest":
        self._ensure_mutable()
        passed = {evidence.name for evidence in self.validators if evidence.status == "passed"}
        missing = [name for name in required_validators if name not in passed]
        if missing:
            raise StageCompletionGateFailed(
                f"required validators not passed: {', '.join(missing)}"
            )
        return replace(self, status="completed", completed_at=at, failure_reason=None)

    def fail(self, *, reason: str, at: str) -> "ExecutionManifest":
        self._ensure_mutable()
        return replace(self, status="failed", failure_reason=reason, completed_at=at)

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "client_id": self.client_id,
            "stage": self.stage,
            "attempt": self.attempt,
            "source_commit_sha": self.source_commit_sha,
            "started_at": self.started_at,
            "status": self.status,
            "inputs": [_artifact_to_dict(ref) for ref in self.inputs],
            "outputs": [_artifact_to_dict(ref) for ref in self.outputs],
            "checkpoints": [
                {"name": record.name, "at": record.at} for record in self.checkpoints
            ],
            "validators": [
                {
                    "name": evidence.name,
                    "status": evidence.status,
                    "at": evidence.at,
                    "evidence_ref": evidence.evidence_ref,
                }
                for evidence in self.validators
            ],
            "rulings": [dict(record) for record in self.rulings],
            "deviations": [dict(record) for record in self.deviations],
            "completed_at": self.completed_at,
            "failure_reason": self.failure_reason,
        }

    @classmethod
    def from_dict(cls, data: Mapping[str, Any]) -> "ExecutionManifest":
        status = data.get("status", "in_progress")
        if status not in MANIFEST_STATUSES:
            raise ManifestError(f"unknown manifest status: {status!r}")
        return cls(
            run_id=data["run_id"],
            client_id=data["client_id"],
            stage=data["stage"],
            attempt=int(data["attempt"]),
            source_commit_sha=data["source_commit_sha"],
            started_at=data["started_at"],
            status=status,
            inputs=tuple(_artifact_from_dict(item) for item in data.get("inputs", [])),
            outputs=tuple(_artifact_from_dict(item) for item in data.get("outputs", [])),
            checkpoints=tuple(
                CheckpointRecord(name=item["name"], at=item["at"])
                for item in data.get("checkpoints", [])
            ),
            validators=tuple(
                ValidatorEvidence(
                    name=item["name"],
                    status=item["status"],
                    at=item["at"],
                    evidence_ref=item.get("evidence_ref"),
                )
                for item in data.get("validators", [])
            ),
            rulings=tuple(dict(item) for item in data.get("rulings", [])),
            deviations=tuple(dict(item) for item in data.get("deviations", [])),
            completed_at=data.get("completed_at"),
            failure_reason=data.get("failure_reason"),
        )


def _artifact_to_dict(ref: ArtifactRef) -> dict[str, Any]:
    return {"path": ref.path, "sha256": ref.sha256, "authority": ref.authority}


def _artifact_from_dict(data: Mapping[str, Any]) -> ArtifactRef:
    return ArtifactRef(
        path=data["path"],
        sha256=data["sha256"],
        authority=data.get("authority"),
    )


def sha256_file(path: Path) -> str:
    """Return the bare 64-character lowercase hex SHA-256 digest of *path*."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest_relpath(run_id: str, attempt: int) -> str:
    return f"workflow/{EXECUTIONS_DIR_NAME}/{run_id}/attempt-{attempt}.yaml"


def manifest_path(client_dir: Path, run_id: str, attempt: int) -> Path:
    return Path(client_dir) / manifest_relpath(run_id, attempt)


def _atomic_write_yaml(path: Path, data: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(
        dir=str(path.parent), prefix=f"{path.name}.", suffix=".tmp"
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            yaml.safe_dump(dict(data), stream, sort_keys=False)
        os.replace(tmp_path, path)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def write_manifest_create_only(path: Path, manifest: ExecutionManifest) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        existing = load_manifest(path)
        if existing.status != "in_progress":
            raise ManifestImmutable(
                f"{path}: manifest is {existing.status} and cannot be rewritten"
            )
    _atomic_write_yaml(path, manifest.to_dict())


def load_manifest(path: Path) -> ExecutionManifest:
    path = Path(path)
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, yaml.YAMLError) as exc:
        raise ManifestError(f"{path}: cannot load manifest: {exc}") from exc
    if not isinstance(raw, Mapping):
        raise ManifestError(f"{path}: manifest must be a mapping")
    return ExecutionManifest.from_dict(raw)


def validate_manifest(data: Mapping[str, Any]) -> list[str]:
    """Return deterministic schema-shape errors for *data* (empty == valid)."""
    if not isinstance(data, Mapping):
        return ["manifest must be a mapping"]
    try:
        schema = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"cannot load execution manifest schema: {exc}"]
    validator = Draft202012Validator(schema)
    errors: list[str] = []
    for error in validator.iter_errors(dict(data)):
        location = ".".join(str(part) for part in error.path) or "<root>"
        errors.append(f"{location}: {error.message}")
    return sorted(errors)
