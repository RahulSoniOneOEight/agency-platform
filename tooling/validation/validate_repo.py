from __future__ import annotations

import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

import yaml  # noqa: E402

from tooling.design_contract.flutter_bindings import (  # noqa: E402
    load_flutter_bindings,
    runtime_binding_errors,
    validate_flutter_bindings,
)
from tooling.design_contract.generate_flutter_bindings import (  # noqa: E402
    check_flutter_bindings_fresh,
)
from tooling.design_contract.generate_resolved_themes import (  # noqa: E402
    check_resolved_bundles_fresh,
)
from tooling.design_contract.theme_contract import (  # noqa: E402
    validate_direction_theme_overrides,
    validate_theme_presets,
    validate_token_catalogs,
)
from tooling.prototype.validate_runtime_bundle import (  # noqa: E402
    validate_runtime_bundle,
    validate_runtime_bundle_against_design_contract,
)


REQUIRED_PATHS = (
    ".github/workflows/validate.yml",
    ".github/workflows/flutter-ci.yml",
    "client-projects",
    "client-projects/schema/client-profile.schema.json",
    "client-projects/schema/input/client-input.schema.json",
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
    "resources/policies/sourcing-policy.yaml",
    "resources/registry",
    "resources/registry/providers/pexels.yaml",
    "resources/registry/icons/semantic-icons.yaml",
    "resources/registry/motion/motion-assets.yaml",
    "resources/registry/schema/resource-requirements.schema.json",
    "resources/registry/schema/resource-candidates.schema.json",
    "resources/registry/schema/resource-selection.schema.json",
    "resources/registry/schema/resource-provenance.schema.json",
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
    "tooling/resources",
    "tooling/resources/provider_router.py",
    "tooling/resources/pexels_client.py",
    "tooling/resources/scorer.py",
    "tooling/resources/selector.py",
    "tooling/resources/normalizer.py",
    "tooling/resources/validate_resources.py",
    "tooling/screenshots",
    "tooling/validation",
    "tooling/validation/test_resource_selection.py",
    "tooling/validation/test_resource_integration.py",
    "tooling/validation/test_runtime_bundle.py",
    "tooling/visual-review",
    "tooling/workflow/client_input.py",
    "design-contract/schema/flutter-binding.schema.json",
    "design-contract/schema/foundation-tokens.schema.json",
    "design-contract/schema/semantic-tokens.schema.json",
    "design-contract/schema/theme-preset.schema.json",
    "design-contract/tokens/foundation.yaml",
    "design-contract/tokens/semantic.yaml",
    "design-contract/themes/premium-modern.yaml",
    "design-contract/themes/compact-commerce.yaml",
    "design-contract/themes/editorial-commerce.yaml",
    "tooling/design_contract/theme_contract.py",
    "tooling/design_contract/generate_resolved_themes.py",
    "tooling/validation/test_theme_contract.py",
    "apps/prototype_app/lib/runtime/runtime_theme.dart",
    "packages/agency_flutter_ui/lib/themes/agency_theme_tokens.dart",
    "design-contract/bindings/flutter",
    "tooling/design_contract/flutter_bindings.py",
    "tooling/design_contract/generate_flutter_bindings.py",
    "tooling/validation/test_flutter_bindings.py",
    "apps/prototype_app/lib/registry/generated_design_bindings.dart",
    "tooling/prototype/build_runtime_bundle.py",
    "tooling/prototype/validate_runtime_bundle.py",
    "apps/prototype_app/assets/generated",
    "apps/prototype_app/lib/runtime/prototype_runtime.dart",
    "apps/prototype_app/lib/runtime/runtime_loader.dart",
    "apps/prototype_app/lib/runtime/runtime_exception.dart",
    "apps/prototype_app/lib/runtime/resource_binding.dart",
    "apps/prototype_app/lib/registry/design_contract_resolver.dart",
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


def generated_runtime_bundle_errors(root: Path) -> list[str]:
    """Return B.1B generated client runtime bundle structural errors under *root*.

    Every checked client whose prototype manifest exists must have a generated
    bundle that exists, parses, and is valid against the runtime contract and the
    design contract. Freshness against a fresh compile is enforced separately by
    ``theme_contract_errors`` (single source of truth).
    """
    errors: list[str] = []
    projects = root / "client-projects"
    if not projects.exists():
        return errors

    output_dir = root / "apps" / "prototype_app" / "assets" / "generated"
    for manifest_path in sorted(projects.glob("**/prototype/prototype-manifest.yaml")):
        client_dir = manifest_path.parent.parent
        try:
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, yaml.YAMLError) as exc:
            errors.append(f"{manifest_path}: cannot read prototype manifest: {exc}")
            continue
        if not isinstance(manifest, dict):
            errors.append(f"{manifest_path}: prototype manifest must be an object")
            continue

        client_id = manifest.get("client_id")
        if not isinstance(client_id, str) or not client_id:
            errors.append(f"{manifest_path}: client_id must be a non-empty string")
            continue

        bundle_path = output_dir / f"{client_id}.json"
        if not bundle_path.exists():
            errors.append(
                f"{bundle_path}: missing generated runtime bundle for client {client_id!r}"
            )
            continue

        try:
            bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            errors.append(f"{bundle_path}: cannot parse generated runtime bundle: {exc}")
            continue

        bundle_errors = validate_runtime_bundle(bundle)
        bundle_errors.extend(
            validate_runtime_bundle_against_design_contract(root, bundle)
        )
        if bundle_errors:
            errors.extend(f"{bundle_path}: {error}" for error in sorted(bundle_errors))

    return errors


def theme_contract_errors(root: Path) -> list[str]:
    """Return B.1E token/theme contract, freshness, and direction-override errors.

    Reuses the compiler/validator APIs: token catalogs, theme presets, checked
    resolved-bundle freshness, and strategic direction theme-override allowlists.
    """
    errors: list[str] = []
    errors.extend(validate_token_catalogs(root))
    errors.extend(validate_theme_presets(root))
    errors.extend(check_resolved_bundles_fresh(root))

    projects = root / "client-projects"
    if projects.exists():
        direction_paths = sorted(
            [
                *projects.glob("**/directions/direction-*.yaml"),
                *projects.glob("**/directions/direction-*.yml"),
            ]
        )
        for direction_path in direction_paths:
            try:
                direction = yaml.safe_load(direction_path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, yaml.YAMLError) as exc:
                errors.append(f"{direction_path}: cannot read direction: {exc}")
                continue
            overrides = (
                direction.get("theme_overrides") if isinstance(direction, dict) else None
            )
            for error in validate_direction_theme_overrides(overrides):
                errors.append(f"{direction_path}: {error}")

    return sorted(set(errors))


def flutter_binding_errors(root: Path) -> list[str]:
    """Return B.1D Flutter binding catalog, projection, and runtime parity errors.

    Every checked runtime direction must resolve its patterns, components,
    component variants, and density through approved Flutter bindings, and the
    checked Dart projection must byte-match a fresh deterministic render.
    """
    errors: list[str] = []
    errors.extend(validate_flutter_bindings(root))
    errors.extend(check_flutter_bindings_fresh(root))

    bindings = load_flutter_bindings(root)
    projects = root / "client-projects"
    if projects.exists():
        for direction_path in sorted(
            projects.glob("**/prototype/runtime/direction-*.json")
        ):
            try:
                direction = json.loads(direction_path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError) as exc:
                errors.append(f"{direction_path}: cannot parse runtime direction: {exc}")
                continue
            for error in runtime_binding_errors(root, direction, bindings):
                errors.append(f"{direction_path}: {error}")

    return sorted(set(errors))


def main() -> int:
    root = _ROOT
    missing = missing_required_paths(root)
    bundle_errors = generated_runtime_bundle_errors(root)
    binding_errors = flutter_binding_errors(root)
    theme_errors = theme_contract_errors(root)
    if missing or bundle_errors or binding_errors or theme_errors:
        print("Repository validation failed.")
        if missing:
            print("Missing required paths:")
            for path in missing:
                print(f"- {path}")
        if bundle_errors:
            print("Generated runtime bundle errors:")
            for error in bundle_errors:
                print(f"- {error}")
        if binding_errors:
            print("Flutter design binding errors:")
            for error in binding_errors:
                print(f"- {error}")
        if theme_errors:
            print("Token/theme contract errors:")
            for error in theme_errors:
                print(f"- {error}")
        return 1

    print(
        f"Repository validation passed: {len(REQUIRED_PATHS)} required paths present, "
        "generated runtime bundles are fresh, Flutter design bindings are valid, and "
        "token/theme contracts are valid."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
