from __future__ import annotations

import json
import re
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

from tooling.knowledge.index_design_contract import build_indexes


_SCHEMA_RELATIVE = Path("client-projects") / "schema" / "refinement-notes.schema.json"
_TOOLING_SCHEMA_PATH = Path(__file__).resolve().parents[2] / _SCHEMA_RELATIVE
_CATALOG_FIELDS = (
    ("component", "components", "component"),
    ("pattern", "patterns", "pattern"),
)
_ADDITIONAL_PROPERTIES_RE = re.compile(
    r"^Additional properties are not allowed \((?P<names>.*) "
    r"(?P<verb>was|were) unexpected\)$"
)


def _load_schema(root: Path) -> dict:
    """Load the refinement-note schema from *root*, falling back to tooling.

    The repository root is authoritative when it carries the schema; the tooling
    checkout copy keeps the validator usable against minimal temporary roots.
    """
    candidate = root / _SCHEMA_RELATIVE
    path = candidate if candidate.exists() else _TOOLING_SCHEMA_PATH
    return json.loads(path.read_text(encoding="utf-8"))


def load_refinement_notes(path: Path) -> dict:
    """Load refinement notes as a mapping.

    Raises ``ValueError`` (message prefixed ``invalid refinement notes:``) for
    unreadable files, malformed YAML, or a non-mapping top level.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ValueError(f"invalid refinement notes: {path}: cannot read: {exc}") from exc
    try:
        document = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ValueError(f"invalid refinement notes: {path}: cannot parse YAML: {exc}") from exc
    if not isinstance(document, dict):
        raise ValueError(
            f"invalid refinement notes: {path}: top level must be a mapping"
        )
    return document


def _change_label(document: object, index: int) -> str:
    changes = document.get("changes") if isinstance(document, dict) else None
    if isinstance(changes, list) and 0 <= index < len(changes):
        item = changes[index]
        if isinstance(item, dict):
            item_id = item.get("id")
            if isinstance(item_id, str) and item_id:
                return f"change {item_id!r}"
    return "change <unknown>"


def _canonical_message(message: str) -> str:
    """Sort quoted property names so messages do not depend on key insertion order."""
    match = _ADDITIONAL_PROPERTIES_RE.match(message)
    if match is None:
        return message
    names = re.findall(r"'([^']*)'", match.group("names"))
    if not names:
        return message
    quoted = ", ".join(f"'{name}'" for name in sorted(names))
    verb = "was" if len(names) == 1 else "were"
    return f"Additional properties are not allowed ({quoted} {verb} unexpected)"


def _schema_errors(document: object, schema: dict) -> list[str]:
    validator = Draft202012Validator(schema)
    errors: list[str] = []
    for error in validator.iter_errors(document):
        parts = list(error.path)
        if len(parts) >= 2 and parts[0] == "changes" and isinstance(parts[1], int):
            label = _change_label(document, parts[1])
            subpath = ".".join(str(part) for part in parts[2:])
        else:
            label = "refinement notes"
            subpath = ".".join(str(part) for part in parts)
        prefix = f"{subpath}: " if subpath else ""
        errors.append(f"{label}: {prefix}{_canonical_message(error.message)}")
    return errors


def _duplicate_id_errors(document: object) -> list[str]:
    changes = document.get("changes") if isinstance(document, dict) else None
    if not isinstance(changes, list):
        return []
    seen: set[str] = set()
    duplicated: set[str] = set()
    for item in changes:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if not isinstance(item_id, str) or not item_id:
            continue
        if item_id in seen:
            duplicated.add(item_id)
        else:
            seen.add(item_id)
    return [f"change {item_id!r}: duplicate change id" for item_id in sorted(duplicated)]


def _catalog_errors(root: Path, document: object) -> list[str]:
    changes = document.get("changes") if isinstance(document, dict) else None
    if not isinstance(changes, list):
        return []
    try:
        indexes = build_indexes(root)
    except (OSError, UnicodeError, yaml.YAMLError) as exc:
        return [f"cannot load design contract under {root}: {exc}"]
    errors: list[str] = []
    for index, item in enumerate(changes):
        if not isinstance(item, dict):
            continue
        label = _change_label(document, index)
        for field, catalog_key, noun in _CATALOG_FIELDS:
            value = item.get(field)
            if isinstance(value, str) and value and value not in indexes[catalog_key]:
                errors.append(f"{label}: {field}: unknown canonical {noun} id {value!r}")
    return errors


def validate_refinement_notes(root: Path, path: Path) -> list[str]:
    """Return deterministic, stable-sorted refinement-note errors under *root*.

    Never raises for ordinary validation failures (unreadable, malformed, or
    invalid notes): those are reported as error strings instead.
    """
    try:
        document = load_refinement_notes(path)
    except ValueError as exc:
        return [str(exc)]
    try:
        schema = _load_schema(root)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"cannot load refinement notes schema: {exc}"]

    errors: list[str] = []
    errors.extend(_schema_errors(document, schema))
    errors.extend(_duplicate_id_errors(document))
    errors.extend(_catalog_errors(root, document))
    return sorted(set(errors))
