from __future__ import annotations

import sys
from pathlib import Path


REQUIRED_PATHS = (
    ".github/workflows/validate.yml",
    ".github/workflows/flutter-ci.yml",
    "client-projects",
    "design-contract/components",
    "design-contract/patterns",
    "design-contract/themes",
    "design-contract/tokens",
    "design-contract/variants",
    "docs/source/agency_flutter_opencode_delivery_system_v2.txt",
    "docs/architecture.md",
    "docs/client-delivery.md",
    "docs/design-system.md",
    "docs/opencode-rules.md",
    "docs/reference-policy.md",
    "packages/agency_flutter_ui",
    "penpot/design-system",
    "penpot/starter-designs",
    "resources/approved",
    "resources/github",
    "resources/icons",
    "resources/images",
    "resources/incoming",
    "resources/motion",
    "resources/penpot",
    "resources/registry",
    "resources/rejected",
    "starters/b2b-commerce",
    "starters/booking",
    "starters/customer-portal",
    "starters/ecommerce",
    "starters/grocery",
    "starters/marketplace",
    "tooling/generators",
    "tooling/golden-tests",
    "tooling/normalization",
    "tooling/screenshots",
    "tooling/validation",
    "tooling/visual-review",
    "AGENTS.md",
    "REFERENCE_POLICY.md",
    "DESIGN_SYSTEM.md",
    "VISUAL_QA.md",
    "PENPOT_MAPPING.md",
    "README.md",
    "melos.yaml",
    ".gitignore",
)


def missing_required_paths(root: Path) -> list[str]:
    """Return required platform-control paths that do not exist under *root*."""
    return [relative for relative in REQUIRED_PATHS if not (root / relative).exists()]


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    missing = missing_required_paths(root)
    if missing:
        print("Repository validation failed. Missing required paths:")
        for path in missing:
            print(f"- {path}")
        return 1

    print(f"Repository validation passed: {len(REQUIRED_PATHS)} required paths present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
