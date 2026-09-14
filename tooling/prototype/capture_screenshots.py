from __future__ import annotations

from pathlib import Path
from urllib.parse import urlencode

import yaml


def build_capture_jobs(manifest: dict, base_url: str = "http://localhost:8080") -> list[dict]:
    client_id = str(manifest.get("client_id") or "")
    directions = manifest.get("directions") or []
    viewports = manifest.get("viewports") or []
    if not client_id or not isinstance(directions, list) or not isinstance(viewports, list):
        raise ValueError("invalid screenshot manifest")
    jobs: list[dict] = []
    for direction in directions:
        for viewport in viewports:
            width = int(viewport["width"])
            height = int(viewport["height"])
            name = str(viewport.get("name") or f"{width}x{height}")
            query = urlencode({"client": client_id, "direction": direction})
            jobs.append(
                {
                    "client_id": client_id,
                    "direction": direction,
                    "viewport": name,
                    "width": width,
                    "height": height,
                    "url": f"{base_url.rstrip('/')}/?{query}",
                    "filename": f"{direction}-{name}-{width}x{height}.png",
                }
            )
    return jobs


def load_capture_jobs(path: Path, base_url: str = "http://localhost:8080") -> list[dict]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("screenshot manifest must be a mapping")
    return build_capture_jobs(data, base_url)
