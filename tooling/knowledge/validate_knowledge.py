from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

from tooling.knowledge.index_design_contract import build_indexes
from tooling.knowledge.io import load_json, load_yaml, yaml_files


VALIDATION_TARGETS = (
    ("resources/registry/schema/reference.schema.json", ("resources/registry/github", "resources/registry/providers")),
    ("tooling/normalization/schema/normalization.schema.json", ("tooling/normalization/manifests",)),
    ("design-contract/schema/component.schema.json", ("design-contract/components",)),
    ("design-contract/schema/pattern.schema.json", ("design-contract/patterns",)),
    ("design-contract/schema/journey.schema.json", ("design-contract/journeys",)),
    ("presets/schema/preset.schema.json", ("presets/business-model", "presets/industry", "presets/use-case")),
    ("experience-patterns/schema/experience-pattern.schema.json", ("experience-patterns",)),
    ("client-projects/schema/client-profile.schema.json", ("tooling/knowledge/fixtures/clients",)),
)


def _schema_errors(root: Path) -> list[str]:
    errors: list[str] = []
    for schema_rel, directories in VALIDATION_TARGETS:
        schema_path = root / schema_rel
        if not schema_path.exists():
            errors.append(f"missing schema: {schema_rel}")
            continue
        validator = Draft202012Validator(load_json(schema_path))
        for directory in directories:
            for file_path in yaml_files(root / directory):
                if file_path.name.startswith("_"):
                    continue
                data = load_yaml(file_path)
                for error in validator.iter_errors(data):
                    location = ".".join(str(item) for item in error.absolute_path)
                    errors.append(f"{file_path.relative_to(root)}:{location}: {error.message}")
    return errors


def _cross_reference_errors(root: Path) -> list[str]:
    errors: list[str] = []
    references = {load_yaml(path)["id"]: load_yaml(path) for path in yaml_files(root / "resources/registry/github")}
    patterns = {load_yaml(path)["id"]: load_yaml(path) for path in yaml_files(root / "experience-patterns") if path.parent.name != "schema"}

    for path in yaml_files(root / "tooling/normalization/manifests"):
        manifest = load_yaml(path)
        if manifest["reference_id"] not in references:
            errors.append(f"{path.relative_to(root)}: unknown reference_id {manifest['reference_id']}")

    for ref_id, item in references.items():
        if item.get("status") == "reference_only" and item.get("code_reuse_allowed"):
            errors.append(f"reference {ref_id}: reference_only cannot allow code reuse")
        license_status = item.get("license", {}).get("status")
        if item.get("code_reuse_allowed") and license_status != "resolved":
            errors.append(f"reference {ref_id}: code reuse requires resolved license")

    for preset_dir in ("business-model", "industry", "use-case"):
        for path in yaml_files(root / "presets" / preset_dir):
            preset = load_yaml(path)
            for archetype in preset.get("candidate_archetypes", []):
                if archetype not in patterns:
                    errors.append(f"{path.relative_to(root)}: unknown candidate archetype {archetype}")

    indexes = build_indexes(root)
    component_ids = set(indexes["components"])
    pattern_ids = set(indexes["patterns"])
    for pattern_id, pattern in indexes["patterns"].items():
        for component in pattern.get("compatible_components", []):
            if component not in component_ids:
                errors.append(f"pattern {pattern_id}: unknown component {component}")
    for journey_id, journey in indexes["journeys"].items():
        for pattern in journey.get("patterns", []):
            if pattern not in pattern_ids:
                errors.append(f"journey {journey_id}: unknown pattern {pattern}")

    return errors


def validate_all(root: Path) -> list[str]:
    return _schema_errors(root) + _cross_reference_errors(root)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    errors = validate_all(root)
    if errors:
        print("Knowledge Platform validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print("Knowledge Platform validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
