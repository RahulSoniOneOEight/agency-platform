from __future__ import annotations

import json
from pathlib import Path

import yaml

from tooling.resources.normalizer import normalize_bindings
from tooling.resources.validate_resources import validate_resource_artifacts

from .build_runtime_bundle import build_runtime_bundle
from .fixture_generator import generate_fixture_pack
from .project_direction import project_direction
from .screenshot_manifest import build_screenshot_manifest
from .validate_direction import validate_direction


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"expected mapping in {path}")
    return data


def _brand_preset(client_dir: Path) -> str:
    path = client_dir / "input" / "brand" / "brand-input.yaml"
    if not path.exists():
        raise ValueError("brand input missing: input/brand/brand-input.yaml")
    data = _load_yaml(path)
    visual = data.get("visual")
    if (
        not isinstance(visual, dict)
        or not isinstance(visual.get("preset"), str)
        or not visual["preset"]
    ):
        raise ValueError("brand input visual.preset must be an approved preset id")
    return visual["preset"]


def _discover_direction_paths(client_dir: Path) -> list[tuple[str, Path]]:
    directions_dir = client_dir / "directions"
    found = []
    for path in sorted(directions_dir.glob("direction-*.yaml")):
        direction_key = path.stem.removeprefix("direction-")
        found.append((direction_key, path))

    keys = [key for key, _ in found]
    if "a" not in keys or "b" not in keys:
        raise ValueError("at least directions a and b are required")
    if len(found) > 3:
        raise ValueError("at most 3 directions are supported")
    if any(key not in {"a", "b", "c"} for key in keys):
        raise ValueError("only direction IDs a, b, and optional c are supported")
    return found


def _resource_bindings(root: Path, client_dir: Path) -> dict:
    selection_path = client_dir / "resources" / "selection.yaml"
    candidates_path = client_dir / "resources" / "candidates.yaml"
    if not selection_path.exists() and not candidates_path.exists():
        return {}
    errors = validate_resource_artifacts(root, client_dir)
    if errors:
        raise ValueError("invalid resource artifacts: " + "; ".join(errors))
    selection = _load_yaml(selection_path)
    candidates = _load_yaml(candidates_path)
    return normalize_bindings(selection, candidates)


def compose_prototype(root: Path, client_dir: Path) -> Path:
    profile_path = client_dir / "derived" / "client-profile.yaml"
    if not profile_path.exists():
        raise ValueError("derived/client-profile.yaml missing")
    profile = _load_yaml(profile_path)
    industry = profile.get("industry")
    if not isinstance(industry, str):
        raise ValueError("client profile industry missing")

    if not (client_dir / "directions" / "comparison.yaml").exists():
        raise ValueError("directions/comparison.yaml missing")

    discovered = _discover_direction_paths(client_dir)

    prototype_dir = client_dir / "prototype"
    runtime_dir = prototype_dir / "runtime"
    fixtures_dir = prototype_dir / "fixtures"
    qa_dir = prototype_dir / "qa"
    screenshots_dir = prototype_dir / "screenshots"
    for directory in (runtime_dir, fixtures_dir, qa_dir, screenshots_dir):
        directory.mkdir(parents=True, exist_ok=True)

    for stale in runtime_dir.glob("direction-*.json"):
        stale.unlink()

    directions: dict[str, str] = {}
    seen_ids: set[str] = set()
    for direction_key, path in discovered:
        direction = _load_yaml(path)
        errors = validate_direction(direction)
        if errors:
            raise ValueError(f"invalid direction {direction_key}: {'; '.join(errors)}")
        logical_id = direction["id"]
        if logical_id != direction_key:
            raise ValueError(f"direction file {path.name} declares id {logical_id!r}, expected {direction_key!r}")
        if logical_id in seen_ids:
            raise ValueError(f"duplicate direction id: {logical_id}")
        seen_ids.add(logical_id)

        runtime_direction = project_direction(direction)
        runtime_path = runtime_dir / f"direction-{direction_key}.json"
        runtime_path.write_text(
            json.dumps(runtime_direction, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        directions[direction_key] = f"prototype/runtime/direction-{direction_key}.json"

    fixture_path = fixtures_dir / "demo.yaml"
    fixture_path.write_text(
        yaml.safe_dump(generate_fixture_pack(industry, seed=108), sort_keys=False),
        encoding="utf-8",
    )

    available_ids = list(directions.keys())
    client_id = str(profile.get("id") or client_dir.name)
    manifest = {
        "version": 1,
        "client_id": client_id,
        "runtime": "apps/prototype_app",
        "default_direction": available_ids[0],
        "directions": directions,
        "fixture_pack": "prototype/fixtures/demo.yaml",
        "theme": {"preset": _brand_preset(client_dir)},
        "review": {"query_parameter": "direction", "allowed_values": available_ids},
    }
    resources = _resource_bindings(root, client_dir)
    if resources:
        manifest["resources"] = resources

    manifest_path = prototype_dir / "prototype-manifest.yaml"
    manifest_path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")

    screenshot_path = qa_dir / "screenshot-manifest.yaml"
    screenshot_path.write_text(
        yaml.safe_dump(build_screenshot_manifest(client_id, available_ids), sort_keys=False),
        encoding="utf-8",
    )

    build_runtime_bundle(
        root,
        client_dir,
        root / "apps" / "prototype_app" / "assets" / "generated",
    )
    return manifest_path
