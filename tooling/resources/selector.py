from __future__ import annotations

from .scorer import score_candidate


def select_candidates(requirements: dict, candidates: dict) -> dict:
    output = {"version": 1, "selections": {}}
    grouped = candidates.get("candidates") or {}
    for requirement in requirements.get("resources") or []:
        requirement_id = requirement.get("id")
        allowed = set((requirement.get("sourcing") or {}).get("allowed_sources") or [])
        mode = (requirement.get("sourcing") or {}).get("mode")
        pool = []
        for candidate in grouped.get(requirement_id, []) or []:
            source = candidate.get("source")
            if allowed and source not in allowed:
                continue
            if mode == "authoritative" and source not in {"client", "official", "agency"}:
                continue
            pool.append(candidate)
        if not pool:
            continue
        ranked = sorted(pool, key=lambda candidate: score_candidate(requirement, candidate), reverse=True)
        chosen = {
            "primary": ranked[0]["id"],
            "rationale": [f"highest deterministic fit score: {score_candidate(requirement, ranked[0]):.3f}"],
        }
        if len(ranked) > 1:
            chosen["fallback"] = ranked[1]["id"]
        output["selections"][requirement_id] = chosen
    return output
