from __future__ import annotations

from pathlib import Path

import yaml

from tooling.workflow.client_paths import ClientPaths

from .fixture_generator import generate_fixture_pack
from .screenshot_manifest import build_screenshot_manifest
from .validate_direction import validate_direction


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"expected mapping in {path}")
    return data


def compose_prototype(root: Path, client_dir: Path) -> Path:
    del root
    client_paths = ClientPaths.for_client(client_dir)
    profile_path = client_paths.read_client_profile()
    if not profile_path.exists():
        raise ValueError("derived/client-profile.yaml missing")
    profile = _load_yaml(profile_path)
    industry = profile.get("industry")
    if not isinstance(industry, str) or not industry:
        raise ValueError("client profile industry missing")

    directions: dict[str, str] = {}
    for direction_id in ("a", "b", "c"):
        path = client_dir / "directions" / f"direction-{direction_id}.yaml"
        if not path.exists():
            raise ValueError(f"direction-{direction_id}.yaml missing")
        direction = _load_yaml(path)
        errors = validate_direction(direction)
        if errors:
            raise ValueError(f"invalid direction {direction_id}: {'; '.join(errors)}")
        directions[direction_id] = f"directions/direction-{direction_id}.yaml"

    comparison = client_dir / "directions" / "comparison.yaml"
    if not comparison.exists():
        raise ValueError("directions/comparison.yaml missing")

    prototype_dir = client_dir / "prototype"
    fixtures_dir = prototype_dir / "fixtures"
    qa_dir = prototype_dir / "qa"
    screenshots_dir = prototype_dir / "screenshots"
    for directory in (fixtures_dir, qa_dir, screenshots_dir):
        directory.mkdir(parents=True, exist_ok=True)

    fixture_path = fixtures_dir / "demo.yaml"
    fixture_path.write_text(
        yaml.safe_dump(generate_fixture_pack(industry, seed=108), sort_keys=False),
        encoding="utf-8",
    )

    client_id = str(profile.get("id") or client_dir.name)
    manifest = {
        "version": 1,
        "client_id": client_id,
        "runtime": "apps/prototype_app",
        "default_direction": "a",
        "directions": directions,
        "fixture_pack": "prototype/fixtures/demo.yaml",
        "theme": {"seed_color": "#6750A4"},
        "review": {"query_parameter": "direction", "allowed_values": ["a", "b", "c"]},
    }
    manifest_path = prototype_dir / "prototype-manifest.yaml"
    manifest_path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")

    screenshot_path = qa_dir / "screenshot-manifest.yaml"
    screenshot_path.write_text(
        yaml.safe_dump(build_screenshot_manifest(client_id, ["a", "b", "c"]), sort_keys=False),
        encoding="utf-8",
    )
    return manifest_path
