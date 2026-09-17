from __future__ import annotations

import json
from pathlib import Path

import yaml

from .project_direction import validate_runtime_direction
from .screenshot_manifest import InvalidCaptureJob, manifest_directions

REQUIRED_PATHS = (
    "tooling/prototype/__init__.py",
    "tooling/prototype/runtime_direction.schema.json",
    "tooling/prototype/validate_direction.py",
    "tooling/prototype/project_direction.py",
    "tooling/prototype/fixture_generator.py",
    "tooling/prototype/screenshot_manifest.py",
    "tooling/prototype/capture_screenshots.py",
    "tooling/prototype/validate_visual_qa.py",
    "tooling/prototype/build_prototype.py",
    "tooling/prototype/approved_experience.py",
    "packages/agency_flutter_ui/pubspec.yaml",
    "packages/agency_flutter_ui/lib/agency_flutter_ui.dart",
    "apps/prototype_app/pubspec.yaml",
    "apps/prototype_app/lib/main.dart",
    "apps/widgetbook/pubspec.yaml",
    "apps/widgetbook/lib/main.dart",
    "templates/prototype-manifest.yaml",
    "templates/visual-qa-findings.yaml",
    "templates/approved-experience.yaml",
)

_ALLOWED_DIRECTION_IDS = {"a", "b", "c"}


def _validate_manifest(manifest_path: Path) -> list[str]:
    try:
        return _validate_manifest_inner(manifest_path)
    except Exception as exc:  # noqa: BLE001 - validator must never raise
        return [f"{manifest_path}: {exc}"]


def _validate_manifest_inner(manifest_path: Path) -> list[str]:
    errors: list[str] = []
    label = str(manifest_path)
    try:
        manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        return [f"{label}: invalid yaml: {exc}"]
    if not isinstance(manifest, dict):
        return [f"{label}: manifest must be a mapping"]

    directions = manifest.get("directions")
    if not isinstance(directions, dict):
        return [f"{label}: directions must be a mapping"]

    keys = list(directions.keys())
    if not 2 <= len(keys) <= 3:
        errors.append(f"{label}: expected 2-3 directions, found {len(keys)}")
    if not {"a", "b"}.issubset(keys):
        errors.append(f"{label}: directions must include a and b")
    if any(key not in _ALLOWED_DIRECTION_IDS for key in keys):
        errors.append(f"{label}: only direction ids a, b, and optional c are supported")

    client_dir = manifest_path.parent.parent
    for key in keys:
        rel_path = directions[key]
        if not isinstance(rel_path, str) or not rel_path:
            errors.append(f"{label}: direction {key} path must be a non-empty string")
            continue
        runtime_path = (client_dir / rel_path).resolve()
        if not runtime_path.is_relative_to(client_dir.resolve()):
            errors.append(f"{label}: direction {key} path escapes client directory: {rel_path}")
            continue
        if not runtime_path.exists():
            errors.append(f"{label}: missing runtime artifact {rel_path}")
            continue
        try:
            runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            errors.append(f"{label}: cannot parse {rel_path}: {exc}")
            continue
        if not isinstance(runtime, dict):
            errors.append(f"{label}: {rel_path}: runtime direction must be a mapping")
            continue
        errors.extend(f"{label}: {rel_path}: {error}" for error in validate_runtime_direction(runtime))
        if runtime.get("id") != key:
            errors.append(f"{label}: {rel_path} declares id {runtime.get('id')!r}, expected {key!r}")

    review = manifest.get("review")
    if review is None:
        review = {}
    if not isinstance(review, dict):
        errors.append(f"{label}: review must be a mapping")
    else:
        allowed_values = review.get("allowed_values")
        if allowed_values != keys:
            errors.append(f"{label}: review.allowed_values {allowed_values!r} must equal direction keys {keys!r}")

    screenshot_path = manifest_path.parent / "qa" / "screenshot-manifest.yaml"
    if not screenshot_path.exists():
        return errors + [f"{label}: missing screenshot manifest"]
    try:
        screenshot = yaml.safe_load(screenshot_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        return errors + [f"{label}: invalid screenshot manifest yaml: {exc}"]
    screenshot_dirs: set[str] | None = None
    try:
        screenshot_dirs = manifest_directions(screenshot)
    except InvalidCaptureJob as exc:
        errors.append(f"{label}: invalid screenshot manifest: {exc}")
    else:
        if screenshot_dirs != set(keys):
            errors.append(
                f"{label}: screenshot manifest directions must equal {keys!r}"
            )

    return errors


def _validate_client_prototypes(root: Path) -> list[str]:
    errors: list[str] = []
    projects = root / "client-projects"
    if not projects.exists():
        return errors
    for manifest_path in sorted(projects.glob("**/prototype/prototype-manifest.yaml")):
        errors.extend(_validate_manifest(manifest_path))
    return errors


def validate_prototype_platform(root: Path) -> list[str]:
    errors: list[str] = []
    for rel in REQUIRED_PATHS:
        if not (root / rel).exists():
            errors.append(f"missing prototype-platform path: {rel}")
    errors.extend(_validate_client_prototypes(root))
    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    errors = validate_prototype_platform(root)
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Prototype Platform validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
