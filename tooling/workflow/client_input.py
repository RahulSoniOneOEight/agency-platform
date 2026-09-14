from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

_MODULE_SCHEMAS = {
    "business_rules": "business-rules.schema.json",
    "user_groups": "user-groups.schema.json",
    "journey_priorities": "journey-priorities.schema.json",
    "feature_requirements": "feature-requirements.schema.json",
    "platform_requirements": "platform-requirements.schema.json",
    "integration_requirements": "integration-requirements.schema.json",
    "content_requirements": "content-requirements.schema.json",
    "data_context": "data-context.schema.json",
    "constraints": "constraints.schema.json",
    "open_questions": "open-questions.schema.json",
}

_COLLECTION_SCHEMAS = {
    "brand": "brand-input.schema.json",
    "references": "references.schema.json",
    "assets": "asset-manifest.schema.json",
    "source_documents": "source-documents.schema.json",
}

_ID_ARRAY_FIELDS = {
    "references": "references",
    "assets": "assets",
    "source_documents": "documents",
    "open_questions": "questions",
}

_SCHEMA_DIR_PARTS = ("client-projects", "schema", "input")


def _schema_for(kind: str, key: str) -> str | None:
    mapping = _MODULE_SCHEMAS if kind == "modules" else _COLLECTION_SCHEMAS
    return mapping.get(key)


def _schema_dir(root: Path) -> Path:
    return root.joinpath(*_SCHEMA_DIR_PARTS)


def _validate_schema(root: Path, schema_name: str, data: Any, label: str) -> list[str]:
    schema_path = _schema_dir(root) / schema_name
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return [f"{label}: cannot load schema {schema_name}: {exc}"]
    validator = Draft202012Validator(schema)
    if not isinstance(data, dict):
        return [f"{label}: expected a mapping"]
    errors = sorted(validator.iter_errors(data), key=lambda error: list(error.path))
    return [f"{label}: {'.'.join(map(str, error.path)) or '<root>'}: {error.message}" for error in errors]


def _duplicate_id_errors(items: Any, label: str, field: str) -> list[str]:
    if not isinstance(items, list):
        return []
    seen: dict[str, bool] = {}
    errors: list[str] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if item_id is None:
            continue
        if item_id in seen:
            errors.append(f"{label}: duplicate {field} id {item_id!r}")
        seen[item_id] = True
    return errors


def _validate_reference(root: Path, input_dir: Path, kind: str, key: str, rel_path: Any) -> list[str]:
    label = f"{input_dir}/<{kind}.{key}>"
    schema_name = _schema_for(kind, key)
    if schema_name is None:
        singular = "module" if kind == "modules" else "collection"
        return [f"{label}: unknown {singular} key {key!r}"]
    if not isinstance(rel_path, str) or not rel_path:
        return [f"{label}: reference path must be a non-empty string"]
    if Path(rel_path).is_absolute():
        return [f"{label}: reference path must be relative: {rel_path}"]
    resolved = (input_dir / rel_path).resolve()
    if not resolved.is_relative_to(input_dir.resolve()):
        return [f"{label}: reference path escapes input directory: {rel_path}"]
    if not resolved.exists():
        return [f"{label}: missing referenced file: {rel_path}"]
    try:
        data = yaml.safe_load(resolved.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        return [f"{resolved}: invalid yaml: {exc}"]
    if not isinstance(data, dict):
        return [f"{resolved}: must be a mapping"]

    errors = _validate_schema(root, schema_name, data, str(resolved))
    array_field = _ID_ARRAY_FIELDS.get(key)
    if array_field:
        errors.extend(_duplicate_id_errors(data.get(array_field), str(resolved), array_field))
    return errors


def _validate_client_input(root: Path, client_dir: Path) -> list[str]:
    input_dir = client_dir / "input"
    index_path = input_dir / "client-input.yaml"
    label = str(index_path)
    if not index_path.exists():
        return [f"{label}: missing client-input.yaml"]
    try:
        index = yaml.safe_load(index_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        return [f"{label}: invalid yaml: {exc}"]
    if not isinstance(index, dict):
        return [f"{label}: client-input.yaml must be a mapping"]

    errors = _validate_schema(root, "client-input.schema.json", index, label)

    for kind in ("modules", "collections"):
        mapping = index.get(kind)
        if not isinstance(mapping, dict):
            continue
        for key, rel_path in mapping.items():
            errors.extend(_validate_reference(root, input_dir, kind, key, rel_path))
    return errors


def validate_client_input(root: Path, client_dir: Path) -> list[str]:
    try:
        return _validate_client_input(root, client_dir)
    except Exception as exc:  # noqa: BLE001 - validator must never raise
        return [f"{client_dir}: {exc}"]


def blocking_open_questions(client_dir: Path) -> list[dict]:
    try:
        return _blocking_open_questions(client_dir)
    except Exception:  # noqa: BLE001 - helper must never raise
        return []


def _blocking_open_questions(client_dir: Path) -> list[dict]:
    input_dir = client_dir / "input"
    index_path = input_dir / "client-input.yaml"
    try:
        index = yaml.safe_load(index_path.read_text(encoding="utf-8"))
    except (yaml.YAMLError, OSError):
        return []
    if not isinstance(index, dict):
        return []
    modules = index.get("modules")
    if not isinstance(modules, dict):
        return []
    rel_path = modules.get("open_questions")
    if not isinstance(rel_path, str) or not rel_path:
        return []
    resolved = (input_dir / rel_path).resolve()
    if not resolved.is_relative_to(input_dir.resolve()) or not resolved.exists():
        return []
    try:
        data = yaml.safe_load(resolved.read_text(encoding="utf-8"))
    except (yaml.YAMLError, OSError):
        return []
    if not isinstance(data, dict):
        return []
    questions = data.get("questions")
    if not isinstance(questions, list):
        return []
    return [
        question
        for question in questions
        if isinstance(question, dict)
        and question.get("blocking") is True
        and question.get("status") != "resolved"
    ]
