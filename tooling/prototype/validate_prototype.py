from __future__ import annotations

from pathlib import Path

REQUIRED_PATHS = (
    "tooling/prototype/__init__.py",
    "tooling/prototype/validate_direction.py",
    "tooling/prototype/fixture_generator.py",
    "tooling/prototype/screenshot_manifest.py",
    "tooling/prototype/validate_visual_qa.py",
    "templates/prototype-manifest.yaml",
    "templates/visual-qa-findings.yaml",
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
