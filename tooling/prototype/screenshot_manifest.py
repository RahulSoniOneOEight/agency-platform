"""Deterministic screenshot-manifest contract (v2) with v1 read compatibility.

A manifest is a *capture plan*: an ordered set of capture jobs whose identity is
derived only from canonical, normalized input (never wall-clock time). v2 jobs
carry enough information to reproduce a capture exactly:

``client_id``, ``surface``, ``screen``/``story``, ``state``, ``direction``,
``mix_ref``, ``viewport``, ``device_scale_factor``, ``fixture_version`` and
``source_commit_sha``.

v1 manifests (``directions`` × ``viewports``) are still accepted and expanded
into normalized v2 jobs so existing clients keep loading; new writes are v2.
"""

from __future__ import annotations

import hashlib
import json
from urllib.parse import urlencode

from tooling.visual_qa.errors import InvalidCaptureJob

MANIFEST_VERSION = 2

STANDARD_VIEWPORTS = [
    {"name": "mobile-small", "width": 360, "height": 800},
    {"name": "mobile-medium", "width": 390, "height": 844},
    {"name": "mobile-large", "width": 430, "height": 932},
    {"name": "tablet", "width": 768, "height": 1024},
    {"name": "desktop", "width": 1440, "height": 900},
]

VIEWPORT_BY_NAME = {viewport["name"]: dict(viewport) for viewport in STANDARD_VIEWPORTS}

ALLOWED_SURFACES = frozenset({"prototype", "widgetbook"})

# The runtime contract supports direction IDs a, b, and optional c.
ALLOWED_DIRECTIONS = frozenset({"a", "b", "c"})


def _require_mapping(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise InvalidCaptureJob(f"{label} must be a mapping")
    return value


def _require_non_empty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise InvalidCaptureJob(f"{label} must be a non-empty string")
    return value.strip()


def _optional_non_empty_string(value: object, label: str) -> str | None:
    if value is None:
        return None
    return _require_non_empty_string(value, label)


def _resolve_viewport(raw: object) -> dict:
    viewport = _require_mapping(raw, "capture viewport")
    name = viewport.get("name")
    width = viewport.get("width")
    height = viewport.get("height")

    if name is not None:
        preset_name = _require_non_empty_string(name, "viewport name")
        preset = VIEWPORT_BY_NAME.get(preset_name)
        if preset is None:
            raise InvalidCaptureJob(f"unknown governed viewport preset: {preset_name}")
        if width is None and height is None:
            return {"name": preset_name, "width": preset["width"], "height": preset["height"]}
        if width != preset["width"] or height != preset["height"]:
            raise InvalidCaptureJob(
                f"viewport preset {preset_name} does not match explicit dimensions"
            )
        return {"name": preset_name, "width": preset["width"], "height": preset["height"]}

    if not isinstance(width, int) or not isinstance(height, int) or isinstance(width, bool):
        raise InvalidCaptureJob("capture viewport requires integer width and height")
    if width <= 0 or height <= 0:
        raise InvalidCaptureJob("capture viewport dimensions must be positive")
    return {"width": width, "height": height}


def _normalize_job(
    raw: object,
    *,
    client_id: str,
    fixture_version: str,
    index: int,
) -> dict:
    job = _require_mapping(raw, f"capture job {index}")
    surface = _require_non_empty_string(job.get("surface"), f"job {index} surface")
    if surface not in ALLOWED_SURFACES:
        raise InvalidCaptureJob(f"job {index} has unsupported surface: {surface}")

    state = _require_non_empty_string(job.get("state"), f"job {index} state")
    viewport = _resolve_viewport(job.get("viewport"))

    device_scale_factor = job.get("device_scale_factor", 1)
    if (
        not isinstance(device_scale_factor, (int, float))
        or isinstance(device_scale_factor, bool)
        or device_scale_factor <= 0
    ):
        raise InvalidCaptureJob(f"job {index} device_scale_factor must be positive")

    mix_ref = _optional_non_empty_string(job.get("mix_ref"), f"job {index} mix_ref")

    if surface == "prototype":
        direction = _require_non_empty_string(job.get("direction"), f"job {index} direction")
        if direction not in ALLOWED_DIRECTIONS:
            raise InvalidCaptureJob(f"job {index} has unknown direction: {direction}")
        screen = _require_non_empty_string(job.get("screen"), f"job {index} screen")
        if job.get("story") is not None:
            raise InvalidCaptureJob(f"job {index} prototype job must not declare a story")
        return {
            "client_id": client_id,
            "surface": surface,
            "screen": screen,
            "story": None,
            "state": state,
            "direction": direction,
            "mix_ref": mix_ref,
            "viewport": viewport,
            "device_scale_factor": device_scale_factor,
            "fixture_version": fixture_version,
        }

    story = _require_non_empty_string(job.get("story"), f"job {index} story")
    if job.get("screen") is not None:
        raise InvalidCaptureJob(f"job {index} widgetbook job must not declare a screen")
    if job.get("direction") is not None:
        raise InvalidCaptureJob(f"job {index} widgetbook job must not declare a direction")
    return {
        "client_id": client_id,
        "surface": surface,
        "screen": None,
        "story": story,
        "state": state,
        "direction": None,
        "mix_ref": mix_ref,
        "viewport": viewport,
        "device_scale_factor": device_scale_factor,
        "fixture_version": fixture_version,
    }


def _normalize_v2(data: dict) -> dict:
    client_id = _require_non_empty_string(data.get("client_id"), "client_id")
    fixture_version = _require_non_empty_string(data.get("fixture_version"), "fixture_version")
    raw_jobs = data.get("jobs")
    if not isinstance(raw_jobs, list) or not raw_jobs:
        raise InvalidCaptureJob("manifest jobs must be a non-empty list")
    jobs = [
        _normalize_job(
            raw,
            client_id=client_id,
            fixture_version=fixture_version,
            index=index,
        )
        for index, raw in enumerate(raw_jobs)
    ]
    return {
        "version": MANIFEST_VERSION,
        "client_id": client_id,
        "fixture_version": fixture_version,
        "viewports": [dict(viewport) for viewport in STANDARD_VIEWPORTS],
        "jobs": jobs,
    }


def _normalize_v1(data: dict) -> dict:
    client_id = _require_non_empty_string(data.get("client_id"), "client_id")
    fixture_version = _optional_non_empty_string(
        data.get("fixture_version"), "fixture_version"
    ) or "v1"
    directions = data.get("directions")
    if not isinstance(directions, list) or not directions:
        raise InvalidCaptureJob("v1 manifest requires a non-empty directions list")
    viewports = data.get("viewports")
    if not isinstance(viewports, list) or not viewports:
        raise InvalidCaptureJob("v1 manifest requires a non-empty viewports list")

    jobs: list[dict] = []
    for direction in directions:
        clean_direction = _require_non_empty_string(direction, "v1 direction")
        if clean_direction not in ALLOWED_DIRECTIONS:
            raise InvalidCaptureJob(f"v1 manifest has unknown direction: {clean_direction}")
        for viewport in viewports:
            resolved = _resolve_viewport(viewport)
            jobs.append(
                {
                    "client_id": client_id,
                    "surface": "prototype",
                    "screen": None,
                    "story": None,
                    "state": "default",
                    "direction": clean_direction,
                    "mix_ref": None,
                    "viewport": resolved,
                    "device_scale_factor": 1,
                    "fixture_version": fixture_version,
                }
            )
    return {
        "version": MANIFEST_VERSION,
        "client_id": client_id,
        "fixture_version": fixture_version,
        "viewports": [dict(viewport) for viewport in STANDARD_VIEWPORTS],
        "jobs": jobs,
    }


def normalize_manifest(data: object) -> dict:
    """Return the internal canonical v2 form of *data* (v1 or v2 input).

    The returned mapping is an internal normalized capture-job representation
    (it repeats ``client_id``/``fixture_version`` per job for self-contained
    jobs); the *wire* manifest validated by
    ``client-projects/schema/screenshot-manifest.schema.json`` is the
    ``build_screenshot_manifest`` shape.
    """
    manifest = _require_mapping(data, "screenshot manifest")
    version = manifest.get("version", 1)
    if version == 2:
        return _normalize_v2(manifest)
    if version == 1:
        return _normalize_v1(manifest)
    raise InvalidCaptureJob(f"unsupported screenshot manifest version: {version!r}")


def manifest_directions(data: object) -> set[str]:
    """Direction IDs declared by a v1 or v2 manifest (empty for widgetbook-only)."""
    normalized = normalize_manifest(data)
    return {
        job["direction"]
        for job in normalized["jobs"]
        if isinstance(job.get("direction"), str)
    }


def _canonical_scale_factor(value: object) -> int | float:
    """Canonicalize a scale factor so ``1`` and ``1.0`` share one identity."""
    number = float(value)  # type: ignore[arg-type]
    if number.is_integer():
        return int(number)
    return number


def capture_identity(job: dict, source_commit_sha: str) -> str:
    """Deterministic ``sha256:<hex>`` identity for a normalized capture job."""
    payload = {
        "client_id": job["client_id"],
        "surface": job["surface"],
        "screen": job["screen"],
        "story": job["story"],
        "state": job["state"],
        "direction": job["direction"],
        "mix_ref": job["mix_ref"],
        "viewport": {
            "name": job["viewport"].get("name"),
            "width": job["viewport"]["width"],
            "height": job["viewport"]["height"],
        },
        "device_scale_factor": _canonical_scale_factor(job["device_scale_factor"]),
        "fixture_version": job["fixture_version"],
        "source_commit_sha": source_commit_sha,
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _capture_url(job: dict, base_url: str) -> str:
    base = base_url.rstrip("/")
    query: dict[str, str] = {}
    if job["surface"] == "prototype":
        query["client"] = job["client_id"]
        if job["direction"]:
            query["direction"] = job["direction"]
    else:
        query["story"] = job["story"]
    if job["state"] != "default":
        query["state"] = job["state"]
    if job["mix_ref"]:
        query["mix"] = job["mix_ref"]
    return f"{base}/?{urlencode(query)}"


def _slug(value: str) -> str:
    return "".join(
        character if character.isalnum() or character in "-_" else "-"
        for character in value
    ).strip("-")


def _capture_filename(job: dict, capture_id: str) -> str:
    short = capture_id.split(":", 1)[1][:12]
    slug = _slug(job["screen"] or job["story"] or "surface")
    direction = _slug(job["direction"] or "na")
    state = _slug(job["state"])
    return (
        f"{short}-{job['surface']}-{slug}-{state}-{direction}"
        f"-{job['viewport']['width']}x{job['viewport']['height']}.png"
    )


def build_capture_jobs(
    manifest: object,
    base_url: str = "http://localhost:8080",
    source_commit_sha: str = "",
    screens_by_direction: dict[str, list[str]] | None = None,
) -> list[dict]:
    """Expand a v1/v2 manifest into deterministic, identity-rich capture jobs.

    v1 manifests are read-compatible for planning/validation, but a v1 job has no
    governed screen. Passing ``screens_by_direction`` upgrades those legacy jobs
    into capturable v2 jobs; without it a screen-less prototype job is rejected
    with a typed error rather than producing an artifact that cannot be
    reproduced.
    """
    if not isinstance(source_commit_sha, str):
        raise InvalidCaptureJob("source_commit_sha must be a string")
    normalized = normalize_manifest(manifest)
    jobs: list[dict] = []
    for job in normalized["jobs"]:
        if (
            job["surface"] == "prototype"
            and job["screen"] is None
            and screens_by_direction
        ):
            screens = screens_by_direction.get(job["direction"] or "")
            if screens:
                job = {**job, "screen": screens[0]}
        if job["surface"] == "prototype" and job["screen"] is None:
            raise InvalidCaptureJob(
                "legacy screenshot manifests are read-only: upgrade to a v2 "
                "manifest with explicit screens (or pass screens_by_direction) "
                "before capturing"
            )
        capture_id = capture_identity(job, source_commit_sha)
        jobs.append(
            {
                **job,
                "source_commit_sha": source_commit_sha,
                "capture_id": capture_id,
                "url": _capture_url(job, base_url),
                "filename": _capture_filename(job, capture_id),
            }
        )
    return jobs


def build_screenshot_manifest(
    client_id: str,
    directions: list[str],
    screens_by_direction: dict[str, list[str]] | None = None,
    fixture_version: str = "v1",
) -> dict:
    """Write a v2 capture manifest for *client_id*.

    ``screens_by_direction`` names the governed screens to capture per
    direction. Every declared direction must name at least one screen: a v2
    capture job is screen-scoped, never a route-level guess.
    """
    clean_directions = [str(direction).lower() for direction in directions]
    for direction in clean_directions:
        if direction not in ALLOWED_DIRECTIONS:
            raise InvalidCaptureJob(f"unknown direction: {direction}")

    screens = screens_by_direction or {}
    jobs: list[dict] = []
    for direction in clean_directions:
        direction_screens = list(screens.get(direction) or [])
        if not direction_screens:
            raise InvalidCaptureJob(
                f"direction {direction} declares no screens to capture"
            )
        for screen in direction_screens:
            for viewport in STANDARD_VIEWPORTS:
                jobs.append(
                    {
                        "surface": "prototype",
                        "screen": screen,
                        "state": "default",
                        "direction": direction,
                        "viewport": {"name": viewport["name"]},
                        "device_scale_factor": 1,
                    }
                )

    manifest = {
        "version": MANIFEST_VERSION,
        "client_id": client_id,
        "fixture_version": fixture_version,
        "viewports": [dict(viewport) for viewport in STANDARD_VIEWPORTS],
        "jobs": jobs,
    }
    normalize_manifest(manifest)
    return manifest
