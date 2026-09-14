from __future__ import annotations

import json
import os
from typing import Callable
from urllib.parse import urlencode
from urllib.request import Request, urlopen


Transport = Callable[[str, dict[str, str]], dict]


def _default_transport(url: str, headers: dict[str, str]) -> dict:
    request = Request(url, headers=headers)
    with urlopen(request, timeout=20) as response:  # noqa: S310 - governed HTTPS provider
        return json.loads(response.read().decode("utf-8"))


def search_pexels(
    requirement: dict,
    api_key: str | None = None,
    transport: Transport | None = None,
) -> list[dict]:
    key = api_key or os.getenv("PEXELS_API_KEY")
    if not key:
        return []

    details = requirement.get("requirements") or {}
    query = details.get("subject") or requirement.get("role") or requirement.get("id") or ""
    params = {"query": str(query), "per_page": 10}
    orientation = details.get("orientation")
    if orientation in {"landscape", "portrait", "square"}:
        params["orientation"] = orientation
    url = "https://api.pexels.com/v1/search?" + urlencode(params)
    payload = (transport or _default_transport)(url, {"Authorization": key})

    results: list[dict] = []
    for photo in payload.get("photos") or []:
        if not isinstance(photo, dict) or photo.get("id") is None:
            continue
        src = photo.get("src") if isinstance(photo.get("src"), dict) else {}
        image_url = src.get("large2x") or src.get("large") or src.get("original")
        provider_id = str(photo["id"])
        results.append(
            {
                "id": f"pexels-{provider_id}",
                "source": "pexels",
                "type": requirement.get("type", "image"),
                "role": requirement.get("role"),
                "asset": {
                    "url": image_url,
                    "width": photo.get("width"),
                    "height": photo.get("height"),
                    "photographer": photo.get("photographer"),
                },
                "provenance": {
                    "source": "pexels",
                    "provider_id": provider_id,
                    "source_url": photo.get("url"),
                    "usage_status": "prototype-approved",
                },
                "scores": {},
            }
        )
    return results
