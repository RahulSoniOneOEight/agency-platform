from __future__ import annotations

STANDARD_VIEWPORTS = [
    {"name": "mobile-small", "width": 360, "height": 800},
    {"name": "mobile-medium", "width": 390, "height": 844},
    {"name": "mobile-large", "width": 430, "height": 932},
    {"name": "tablet", "width": 768, "height": 1024},
    {"name": "desktop", "width": 1440, "height": 900},
]


def build_screenshot_manifest(client_id: str, directions: list[str]) -> dict:
    clean = [d.lower() for d in directions]
    return {
        "version": 1,
        "client_id": client_id,
        "directions": clean,
        "viewports": [dict(v) for v in STANDARD_VIEWPORTS],
        "routes": [
            {"direction": d, "path": f"/?client={client_id}&direction={d}"}
            for d in clean
        ],
    }
