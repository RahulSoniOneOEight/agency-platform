from __future__ import annotations


def canonical_id(candidate: dict) -> str:
    role = str(candidate.get("role") or "resource")
    resource_type = candidate.get("type")
    if resource_type == "image":
        return f"asset.{role}"
    if resource_type == "icon":
        return role if role.startswith("icon.") else f"icon.{role}"
    if resource_type == "motion":
        return role if role.startswith("motion.") else f"motion.{role}"
    return f"resource.{role}"


def _candidate_index(candidates: dict) -> dict[str, dict]:
    by_id: dict[str, dict] = {}
    for group in (candidates.get("candidates") or {}).values():
        for candidate in group or []:
            if isinstance(candidate, dict) and candidate.get("id"):
                by_id[str(candidate["id"])] = candidate
    return by_id


def _normalize_selection_group(group: dict, by_id: dict[str, dict]) -> dict:
    bindings: dict = {}
    for item in (group or {}).values():
        candidate = by_id.get(item.get("primary")) if isinstance(item, dict) else None
        if not candidate:
            continue
        canonical = canonical_id(candidate)
        bindings[canonical] = {
            "candidate_id": candidate.get("id"),
            "type": candidate.get("type"),
            "source": candidate.get("source"),
            "asset": candidate.get("asset", {}),
        }
    return bindings


def normalize_bindings(selection: dict, candidates: dict) -> dict:
    by_id = _candidate_index(candidates)
    bindings = _normalize_selection_group(selection.get("selections") or {}, by_id)

    overrides: dict[str, dict] = {}
    for direction_id, group in (selection.get("direction_overrides") or {}).items():
        normalized = _normalize_selection_group(group or {}, by_id)
        if normalized:
            overrides[str(direction_id)] = normalized
    if overrides:
        bindings["direction_overrides"] = overrides

    return bindings
