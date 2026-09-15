from __future__ import annotations

import copy
import math
import re
from pathlib import Path

import yaml


FOUNDATION_TOKENS_RELATIVE = Path("design-contract") / "tokens" / "foundation.yaml"
SEMANTIC_TOKENS_RELATIVE = Path("design-contract") / "tokens" / "semantic.yaml"
THEMES_RELATIVE = Path("design-contract") / "themes"

PRESET_STATUSES = ("experimental", "approved", "deprecated")

CANONICAL_GROUPS = (
    "color",
    "typography",
    "spacing",
    "radius",
    "elevation",
    "size",
    "density",
    "motion",
    "breakpoints",
)

CANONICAL_DENSITIES = ("compact", "normal", "spacious")

# Per-group numeric leaves. ``None`` means every key in the group is numeric.
_NUMERIC_LEAVES: dict[str, tuple[str, ...] | None] = {
    "spacing": None,
    "radius": None,
    "elevation": None,
    "size": None,
    "breakpoints": None,
    "typography": (
        "display",
        "headline",
        "title",
        "body",
        "label",
        "line_height_body",
        "weight_regular",
        "weight_emphasis",
    ),
    "motion": ("fast_ms", "normal_ms", "slow_ms"),
}

# Per-group string leaves that must be non-empty literals.
_STRING_LEAVES: dict[str, tuple[str, ...]] = {
    "typography": ("font_family", "font_fallback", "heading_emphasis"),
    "motion": ("easing",),
}

_COLOR_PATTERN = re.compile(r"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
_REFERENCE_PATTERN = re.compile(
    r"^\{foundation\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*\}$"
)
_RESOLUTION_REFERENCE_PATTERN = re.compile(
    r"^\{foundation\.([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)\}$"
)

# Raw client brand keys that map onto approved semantic override paths (R2/R8).
BRAND_OVERRIDE_MAP: dict[str, tuple[str, str]] = {
    "primary_color": ("color", "primary"),
    "secondary_color": ("color", "secondary"),
    "font_family": ("typography", "font_family"),
    "font_fallback": ("typography", "font_fallback"),
}

_TYPOGRAPHY_SUBGROUPS = ("size", "line_height", "weight")
_MOTION_DURATIONS = ("fast_ms", "normal_ms", "slow_ms")

SEMANTIC_KEYS: dict[str, tuple[str, ...]] = {
    "color": (
        "primary",
        "on_primary",
        "secondary",
        "on_secondary",
        "surface",
        "surface_muted",
        "text_primary",
        "text_secondary",
        "border",
        "error",
        "on_error",
    ),
    "typography": (
        "font_family",
        "font_fallback",
        "display",
        "headline",
        "title",
        "body",
        "label",
        "line_height_body",
        "weight_regular",
        "weight_emphasis",
        "heading_emphasis",
    ),
    "spacing": ("inline", "control", "card", "tile", "section"),
    "radius": ("control", "card"),
    "elevation": ("card", "overlay"),
    "size": ("control_height", "control_height_compact", "icon"),
    "density": ("default",),
    "motion": ("fast_ms", "normal_ms", "slow_ms", "easing"),
    "breakpoints": ("mobile", "tablet", "desktop"),
}


def _stringify_keys(value):
    """Recursively coerce every mapping key to ``str`` for YAML numeric keys."""
    if isinstance(value, dict):
        return {str(key): _stringify_keys(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_stringify_keys(item) for item in value]
    return value


def _load_catalog(root: Path, relative: Path, label: str) -> dict:
    path = root / relative
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ValueError(f"{label}: cannot read {path}: {exc}") from exc
    try:
        document = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ValueError(f"{label}: invalid YAML in {path}: {exc}") from exc
    if not isinstance(document, dict):
        raise ValueError(f"{label}: expected a mapping at {path}")
    return _stringify_keys(document)


def load_foundation_tokens(root: Path) -> dict:
    """Load the foundation token catalog under *root* with normalized string keys."""
    return _load_catalog(root, FOUNDATION_TOKENS_RELATIVE, "foundation")


def load_semantic_tokens(root: Path) -> dict:
    """Load the semantic token catalog under *root* with normalized string keys."""
    return _load_catalog(root, SEMANTIC_TOKENS_RELATIVE, "semantic")


def _describe(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return f"boolean {value!r}"
    if isinstance(value, dict):
        return "a mapping"
    if isinstance(value, list):
        return "a list"
    if isinstance(value, str):
        return "a string"
    if isinstance(value, (int, float)):
        return f"number {value!r}"
    return f"{type(value).__name__}"


def _numeric_errors(
    path: str, value, *, minimum: float | None = None, exclusive: bool = False
) -> list[str]:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return [f"{path}: expected a number, got {_describe(value)}"]
    if isinstance(value, float) and not math.isfinite(value):
        return [f"{path}: expected a finite number, got {value!r}"]
    if minimum is not None:
        if exclusive and value <= minimum:
            return [f"{path}: expected a number greater than {minimum}, got {value!r}"]
        if not exclusive and value < minimum:
            return [f"{path}: expected a number >= {minimum}, got {value!r}"]
    return []


def _validate_foundation_color(prefix: str, group: dict) -> list[str]:
    errors: list[str] = []
    for family in sorted(group):
        shades = group[family]
        if not isinstance(shades, dict):
            errors.append(
                f"{prefix}.{family}: expected a mapping of color shades, "
                f"got {_describe(shades)}"
            )
            continue
        for shade in sorted(shades):
            value = shades[shade]
            if not isinstance(value, str) or not _COLOR_PATTERN.match(value):
                errors.append(
                    f"{prefix}.{family}.{shade}: invalid color {value!r}; "
                    f"expected #RRGGBB or #AARRGGBB"
                )
    return errors


def _validate_foundation_typography(prefix: str, group: dict) -> list[str]:
    errors: list[str] = []
    for subgroup in _TYPOGRAPHY_SUBGROUPS:
        if subgroup not in group:
            errors.append(f"{prefix}.{subgroup}: missing required typography subgroup")
            continue
        values = group[subgroup]
        if not isinstance(values, dict):
            errors.append(
                f"{prefix}.{subgroup}: expected a mapping, got {_describe(values)}"
            )
            continue
        for key in sorted(values):
            errors.extend(
                _numeric_errors(
                    f"{prefix}.{subgroup}.{key}", values[key], minimum=0, exclusive=True
                )
            )
    for subgroup in sorted(set(group) - set(_TYPOGRAPHY_SUBGROUPS)):
        errors.append(f"{prefix}.{subgroup}: unknown typography subgroup")
    return errors


def _validate_foundation_dimension(prefix: str, group: dict) -> list[str]:
    errors: list[str] = []
    for key in sorted(group):
        errors.extend(_numeric_errors(f"{prefix}.{key}", group[key], minimum=0))
    return errors


def _validate_foundation_density(prefix: str, group: dict) -> list[str]:
    errors: list[str] = []
    if "multiplier" not in group:
        return [f"{prefix}.multiplier: missing required density multiplier mapping"]
    multipliers = group["multiplier"]
    if not isinstance(multipliers, dict):
        return [
            f"{prefix}.multiplier: expected a mapping, got {_describe(multipliers)}"
        ]
    for key in sorted(multipliers):
        if key not in CANONICAL_DENSITIES:
            errors.append(
                f"{prefix}.multiplier.{key}: density key must be one of "
                f"compact, normal, spacious"
            )
            continue
        errors.extend(
            _numeric_errors(
                f"{prefix}.multiplier.{key}", multipliers[key], minimum=0, exclusive=True
            )
        )
    for key in CANONICAL_DENSITIES:
        if key not in multipliers:
            errors.append(f"{prefix}.multiplier.{key}: missing required density multiplier")
    return errors


def _validate_foundation_motion(prefix: str, group: dict) -> list[str]:
    errors: list[str] = []
    for key in _MOTION_DURATIONS:
        if key not in group:
            errors.append(f"{prefix}.{key}: missing required motion token")
            continue
        errors.extend(_numeric_errors(f"{prefix}.{key}", group[key], minimum=0))
    if "easing" not in group:
        errors.append(f"{prefix}.easing: missing required motion token")
    elif not isinstance(group["easing"], str) or not group["easing"]:
        errors.append(f"{prefix}.easing: expected a non-empty string")
    for key in sorted(set(group) - set(_MOTION_DURATIONS) - {"easing"}):
        errors.append(f"{prefix}.{key}: unknown motion token")
    return errors


_FOUNDATION_VALIDATORS = {
    "color": _validate_foundation_color,
    "typography": _validate_foundation_typography,
    "spacing": _validate_foundation_dimension,
    "radius": _validate_foundation_dimension,
    "elevation": _validate_foundation_dimension,
    "size": _validate_foundation_dimension,
    "density": _validate_foundation_density,
    "motion": _validate_foundation_motion,
    "breakpoints": _validate_foundation_dimension,
}


def _version_errors(label: str, version) -> list[str]:
    if isinstance(version, bool) or version != 1:
        return [f"{label}.version: must equal 1"]
    return []


def _validate_foundation(catalog: dict) -> list[str]:
    errors: list[str] = []
    errors.extend(_version_errors("foundation", catalog.get("version")))
    declared = set(catalog) - {"version"}
    for group in CANONICAL_GROUPS:
        if group not in catalog:
            errors.append(f"foundation: missing required top-level group '{group}'")
    for group in sorted(declared - set(CANONICAL_GROUPS)):
        errors.append(f"foundation: unknown top-level group '{group}'")
    for group in CANONICAL_GROUPS:
        if group not in catalog:
            continue
        value = catalog[group]
        if not isinstance(value, dict):
            errors.append(
                f"foundation.{group}: expected a mapping, got {_describe(value)}"
            )
            continue
        if not value:
            errors.append(f"foundation.{group}: must not be empty")
            continue
        errors.extend(_FOUNDATION_VALIDATORS[group](f"foundation.{group}", value))
    return errors


def _validate_semantic_value(group: str, key: str, value) -> list[str]:
    path = f"semantic.{group}.{key}"
    if isinstance(value, str) and ("{" in value or "}" in value):
        if not _REFERENCE_PATTERN.match(value):
            return [
                f"{path}: malformed token reference {value!r}; "
                f"expected a complete {{foundation.<path>}} reference"
            ]
        return []
    if group == "color":
        if not isinstance(value, str) or not _COLOR_PATTERN.match(value):
            return [
                f"{path}: invalid color {value!r}; expected #RRGGBB, #AARRGGBB, "
                f"or a foundation reference"
            ]
        return []
    if group == "density" and key == "default":
        if value not in CANONICAL_DENSITIES:
            return [f"{path}: density must be one of compact, normal, spacious"]
        return []

    numeric_leaves = _NUMERIC_LEAVES.get(group, ())
    if numeric_leaves is None or key in numeric_leaves:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return [
                f"{path}: expected a number or foundation reference, "
                f"got {_describe(value)}"
            ]
        return _numeric_errors(path, value, minimum=0)

    if key in _STRING_LEAVES.get(group, ()):
        if not isinstance(value, str) or not value:
            return [f"{path}: expected a non-empty string, got {_describe(value)}"]
        return []

    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return [
            f"{path}: expected a token reference or literal value, got {_describe(value)}"
        ]
    return []


def _validate_semantic(catalog: dict) -> list[str]:
    errors: list[str] = []
    errors.extend(_version_errors("semantic", catalog.get("version")))
    declared = set(catalog) - {"version"}
    for group in CANONICAL_GROUPS:
        if group not in catalog:
            errors.append(f"semantic: missing required top-level group '{group}'")
    for group in sorted(declared - set(CANONICAL_GROUPS)):
        errors.append(f"semantic: unknown top-level group '{group}'")
    for group in CANONICAL_GROUPS:
        if group not in catalog:
            continue
        value = catalog[group]
        if not isinstance(value, dict):
            errors.append(f"semantic.{group}: expected a mapping, got {_describe(value)}")
            continue
        if not value:
            errors.append(f"semantic.{group}: must not be empty")
            continue
        required = SEMANTIC_KEYS[group]
        for key in sorted(set(required) - set(value)):
            errors.append(f"semantic.{group}: missing required key '{key}'")
        for key in sorted(set(value) - set(required)):
            errors.append(f"semantic.{group}: unknown key '{key}'")
        for key in sorted(set(value) & set(required)):
            errors.extend(_validate_semantic_value(group, key, value[key]))
    return errors


def validate_token_catalogs(root: Path) -> list[str]:
    """Validate both token catalogs under *root*; never raises, returns sorted errors."""
    errors: list[str] = []
    try:
        foundation = load_foundation_tokens(root)
    except ValueError as exc:
        errors.append(str(exc))
        foundation = None
    except Exception as exc:  # pragma: no cover - defensive, never raise
        errors.append(f"foundation: unexpected validation failure: {exc}")
        foundation = None

    try:
        semantic = load_semantic_tokens(root)
    except ValueError as exc:
        errors.append(str(exc))
        semantic = None
    except Exception as exc:  # pragma: no cover - defensive, never raise
        errors.append(f"semantic: unexpected validation failure: {exc}")
        semantic = None

    if foundation is not None:
        try:
            errors.extend(_validate_foundation(foundation))
        except Exception as exc:  # pragma: no cover - defensive, never raise
            errors.append(f"foundation: unexpected validation failure: {exc}")
    if semantic is not None:
        try:
            errors.extend(_validate_semantic(semantic))
        except Exception as exc:  # pragma: no cover - defensive, never raise
            errors.append(f"semantic: unexpected validation failure: {exc}")

    return sorted(set(errors))


def _iter_preset_files(root: Path) -> list[Path]:
    directory = root / THEMES_RELATIVE
    if not directory.is_dir():
        return []
    return sorted(directory.glob("*.yaml"), key=lambda path: path.name)


def _read_preset_yaml(path: Path, label: str):
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ValueError(f"{label}: cannot read {path}: {exc}") from exc
    try:
        return _stringify_keys(yaml.safe_load(text))
    except yaml.YAMLError as exc:
        raise ValueError(f"{label}: invalid YAML in {path}: {exc}") from exc


def load_theme_presets(root: Path) -> dict[str, dict]:
    """Load theme presets under *root*, keyed by ``id``, in filename-sorted order."""
    presets: dict[str, dict] = {}
    for path in _iter_preset_files(root):
        label = f"theme preset {path.name}"
        document = _read_preset_yaml(path, label)
        if not isinstance(document, dict):
            raise ValueError(f"{label}: expected a mapping at {path}")
        preset_id = document.get("id")
        if not isinstance(preset_id, str) or not preset_id:
            raise ValueError(f"{label}: missing or empty id")
        if preset_id in presets:
            raise ValueError(f"{label}: duplicate preset id {preset_id!r}")
        presets[preset_id] = document
    return presets


def _override_path_errors(label: str, overrides) -> list[str]:
    """Validate an override layer against :data:`SEMANTIC_KEYS`; returns errors."""
    if not isinstance(overrides, dict):
        return [
            f"{label}: semantic overrides must be a mapping, got {_describe(overrides)}"
        ]
    errors: list[str] = []
    for group in sorted(overrides):
        value = overrides[group]
        if group not in SEMANTIC_KEYS:
            errors.append(f"{label}: unknown override group '{group}'")
            continue
        if not isinstance(value, dict):
            errors.append(
                f"{label}: override group '{group}' must be a mapping, "
                f"got {_describe(value)}"
            )
            continue
        for key in sorted(value):
            if key not in SEMANTIC_KEYS[group]:
                errors.append(f"{label}: unknown override key '{group}.{key}'")
    return errors


def validate_theme_presets(root: Path) -> list[str]:
    """Validate every theme preset under *root*; never raises, returns sorted errors."""
    errors: list[str] = []
    seen: dict[str, str] = {}
    try:
        paths = _iter_preset_files(root)
    except Exception as exc:  # pragma: no cover - defensive, never raise
        return [f"theme presets: unexpected validation failure: {exc}"]
    for path in paths:
        name = path.name
        label = f"theme preset {name}"
        try:
            document = _read_preset_yaml(path, label)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        except Exception as exc:  # pragma: no cover - defensive, never raise
            errors.append(f"{label}: unexpected validation failure: {exc}")
            continue
        if not isinstance(document, dict):
            errors.append(f"{label}: expected a mapping at {path}")
            continue
        preset_id = document.get("id")
        if not isinstance(preset_id, str) or not preset_id:
            errors.append(f"{label}: missing or empty id")
            continue
        if preset_id in seen:
            errors.append(f"{label}: duplicate id '{preset_id}'")
        else:
            seen[preset_id] = name
        status = document.get("status")
        if status not in PRESET_STATUSES:
            errors.append(
                f"theme preset {preset_id}: invalid status {status!r}; "
                f"expected one of {', '.join(PRESET_STATUSES)}"
            )
        for extra in sorted(set(document) - {"id", "status", "semantic_overrides"}):
            errors.append(f"theme preset {preset_id}: unknown key '{extra}'")
        if "semantic_overrides" not in document:
            errors.append(f"theme preset {preset_id}: missing semantic_overrides")
        else:
            errors.extend(
                _override_path_errors(
                    f"theme preset {preset_id}", document["semantic_overrides"]
                )
            )
    return sorted(set(errors))


def brand_to_semantic_overrides(brand: dict) -> dict:
    """Map approved raw client brand keys onto nested semantic override paths."""
    overrides: dict[str, dict] = {}
    if not isinstance(brand, dict):
        return overrides
    for raw_key, (group, key) in BRAND_OVERRIDE_MAP.items():
        if raw_key in brand:
            overrides.setdefault(group, {})[key] = brand[raw_key]
    return overrides


def _deep_merge(base: dict, overlay: dict) -> None:
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _deep_merge(base[key], value)
        else:
            base[key] = copy.deepcopy(value)


def _resolve_foundation_path(
    path: str, foundation: dict, context: str, visiting: list[str], errors: list[str]
):
    label = f"foundation.{path}"
    if label in visiting:
        errors.append(
            f"{context}: cyclic token reference: " + " -> ".join(visiting + [label])
        )
        return None
    current = foundation
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            errors.append(
                f"{context}: unknown token reference: {{foundation.{path}}}"
            )
            return None
        current = current[part]
    if isinstance(current, str):
        match = _RESOLUTION_REFERENCE_PATTERN.match(current)
        if match:
            visiting.append(label)
            resolved = _resolve_foundation_path(
                match.group(1), foundation, context, visiting, errors
            )
            visiting.pop()
            return resolved
    return current


def _resolve_theme_values(theme: dict, foundation: dict) -> tuple[dict, list[str]]:
    errors: list[str] = []
    resolved: dict = {}
    for group in sorted(theme):
        group_value = theme[group]
        if not isinstance(group_value, dict):
            resolved[group] = copy.deepcopy(group_value)
            continue
        resolved_group: dict = {}
        for key in sorted(group_value):
            value = group_value[key]
            if isinstance(value, str):
                match = _RESOLUTION_REFERENCE_PATTERN.match(value)
                if match:
                    value = _resolve_foundation_path(
                        match.group(1),
                        foundation,
                        f"semantic.{group}.{key}",
                        [],
                        errors,
                    )
            resolved_group[key] = copy.deepcopy(value)
        resolved[group] = resolved_group
    return resolved, errors


def _sorted_deep_copy(value):
    if isinstance(value, dict):
        return {key: _sorted_deep_copy(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [_sorted_deep_copy(item) for item in value]
    return copy.deepcopy(value)


def resolve_theme(
    root: Path,
    preset_id: str,
    client_brand: dict | None = None,
    direction_overrides: dict | None = None,
) -> dict:
    """Compile foundation + semantic defaults + preset + brand + direction to a theme."""
    catalog_errors = validate_token_catalogs(root)
    if catalog_errors:
        raise ValueError(
            "invalid token catalogs: " + "; ".join(sorted(catalog_errors))
        )

    foundation = load_foundation_tokens(root)
    semantic = load_semantic_tokens(root)
    presets = load_theme_presets(root)

    if preset_id not in presets:
        raise ValueError(f"unknown theme preset: {preset_id}")
    preset = presets[preset_id]
    if preset.get("status") != "approved":
        raise ValueError(f"theme preset '{preset_id}' is not approved")

    layers = (
        ("preset override", preset.get("semantic_overrides")),
        ("brand override", brand_to_semantic_overrides(client_brand or {})),
        ("direction override", direction_overrides or {}),
    )
    override_errors: list[str] = []
    for label, overrides in layers:
        override_errors.extend(_override_path_errors(label, overrides))
    if override_errors:
        raise ValueError("; ".join(sorted(override_errors)))

    theme = copy.deepcopy(semantic)
    theme.pop("version", None)
    for _label, overrides in layers:
        _deep_merge(theme, overrides)

    resolved, reference_errors = _resolve_theme_values(theme, foundation)
    if reference_errors:
        raise ValueError("; ".join(sorted(set(reference_errors))))

    resolved["version"] = 1
    semantic_errors = _validate_semantic(resolved)
    if semantic_errors:
        raise ValueError("; ".join(sorted(semantic_errors)))

    return _sorted_deep_copy(resolved)
