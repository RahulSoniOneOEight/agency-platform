from __future__ import annotations

from pathlib import Path

import yaml


def client_asset_candidates(client_dir: Path, requirement: dict) -> list[dict]:
    manifest = client_dir / "input" / "assets" / "asset-manifest.yaml"
    if not manifest.exists():
        return []
    data = yaml.safe_load(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return []
    role = requirement.get("role")
    resource_type = requirement.get("type")
    found: list[dict] = []
    for asset in data.get("assets") or []:
        if not isinstance(asset, dict):
            continue
        if asset.get("role") != role:
            continue
        if asset.get("type", resource_type) != resource_type:
            continue
        item = {
            "id": str(asset["id"]),
            "source": "client",
            "type": resource_type,
            "role": role,
            "asset": {key: value for key, value in asset.items() if key not in {"id", "role", "type", "scores"}},
            "scores": asset.get("scores", {}),
            "provenance": {"source": "client", "usage_status": "client-supplied"},
        }
        found.append(item)
    return found
