"""Deterministic capture orchestration with atomic artifact publication.

The runner owns the *contract* of a capture: it validates the job, delegates
pixel production to a [ScreenshotCaptureBackend], verifies the output is a
usable, deterministic image, hashes it, publishes it atomically, and writes a
sidecar [ScreenshotArtifact]. A failure at any step leaves no successful
artifact behind — a partial or stale image can never masquerade as evidence.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Protocol

from .capture_models import ScreenshotArtifact
from .errors import (
    CaptureFailed,
    CaptureNotDeterministic,
    InvalidScreenshotMetadata,
    VisualQaError,
)

_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_dimensions(data: bytes) -> tuple[int, int] | None:
    """Return ``(width, height)`` for a PNG byte string, or ``None``."""
    if not isinstance(data, (bytes, bytearray)) or len(data) < 24:
        return None
    if bytes(data[:8]) != _PNG_SIGNATURE or bytes(data[12:16]) != b"IHDR":
        return None
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    if width <= 0 or height <= 0:
        return None
    return width, height


@dataclass(frozen=True)
class CaptureResult:
    """What a backend reports about a capture it produced."""

    deterministic: bool = True
    detail: str | None = None


class ScreenshotCaptureBackend(Protocol):
    """Produces a PNG for *job* at *destination*; transport only."""

    def capture(self, job: dict, destination: Path) -> CaptureResult:
        ...


def _default_clock() -> datetime:
    return datetime.now(timezone.utc)


def content_hash(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


class CaptureRunner:
    """Runs governed capture jobs and publishes identity-rich artifacts."""

    def __init__(
        self,
        backend: ScreenshotCaptureBackend,
        output_dir: Path,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._backend = backend
        self._output_dir = Path(output_dir).resolve()
        self._clock = clock or _default_clock

    @property
    def output_dir(self) -> Path:
        return self._output_dir

    def run(self, jobs: Iterable[dict]) -> list[ScreenshotArtifact]:
        artifacts: list[ScreenshotArtifact] = []
        for job in jobs:
            artifacts.append(self._capture_one(job))
        return artifacts

    def _capture_one(self, job: dict) -> ScreenshotArtifact:
        if not isinstance(job, dict):
            raise InvalidScreenshotMetadata("capture job must be a mapping")
        filename = job.get("filename")
        if not isinstance(filename, str) or not filename.strip():
            raise InvalidScreenshotMetadata("capture job requires a filename")
        if Path(filename).name != filename:
            raise InvalidScreenshotMetadata("capture filename must not contain a path")

        self._output_dir.mkdir(parents=True, exist_ok=True)
        # Backends (browsers) require a real image extension, so the unpublished
        # capture lives in a private temp directory until it is verified.
        temp_dir = self._output_dir / ".capture-tmp"
        temp_dir.mkdir(parents=True, exist_ok=True)
        temp = temp_dir / f"{uuid.uuid4().hex}-{filename}"

        try:
            if temp.exists():
                temp.unlink()
            try:
                result = self._backend.capture(job, temp)
            except VisualQaError:
                raise
            except Exception as error:  # noqa: BLE001 - normalize backend failures
                raise CaptureFailed(f"capture backend failed: {error}") from error

            if result is not None and not result.deterministic:
                raise CaptureNotDeterministic(
                    result.detail or "capture could not be shown to be deterministic"
                )

            if not temp.exists():
                raise CaptureFailed("capture backend produced no output")
            data = temp.read_bytes()
            if not data:
                raise CaptureFailed("capture backend produced an empty image")

            dimensions = png_dimensions(data)
            if dimensions is None:
                raise CaptureFailed("capture output is not a usable PNG image")
            width, height = dimensions
            expected = job.get("viewport")
            if (
                isinstance(expected, dict)
                and expected.get("width")
                and expected.get("height")
                and (width, height) != (expected["width"], expected["height"])
            ):
                raise InvalidScreenshotMetadata(
                    f"capture dimensions {width}x{height} do not match the "
                    f"job viewport {expected['width']}x{expected['height']}"
                )

            artifact = ScreenshotArtifact.from_capture_job(
                job,
                path=filename,
                content_hash=content_hash(data),
                width=width,
                height=height,
                captured_at=self._clock().isoformat(),
            )

            # Stage both files, then publish as a unit: if the sidecar cannot be
            # published, the PNG is rolled back so a capture is never half-recorded.
            published = self._output_dir / filename
            sidecar = self._output_dir / f"{filename}.artifact.json"
            staged_sidecar = temp_dir / f"{filename}.artifact.json"
            staged_sidecar.write_text(
                json.dumps(artifact.to_json(), indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            os.replace(temp, published)
            try:
                os.replace(staged_sidecar, sidecar)
            except OSError:
                published.unlink(missing_ok=True)
                raise
            return artifact
        finally:
            if temp.exists():
                temp.unlink()
            if temp_dir.exists() and not any(temp_dir.iterdir()):
                temp_dir.rmdir()


DEFAULT_BROWSER_SCRIPT = (
    Path(__file__).resolve().parents[1] / "screenshots" / "capture_web.mjs"
)


class ProcessCaptureBackend:
    """Invokes the transport-only headless-browser adapter over a JSON contract.

    The adapter (``tooling/screenshots/capture_web.mjs``) owns no QA policy: it
    receives a normalized job, renders it deterministically, writes a PNG, and
    returns machine-readable success/error JSON. This backend maps that contract
    onto typed QA errors.
    """

    def __init__(
        self,
        script_path: Path | None = None,
        *,
        node: str = "node",
        timeout_seconds: float = 180.0,
        settle_ms: int = 250,
    ) -> None:
        self._script = Path(script_path) if script_path else DEFAULT_BROWSER_SCRIPT
        self._node = node
        self._timeout = timeout_seconds
        self._settle_ms = settle_ms

    def available(self) -> bool:
        return self._script.exists() and shutil.which(self._node) is not None

    @property
    def script_path(self) -> Path:
        return self._script

    def capture(self, job: dict, destination: Path) -> CaptureResult:
        if not self._script.exists():
            raise CaptureFailed(f"browser adapter not found: {self._script}")
        if shutil.which(self._node) is None:
            raise CaptureFailed(f"node executable not found: {self._node}")

        with tempfile.TemporaryDirectory() as tmp:
            job_path = Path(tmp) / "job.json"
            job_path.write_text(json.dumps(job, sort_keys=True), encoding="utf-8")
            command = [
                self._node,
                str(self._script),
                "--job",
                str(job_path),
                "--out",
                str(destination),
                "--settle-ms",
                str(self._settle_ms),
            ]
            try:
                completed = subprocess.run(
                    command,
                    capture_output=True,
                    text=True,
                    timeout=self._timeout,
                    check=False,
                )
            except subprocess.TimeoutExpired as error:
                raise CaptureFailed(f"browser capture timed out: {error}") from error

            payload = self._parse_stdout(completed.stdout)
            if payload is None:
                detail = (completed.stderr or completed.stdout or "").strip()
                raise CaptureFailed(
                    f"browser adapter returned no result (exit {completed.returncode}): {detail}"
                )
            if not payload.get("ok", False):
                code = str(payload.get("code") or "capture_failed")
                message = str(payload.get("message") or "browser capture failed")
                if code == CaptureNotDeterministic.code:
                    raise CaptureNotDeterministic(message)
                raise CaptureFailed(message)
            return CaptureResult(
                deterministic=bool(payload.get("deterministic", True)),
                detail=payload.get("detail"),
            )

    @staticmethod
    def _parse_stdout(stdout: str) -> dict | None:
        for line in reversed((stdout or "").splitlines()):
            candidate = line.strip()
            if not candidate.startswith("{"):
                continue
            try:
                decoded = json.loads(candidate)
            except json.JSONDecodeError:
                continue
            if isinstance(decoded, dict):
                return decoded
        return None
