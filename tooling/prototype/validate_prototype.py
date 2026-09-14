from __future__ import annotations

from pathlib import Path

REQUIRED_PATHS = (
    "tooling/prototype/__init__.py",
    "tooling/prototype/direction_schema.json",
    "tooling/prototype/validate_direction.py",
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


def validate_prototype_platform(root: Path) -> list[str]:
    errors: list[str] = []
    for rel in REQUIRED_PATHS:
        if not (root / rel).exists():
            errors.append(f"missing prototype-platform path: {rel}")
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
