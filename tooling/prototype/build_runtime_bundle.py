from __future__ import annotations

import copy
import json
from pathlib import Path

import yaml

from tooling.design_contract.theme_contract import resolve_theme

from .validate_runtime_bundle import (
    validate_runtime_bundle,
    validate_runtime_bundle_against_design_contract,
)


def _invalid(message: str) -> ValueError:
    return ValueError(f"invalid runtime bundle: {message}")


def _load_yaml(path: Path) -> object:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, yaml.YAMLError) as exc:
        raise _invalid(f"cannot load {path}: {exc}") from exc


def _load_optional_yaml(path: Path) -> object:
    if not path.exists():
        return None
    return _load_yaml(path)


def _resolve_client_path(client_dir: Path, relative_path: object, label: str) -> Path:
    if not isinstance(relative_path, str) or not relative_path:
        raise _invalid(f"{label} path must be a non-empty string")
    path = (client_dir / relative_path).resolve()
    if not path.is_relative_to(client_dir.resolve()):
        raise _invalid(f"{label} path escapes client directory: {relative_path}")
    return path


def _load_brand_visual(client_dir: Path) -> dict:
    path = client_dir / "input" / "brand" / "brand-input.yaml"
    document = _load_optional_yaml(path)
    if not isinstance(document, dict):
        return {}
    visual = document.get("visual")
    return visual if isinstance(visual, dict) else {}


def _load_strategic_directions(client_dir: Path) -> dict[str, dict]:
    directory = client_dir / "directions"
    result: dict[str, dict] = {}
    if not directory.is_dir():
        return result
    for path in sorted([*directory.glob("direction-*.yaml"), *directory.glob("direction-*.yml")]):
        document = _load_yaml(path)
        if isinstance(document, dict):
            result[path.stem.removeprefix("direction-")] = document
    return result


def _compile_theme_layers(
    root: Path, client_dir: Path, manifest: dict, directions: dict[str, object]
) -> tuple[dict, dict[str, dict]]:
    theme_config = manifest.get("theme")
    if not isinstance(theme_config, dict) or not isinstance(theme_config.get("preset"), str):
        raise _invalid("manifest theme.preset must be an approved preset id")
    preset_id = theme_config["preset"]
    brand = _load_brand_visual(client_dir)
    strategic = _load_strategic_directions(client_dir)

    try:
        base_theme = resolve_theme(root, preset_id, brand, None)
        direction_themes: dict[str, dict] = {}
        for direction_id in sorted(directions, key=str):
            direction = directions[direction_id]
            density = direction.get("density") if isinstance(direction, dict) else None
            strategic_direction = strategic.get(direction_id)
            overrides = (
                strategic_direction.get("theme_overrides")
                if isinstance(strategic_direction, dict)
                else None
            )
            direction_themes[direction_id] = resolve_theme(
                root, preset_id, brand, overrides, density=density
            )
    except ValueError as exc:
        raise _invalid(str(exc)) from exc

    return base_theme, direction_themes


def compose_runtime_bundle(root: Path, client_dir: Path) -> dict:
    manifest_path = client_dir / "prototype" / "prototype-manifest.yaml"
    manifest = _load_yaml(manifest_path)
    if not isinstance(manifest, dict):
        raise _invalid("prototype manifest must be an object")

    manifest_directions = manifest.get("directions")
    if not isinstance(manifest_directions, dict):
        raise _invalid("manifest directions must be an object")

    directions: dict[str, object] = {}
    for direction_id in sorted(manifest_directions, key=str):
        path = _resolve_client_path(
            client_dir,
            manifest_directions[direction_id],
            f"direction {direction_id}",
        )
        try:
            direction = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise _invalid(f"cannot load direction {direction_id} from {path}: {exc}") from exc
        directions[direction_id] = direction

    fixture_path = _resolve_client_path(client_dir, manifest.get("fixture_pack"), "fixture_pack")
    fixtures = _load_yaml(fixture_path)

    review = copy.deepcopy(manifest.get("review"))
    if isinstance(review, dict):
        allowed_directions = review.pop("allowed_directions", None)
        allowed_values = review.pop("allowed_values", None)
        review["allowed_directions"] = (
            allowed_directions if allowed_directions is not None else allowed_values
        )

    base_theme, direction_themes = _compile_theme_layers(
        root, client_dir, manifest, directions
    )

    return {
        "version": manifest.get("version"),
        "client_id": manifest.get("client_id"),
        "default_direction": manifest.get("default_direction"),
        "directions": directions,
        "fixtures": fixtures,
        "theme": base_theme,
        "direction_themes": direction_themes,
        "resources": copy.deepcopy(manifest.get("resources", {})),
        "review": review,
    }


def build_runtime_bundle(root: Path, client_dir: Path, output_dir: Path) -> Path:
    bundle = compose_runtime_bundle(root, client_dir)
    errors = validate_runtime_bundle(bundle)
    errors.extend(validate_runtime_bundle_against_design_contract(root, bundle))
    if errors:
        raise _invalid("; ".join(sorted(errors)))

    try:
        serialized = json.dumps(bundle, indent=2, sort_keys=True, allow_nan=False) + "\n"
    except (TypeError, ValueError) as exc:
        raise _invalid(f"bundle is not JSON-compatible: {exc}") from exc

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{bundle['client_id']}.json"
    output_path.write_text(serialized, encoding="utf-8", newline="\n")
    return output_path
