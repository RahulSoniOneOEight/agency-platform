from __future__ import annotations


_STOCK_SOURCES = {"pexels", "unsplash", "stock"}


def route_sources(
    requirement: dict,
    client_candidates_exist: bool,
    client_candidate_suitable: bool = True,
) -> list[str]:
    sourcing = requirement.get("sourcing") or {}
    mode = sourcing.get("mode")
    allowed = list(sourcing.get("allowed_sources") or [])

    if mode == "authoritative":
        return [source for source in allowed if source not in _STOCK_SOURCES and source in {"client", "official", "agency"}]

    if mode == "prefer_client" and client_candidates_exist and client_candidate_suitable:
        return [source for source in allowed if source == "client"] or ["client"]

    if mode in {"prefer_client", "comparative", "discovery"}:
        return allowed

    return allowed
