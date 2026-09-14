from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Any

from tooling.knowledge.io import load_yaml, yaml_files
from tooling.knowledge.preset_resolver import resolve_presets


def _patterns(root: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for path in yaml_files(root / "experience-patterns"):
        item = load_yaml(path)
        if isinstance(item, dict) and "id" in item:
            result[item["id"]] = item
    return result


def _context_terms(client: dict[str, Any]) -> set[str]:
    terms: set[str] = set()
    for key in ("objectives", "personas", "jobs", "use_cases"):
        value = client.get(key, [])
        if isinstance(value, list):
            terms.update(str(item) for item in value)
    terms.add(str(client.get("business_model", "")))
    terms.add(str(client.get("industry", "")))
    return {term for term in terms if term}


def generate_directions(root: Path, client: dict[str, Any], *, limit: int = 3) -> dict[str, Any]:
    resolved = resolve_presets(
        root,
        business_model=client["business_model"],
        industry=client["industry"],
        use_cases=list(client.get("use_cases", [])),
    )
    catalog = _patterns(root)
    frequency = Counter(resolved["candidate_archetypes"])
    context = _context_terms(client)

    scored: list[dict[str, Any]] = []
    for archetype, pattern in catalog.items():
        score = frequency[archetype] * 5
        matches = sorted(context.intersection(set(pattern.get("best_when", []))))
        score += len(matches) * 2
        if client.get("business_model") in pattern.get("business_models", []):
            score += 2
        score += len(set(client.get("personas", [])).intersection(pattern.get("personas", [])))
        score += len(set(client.get("jobs", [])).intersection(pattern.get("jobs", [])))
        if score <= 0:
            continue
        scored.append(
            {
                "archetype": archetype,
                "name": pattern["name"],
                "strategy_family": pattern["strategy_family"],
                "score": score,
                "rationale": f"{pattern['strategic_goal']} Matched context: {', '.join(matches) if matches else 'preset fit'}.",
                "primary_journey": list(pattern["primary_journey"]),
                "tradeoffs": pattern.get("tradeoffs", {}),
            }
        )

    scored.sort(key=lambda item: (-item["score"], item["archetype"]))
    selected: list[dict[str, Any]] = []
    used_families: set[str] = set()
    for item in scored:
        if item["strategy_family"] in used_families:
            continue
        selected.append(item)
        used_families.add(item["strategy_family"])
        if len(selected) == limit:
            break

    if len(selected) < limit:
        raise ValueError(f"Could only produce {len(selected)} strategically distinct directions; need {limit}")

    return {
        "client_id": client.get("id", "unknown-client"),
        "resolved_presets": resolved,
        "directions": selected,
    }
