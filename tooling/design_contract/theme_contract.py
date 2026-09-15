from __future__ import annotations

import math
import re
from pathlib import Path

import yaml


FOUNDATION_TOKENS_RELATIVE = Path("design-contract") / "tokens" / "foundation.yaml"
SEMANTIC_TOKENS_RELATIVE = Path("design-contract") / "tokens" / "semantic.yaml"

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

_NON_NEGATIVE_GROUPS = ("spacing", "radius", "elevation", "size", "breakpoints")

_COLOR_PATTERN = re.compile(r"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
_REFERENCE_PATTERN = re.compile(
    r"^\{foundation\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*\}$"
)

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


def _validate_foundation(catalog: dict) -> list[str]:
    errors: list[str] = []
    if catalog.get("version") != 1:
        errors.append("foundation.version: must equal 1")
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
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return [
            f"{path}: expected a token reference or literal string, got {_describe(value)}"
        ]
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return _numeric_errors(path, value, minimum=0)
    return []


def _validate_semantic(catalog: dict) -> list[str]:
    errors: list[str] = []
    if catalog.get("version") != 1:
        errors.append("semantic.version: must equal 1")
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
