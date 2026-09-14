from __future__ import annotations

import argparse
import re
from pathlib import Path

import yaml

from tooling.workflow.client_paths import ClientPaths
from tooling.workflow.state import initial_state, save_state


CLIENT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}$")


def _write_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def initialize_client(root: Path, client_id: str, display_name: str | None = None) -> Path:
    if not CLIENT_ID_RE.fullmatch(client_id):
        raise ValueError("client_id must use lowercase letters, numbers, and hyphens")

    client_dir = root / "client-projects" / client_id
    if client_dir.exists():
        raise FileExistsError(f"client already exists: {client_id}")

    client_dir.mkdir(parents=True)
    paths = ClientPaths.for_client(client_dir)
    name = display_name or client_id

    for folder in (
        paths.input_dir / "brand",
        paths.input_dir / "references",
        paths.input_dir / "assets",
        paths.input_dir / "source-documents",
        client_dir / "resources",
        client_dir / "directions",
    ):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / ".gitkeep").write_text("", encoding="utf-8")

    paths.brief.write_text(f"# {name}\n\nClient brief pending.\n", encoding="utf-8")

    _write_yaml(
        paths.client_input,
        {
            "version": 1,
            "client_id": client_id,
            "display_name": name,
            "business_context": {},
            "users": [],
            "goals": [],
            "brand": {},
            "references": [],
            "assets": [],
            "constraints": [],
        },
    )

    _write_yaml(
        paths.client_profile,
        {
            "id": client_id,
            "display_name": name,
            "business_model": "",
            "industry": "",
            "use_cases": [],
            "objectives": [],
            "personas": [],
            "jobs": [],
            "platforms": [],
            "capabilities": [],
            "constraints": [],
        },
    )
    _write_yaml(
        paths.resolved_presets,
        {"version": 1, "business_model": None, "industry": None, "use_cases": []},
    )
    _write_yaml(
        paths.intelligence_map,
        {
            "version": 1,
            "components": [],
            "patterns": [],
            "journeys": [],
            "variants": [],
            "themes": [],
            "experience_patterns": [],
        },
    )
    _write_yaml(paths.capability_map, {"version": 1, "capabilities": []})
    _write_yaml(paths.gaps, {"version": 1, "gaps": []})
    _write_yaml(paths.resource_requirements, {"version": 1, "resources": []})

    save_state(paths.workflow_state, initial_state(client_id))
    return client_dir


def main() -> int:
    parser = argparse.ArgumentParser(description="Initialize an agency client workflow workspace")
    parser.add_argument("client_id")
    parser.add_argument("--name", dest="display_name")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    client_dir = initialize_client(root, args.client_id, args.display_name)
    print(client_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
