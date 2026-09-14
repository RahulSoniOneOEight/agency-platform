from __future__ import annotations


_WEIGHTS = {
    "direction_fit": 0.25,
    "relevance": 0.20,
    "composition": 0.15,
    "brand_fit": 0.10,
    "technical_quality": 0.10,
    "provenance": 0.10,
    "consistency": 0.10,
}


def score_candidate(requirement: dict, candidate: dict) -> float:
    scores = candidate.get("scores") or {}
    total = sum(float(scores.get(key, 0.0)) * weight for key, weight in _WEIGHTS.items())
    mode = (requirement.get("sourcing") or {}).get("mode")
    if mode == "prefer_client" and candidate.get("source") == "client":
        total += 0.08
    return round(min(total, 1.0), 6)
