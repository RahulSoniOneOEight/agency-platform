from __future__ import annotations


def _canonical_id(candidate: dict) -> str:
    role = str(candidate.get("role") or "resource")
    resource_type = candidate.get("type")
    if resource_type == "image":
        return f"asset.{role}"
    if resource_type == "icon":
        return role if role.startswith("icon.") else f"icon.{role}"
    if resource_type == "motion":
        return role if role.startswith("motion.") else f"motion.{role}"
    return f"resource.{role}"


def normalize_bindings(selection: dict, candidates: dict) -> dict:
    by_id = {}
    for group in (candidates.get("candidates") or {}).values():
        for candidate in group or []:
            by_id[candidate.get("id")] = candidate

    bindings = {}
    for item in (selection.get("selections") or {}).values():
        candidate = by_id.get(item.get("primary"))
        if not candidate:
            continue
        canonical = _canonical_id(candidate)
        bindings[canonical] = {
            "candidate_id": candidate.get("id"),
            "type": candidate.get("type"),
            "source": candidate.get("source"),
            "asset": candidate.get("asset", {}),
        }
    return bindings
