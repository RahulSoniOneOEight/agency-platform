from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

from tooling.knowledge.index_design_contract import build_indexes


_BINDINGS_RELATIVE = Path("design-contract") / "bindings" / "flutter"
_SCHEMA_PATH = (
    Path(__file__).resolve().parents[2]
    / "design-contract"
    / "schema"
    / "flutter-binding.schema.json"
)
_KIND_CATALOG = {"component": "components", "pattern": "patterns"}
_RUNTIME_DENSITIES = ("compact", "normal", "spacious")


def _schema() -> dict:
    return json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))


def _binding_documents(root: Path) -> list[tuple[Path, object, str | None]]:
    directory = root / _BINDINGS_RELATIVE
    if not directory.exists():
        return []
    documents: list[tuple[Path, object, str | None]] = []
    for path in sorted([*directory.glob("*.yaml"), *directory.glob("*.yml")]):
        try:
            document = yaml.safe_load(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, yaml.YAMLError) as exc:
            documents.append((path, None, f"{path}: cannot read binding: {exc}"))
            continue
        documents.append((path, document, None))
    return documents


def load_flutter_bindings(root: Path) -> dict[str, dict]:
    """Return the Flutter binding catalog keyed by canonical Design Contract ID."""
    bindings: dict[str, dict] = {}
    for _path, document, load_error in _binding_documents(root):
        if load_error or not isinstance(document, dict):
            continue
        binding_id = document.get("id")
        if isinstance(binding_id, str) and binding_id:
            bindings[binding_id] = document
    return bindings


def _schema_errors(binding: object) -> list[str]:
    binding_id = binding.get("id") if isinstance(binding, dict) else None
    label = binding_id if isinstance(binding_id, str) and binding_id else "<unknown>"
    validator = Draft202012Validator(_schema())
    errors = []
    for error in validator.iter_errors(binding):
        path = ".".join(str(part) for part in error.path) or "<root>"
        errors.append(f"binding {label}: {path}: {error.message}")
    return errors


def _validate_binding(
    binding_id: str, binding: object, catalogs: dict[str, dict]
) -> list[str]:
    if not isinstance(binding, dict):
        return [f"binding {binding_id}: binding document must be an object"]

    errors = _schema_errors(binding)
    kind = binding.get("kind")
    if kind not in _KIND_CATALOG:
        return errors

    catalog = catalogs[kind]
    contract = catalog.get(binding_id)
    if contract is None:
        other_kind = "pattern" if kind == "component" else "component"
        if binding_id in catalogs[other_kind]:
            errors.append(
                f"binding {binding_id}: kind {kind!r} does not match canonical "
                f"{other_kind} catalog"
            )
        else:
            errors.append(f"binding {binding_id}: canonical {kind} contract not found")
        return errors

    if binding.get("status") == "approved" and contract.get("status") != "approved":
        errors.append(
            f"binding {binding_id}: approved binding requires an approved canonical "
            f"{kind} contract"
        )

    variants = binding.get("variants")
    states = binding.get("states")
    density = binding.get("density")

    if isinstance(variants, dict):
        if kind == "pattern":
            if variants:
                errors.append(
                    f"binding {binding_id}: pattern bindings must not declare variants"
                )
        else:
            declared = contract.get("variants") or []
            for key in sorted(variants):
                if key not in declared:
                    errors.append(
                        f"binding {binding_id}: variant {key} is not declared by "
                        f"canonical contract"
                    )

    if isinstance(states, dict):
        if kind == "pattern":
            if states:
                errors.append(
                    f"binding {binding_id}: pattern bindings must not declare states"
                )
        else:
            declared = contract.get("states") or []
            for key in sorted(states):
                if key not in declared:
                    errors.append(
                        f"binding {binding_id}: state {key} is not declared by "
                        f"canonical contract"
                    )

    if isinstance(density, dict):
        if kind == "pattern":
            for key in sorted(density):
                if key not in _RUNTIME_DENSITIES:
                    errors.append(
                        f"binding {binding_id}: density key {key} is not a canonical "
                        f"runtime density"
                    )
        else:
            declared = contract.get("density") or []
            for key in sorted(density):
                if key not in declared:
                    errors.append(
                        f"binding {binding_id}: density {key} is not declared by "
                        f"canonical contract"
                    )

    if kind == "component":
        requires = contract.get("requires")
        if isinstance(requires, list):
            for required_id in requires:
                required = catalogs["component"].get(required_id)
                if not isinstance(required, dict) or required.get("status") != "approved":
                    errors.append(
                        f"binding {binding_id}: required component {required_id!r} has no "
                        f"approved canonical contract"
                    )

    return errors


def _duplicate_identifier_errors(entries: list[tuple[str, object]]) -> list[str]:
    errors: list[str] = []
    seen: dict[tuple[str, str], str] = {}
    for binding_id, binding in entries:
        if not isinstance(binding, dict):
            continue
        kind = binding.get("kind")
        implementation = binding.get("implementation")
        if kind not in _KIND_CATALOG or not isinstance(implementation, dict):
            continue
        registry_key = implementation.get("registry_key")
        if not isinstance(registry_key, str) or not registry_key:
            continue
        marker = (kind, registry_key)
        other = seen.get(marker)
        if other is None:
            seen[marker] = binding_id
        else:
            errors.append(
                f"binding {binding_id}: implementation registry_key {registry_key!r} "
                f"collides with binding {other}"
            )
    return errors


def validate_flutter_bindings(root: Path, bindings: dict | None = None) -> list[str]:
    """Return deterministic, stable-sorted binding catalog errors under *root*."""
    indexes = build_indexes(root)
    catalogs = {
        "component": indexes["components"],
        "pattern": indexes["patterns"],
    }
    errors: list[str] = []

    if bindings is None:
        entries: list[tuple[str, object]] = []
        seen: dict[str, Path] = {}
        for path, document, load_error in _binding_documents(root):
            if load_error is not None:
                errors.append(load_error)
                continue
            if not isinstance(document, dict):
                errors.append(f"{path}: binding document must be an object")
                continue
            binding_id = document.get("id")
            if not isinstance(binding_id, str) or not binding_id:
                errors.append(f"{path}: binding id must be a non-empty string")
                continue
            if binding_id in seen:
                errors.append(
                    f"duplicate binding id {binding_id!r} in {path} and {seen[binding_id]}"
                )
                continue
            seen[binding_id] = path
            entries.append((binding_id, document))
    else:
        entries = sorted(bindings.items())

    for binding_id, binding in entries:
        errors.extend(_validate_binding(binding_id, binding, catalogs))
    errors.extend(_duplicate_identifier_errors(entries))
    return sorted(set(errors))


def runtime_binding_errors(
    root: Path, runtime_direction: object, bindings: dict | None = None
) -> list[str]:
    """Return errors for runtime references lacking approved Flutter bindings."""
    if not isinstance(runtime_direction, dict):
        return ["runtime direction must be an object"]
    if bindings is None:
        bindings = load_flutter_bindings(root)

    errors: list[str] = []

    patterns = runtime_direction.get("patterns")
    if isinstance(patterns, list):
        for index, pattern_id in enumerate(patterns):
            if not isinstance(pattern_id, str):
                continue
            path = f"patterns.{index}"
            binding = bindings.get(pattern_id)
            if not isinstance(binding, dict) or binding.get("status") != "approved":
                errors.append(
                    f"{path} references canonical pattern {pattern_id!r} without an "
                    f"approved Flutter binding"
                )
            elif binding.get("kind") != "pattern":
                errors.append(
                    f"{path} canonical id {pattern_id!r} is bound as "
                    f"{binding.get('kind')!r}, not a pattern"
                )

    components = runtime_direction.get("components")
    if isinstance(components, list):
        density = runtime_direction.get("density")
        for index, component_id in enumerate(components):
            if not isinstance(component_id, str):
                continue
            path = f"components.{index}"
            binding = bindings.get(component_id)
            if not isinstance(binding, dict) or binding.get("status") != "approved":
                errors.append(
                    f"{path} references canonical component {component_id!r} without an "
                    f"approved Flutter binding"
                )
                continue
            if binding.get("kind") != "component":
                errors.append(
                    f"{path} canonical id {component_id!r} is bound as "
                    f"{binding.get('kind')!r}, not a component"
                )
                continue
            density_map = binding.get("density")
            if isinstance(density, str) and isinstance(density_map, dict):
                if density not in density_map:
                    errors.append(
                        f"{path} canonical component {component_id!r} binding does not "
                        f"support density {density!r}"
                    )

    variants = runtime_direction.get("component_variants")
    if isinstance(variants, list):
        for index, variant in enumerate(variants):
            if not isinstance(variant, dict):
                continue
            component_id = variant.get("component")
            variant_id = variant.get("variant")
            if not isinstance(component_id, str) or not isinstance(variant_id, str):
                continue
            path = f"component_variants.{index}"
            binding = bindings.get(component_id)
            if not isinstance(binding, dict) or binding.get("status") != "approved":
                errors.append(
                    f"{path} references component {component_id!r} without an approved "
                    f"Flutter binding"
                )
                continue
            variant_map = binding.get("variants")
            if not isinstance(variant_map, dict) or variant_id not in variant_map:
                errors.append(
                    f"{path} variant {variant_id!r} for {component_id!r} is not supported "
                    f"by the Flutter binding"
                )

    return sorted(set(errors))
