from __future__ import annotations

import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

from .normalizer import canonical_id


_SCHEMA_NAMES = {
    "requirements": "resource-requirements.schema.json",
    "candidates": "resource-candidates.schema.json",
    "selection": "resource-selection.schema.json",
    "provenance": "resource-provenance.schema.json",
}

_INTERNAL_SOURCES = {"client", "agency", "official"}
_ALLOWED_PROVIDER_STATUSES = {"approved", "approved_with_rules"}


def _load_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _provider_status(root: Path, source: str) -> str | None:
    path = root / "resources" / "registry" / "providers" / f"{source}.yaml"
    if not path.exists():
        return None
    data = _load_yaml(path)
    status = data.get("status")
    return str(status) if status is not None else None


def _validate_candidate(
    *,
    root: Path,
    requirement_id: str,
    requirement: dict,
    candidate: dict,
    provenance: dict,
    errors: list[str],
) -> None:
    source = str(candidate.get("source") or "")
    mode = (requirement.get("sourcing") or {}).get("mode")
    if mode == "authoritative" and source not in _INTERNAL_SOURCES:
        errors.append(f"authoritative resource {requirement_id!r} uses unauthorized source {source!r}")

    if source not in _INTERNAL_SOURCES:
        provider_status = _provider_status(root, source)
        if provider_status == "blocked":
            errors.append(f"external resource {candidate.get('id')!r} uses blocked provider {source!r}")
        elif provider_status not in _ALLOWED_PROVIDER_STATUSES:
            errors.append(
                f"external resource {candidate.get('id')!r} uses unapproved or unknown provider {source!r}"
            )
        if candidate.get("id") not in provenance:
            errors.append(f"external resource {candidate.get('id')!r} missing provenance")


def _validate_selection_group(
    *,
    root: Path,
    label: str,
    group: dict,
    requirements: dict,
    candidate_ids: dict,
    provenance: dict,
    errors: list[str],
    require_critical: bool,
) -> None:
    canonical_owners: dict[str, str] = {}

    for unknown_requirement_id in set(group) - set(requirements):
        errors.append(f"{label} references unknown resource requirement {unknown_requirement_id!r}")

    for requirement_id, requirement in requirements.items():
        selection = group.get(requirement_id)
        if require_critical and requirement.get("impact") == "critical" and not selection:
            errors.append(f"critical resource {requirement_id!r} has no selection")
            continue
        if not selection:
            continue

        primary_id = selection.get("primary")
        candidate = candidate_ids.get(primary_id)
        if candidate is None:
            errors.append(f"{label} {requirement_id!r} references unknown candidate {primary_id!r}")
            continue

        canonical = canonical_id(candidate)
        existing_owner = canonical_owners.get(canonical)
        if existing_owner is not None and existing_owner != requirement_id:
            errors.append(
                f"canonical resource id collision {canonical!r} between {existing_owner!r} and {requirement_id!r} in {label}"
            )
        else:
            canonical_owners[canonical] = requirement_id

        _validate_candidate(
            root=root,
            requirement_id=requirement_id,
            requirement=requirement,
            candidate=candidate,
            provenance=provenance,
            errors=errors,
        )

        fallback_id = selection.get("fallback")
        if fallback_id:
            fallback = candidate_ids.get(fallback_id)
            if fallback is None:
                errors.append(f"{label} {requirement_id!r} references unknown fallback candidate {fallback_id!r}")
            else:
                _validate_candidate(
                    root=root,
                    requirement_id=requirement_id,
                    requirement=requirement,
                    candidate=fallback,
                    provenance=provenance,
                    errors=errors,
                )


def validate_resource_artifacts(root: Path, client_dir: Path) -> list[str]:
    errors: list[str] = []
    paths = {
        "requirements": client_dir / "derived" / "resource-requirements.yaml",
        "candidates": client_dir / "resources" / "candidates.yaml",
        "selection": client_dir / "resources" / "selection.yaml",
        "provenance": client_dir / "resources" / "provenance.yaml",
    }
    data: dict[str, dict] = {}
    for key, path in paths.items():
        if not path.exists():
            return [f"{path}: missing"]
        loaded = _load_yaml(path)
        data[key] = loaded
        schema_path = root / "resources" / "registry" / "schema" / _SCHEMA_NAMES[key]
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        for error in Draft202012Validator(schema).iter_errors(loaded):
            errors.append(f"{path}: {error.message}")

    requirements = {
        str(item.get("id")): item
        for item in data["requirements"].get("resources") or []
        if isinstance(item, dict) and item.get("id")
    }
    candidate_ids = {
        str(candidate.get("id")): candidate
        for group in (data["candidates"].get("candidates") or {}).values()
        for candidate in group or []
        if isinstance(candidate, dict) and candidate.get("id")
    }
    provenance = data["provenance"].get("resources") or {}
    selection_data = data["selection"]

    _validate_selection_group(
        root=root,
        label="selection",
        group=selection_data.get("selections") or {},
        requirements=requirements,
        candidate_ids=candidate_ids,
        provenance=provenance,
        errors=errors,
        require_critical=True,
    )

    for direction_id, group in (selection_data.get("direction_overrides") or {}).items():
        _validate_selection_group(
            root=root,
            label=f"direction override {direction_id!r}",
            group=group or {},
            requirements=requirements,
            candidate_ids=candidate_ids,
            provenance=provenance,
            errors=errors,
            require_critical=False,
        )

    return errors
