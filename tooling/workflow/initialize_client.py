from __future__ import annotations

import argparse
import re
from pathlib import Path

import yaml

from tooling.workflow.state import initial_state, save_state


CLIENT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}$")


def initialize_client(root: Path, client_id: str, display_name: str | None = None) -> Path:
    if not CLIENT_ID_RE.fullmatch(client_id):
        raise ValueError("client_id must use lowercase letters, numbers, and hyphens")

    client_dir = root / "client-projects" / client_id
    if client_dir.exists():
        raise FileExistsError(f"client already exists: {client_id}")

    client_dir.mkdir(parents=True)
    for folder in ("references", "resources", "directions", "fixtures"):
        path = client_dir / folder
        path.mkdir()
        (path / ".gitkeep").write_text("", encoding="utf-8")

    name = display_name or client_id
    (client_dir / "brief.md").write_text(f"# {name}\n\nClient brief pending.\n", encoding="utf-8")
    profile = {
        "id": client_id,
        "display_name": name,
        "business_model": "",
        "industry": "",
        "use_cases": [],
        "objectives": [],
        "personas": [],
        "jobs": [],
        "platforms": [],
    }
    (client_dir / "client-profile.yaml").write_text(yaml.safe_dump(profile, sort_keys=False), encoding="utf-8")
    save_state(client_dir / "workflow-state.yaml", initial_state(client_id))
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
