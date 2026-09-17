"""Normalized capture-artifact metadata with stable, reproducible identity.

A [ScreenshotArtifact] is the durable record of one capture. Its identity is
derived from the normalized capture job (client/surface/screen-or-story/state/
direction/mix/viewport/scale/fixture/source commit) plus the hash of the
produced bytes, so two runs of the same governed job are byte-for-byte
comparable and traceable back to a source commit.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .errors import InvalidScreenshotMetadata

_REQUIRED_JOB_FIELDS = (
    "capture_id",
    "client_id",
    "surface",
    "state",
    "viewport",
    "device_scale_factor",
    "fixture_version",
    "source_commit_sha",
)


def _require_string(payload: dict, key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise InvalidScreenshotMetadata(f"screenshot artifact requires {key}")
    return value


def _optional_string(payload: dict, key: str) -> str | None:
    value = payload.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise InvalidScreenshotMetadata(f"screenshot artifact {key} must be a string")
    return value


def _require_positive_int(payload: dict, key: str) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise InvalidScreenshotMetadata(
            f"screenshot artifact {key} must be a positive integer"
        )
    return value


def _normalize_viewport(raw: object) -> dict:
    if not isinstance(raw, dict):
        raise InvalidScreenshotMetadata("screenshot artifact requires a viewport")
    width = raw.get("width")
    height = raw.get("height")
    if (
        not isinstance(width, int)
        or isinstance(width, bool)
        or width <= 0
        or not isinstance(height, int)
        or isinstance(height, bool)
        or height <= 0
    ):
        raise InvalidScreenshotMetadata("screenshot viewport dimensions are invalid")
    viewport: dict[str, Any] = {"width": width, "height": height}
    name = raw.get("name")
    if name is not None:
        if not isinstance(name, str) or not name.strip():
            raise InvalidScreenshotMetadata("screenshot viewport name is invalid")
        viewport["name"] = name
    return viewport


def _require_content_hash(value: object) -> str:
    if not isinstance(value, str) or not value.startswith("sha256:"):
        raise InvalidScreenshotMetadata("screenshot artifact requires a sha256 content hash")
    digest = value.split(":", 1)[1]
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise InvalidScreenshotMetadata("screenshot artifact content hash is malformed")
    return value


@dataclass(frozen=True)
class ScreenshotArtifact:
    """Immutable metadata for one deterministic capture."""

    capture_id: str
    client_id: str
    surface: str
    screen: str | None
    story: str | None
    state: str
    direction: str | None
    mix_ref: str | None
    viewport: dict
    device_scale_factor: float
    fixture_version: str
    source_commit_sha: str
    url: str
    filename: str
    path: str
    content_hash: str
    width: int | None
    height: int | None
    captured_at: str
    extra: dict = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.surface not in {"prototype", "widgetbook"}:
            raise InvalidScreenshotMetadata(f"unknown capture surface: {self.surface}")
        if self.surface == "prototype" and not self.screen:
            raise InvalidScreenshotMetadata("prototype captures require a screen")
        if self.surface == "widgetbook" and not self.story:
            raise InvalidScreenshotMetadata("widgetbook captures require a story")

    @classmethod
    def from_capture_job(
        cls,
        job: dict,
        *,
        path: str,
        content_hash: str,
        width: int | None,
        height: int | None,
        captured_at: str,
    ) -> "ScreenshotArtifact":
        if not isinstance(job, dict):
            raise InvalidScreenshotMetadata("capture job must be a mapping")
        for key in _REQUIRED_JOB_FIELDS:
            if key not in job:
                raise InvalidScreenshotMetadata(f"capture job is missing {key}")
        return cls(
            capture_id=_require_string(job, "capture_id"),
            client_id=_require_string(job, "client_id"),
            surface=_require_string(job, "surface"),
            screen=_optional_string(job, "screen"),
            story=_optional_string(job, "story"),
            state=_require_string(job, "state"),
            direction=_optional_string(job, "direction"),
            mix_ref=_optional_string(job, "mix_ref"),
            viewport=_normalize_viewport(job.get("viewport")),
            device_scale_factor=float(job.get("device_scale_factor", 1)),
            fixture_version=_require_string(job, "fixture_version"),
            source_commit_sha=_require_string(job, "source_commit_sha"),
            url=_require_string(job, "url"),
            filename=_require_string(job, "filename"),
            path=path,
            content_hash=_require_content_hash(content_hash),
            width=width,
            height=height,
            captured_at=_require_string({"captured_at": captured_at}, "captured_at"),
        )

    @classmethod
    def from_json(cls, payload: object) -> "ScreenshotArtifact":
        if not isinstance(payload, dict):
            raise InvalidScreenshotMetadata("screenshot artifact must be a mapping")
        viewport = _normalize_viewport(payload.get("viewport"))
        width = payload.get("width")
        height = payload.get("height")
        for label, value in (("width", width), ("height", height)):
            if value is not None and (
                not isinstance(value, int) or isinstance(value, bool) or value <= 0
            ):
                raise InvalidScreenshotMetadata(
                    f"screenshot artifact {label} must be a positive integer"
                )
        return cls(
            capture_id=_require_string(payload, "capture_id"),
            client_id=_require_string(payload, "client_id"),
            surface=_require_string(payload, "surface"),
            screen=_optional_string(payload, "screen"),
            story=_optional_string(payload, "story"),
            state=_require_string(payload, "state"),
            direction=_optional_string(payload, "direction"),
            mix_ref=_optional_string(payload, "mix_ref"),
            viewport=viewport,
            device_scale_factor=float(payload.get("device_scale_factor", 1)),
            fixture_version=_require_string(payload, "fixture_version"),
            source_commit_sha=_require_string(payload, "source_commit_sha"),
            url=_require_string(payload, "url"),
            filename=_require_string(payload, "filename"),
            path=_require_string(payload, "path"),
            content_hash=_require_content_hash(payload.get("content_hash")),
            width=width,
            height=height,
            captured_at=_require_string(payload, "captured_at"),
        )

    def to_json(self) -> dict:
        payload: dict[str, Any] = {
            "capture_id": self.capture_id,
            "client_id": self.client_id,
            "surface": self.surface,
            "screen": self.screen,
            "story": self.story,
            "state": self.state,
            "direction": self.direction,
            "mix_ref": self.mix_ref,
            "viewport": dict(self.viewport),
            "device_scale_factor": self.device_scale_factor,
            "fixture_version": self.fixture_version,
            "source_commit_sha": self.source_commit_sha,
            "url": self.url,
            "filename": self.filename,
            "path": self.path,
            "content_hash": self.content_hash,
            "width": self.width,
            "height": self.height,
            "captured_at": self.captured_at,
        }
        return payload
