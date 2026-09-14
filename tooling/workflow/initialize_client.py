from __future__ import annotations

import argparse
import re
from pathlib import Path

import yaml

from tooling.workflow.state import initial_state, save_state


CLIENT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,62}$")

_MODULE_TEMPLATES = {
    "business-rules.yaml": {"version": 1, "provided": False, "rules": []},
    "user-groups.yaml": {"version": 1, "provided": False, "groups": []},
    "journey-priorities.yaml": {"version": 1, "provided": False, "journeys": []},
    "feature-requirements.yaml": {"version": 1, "provided": False, "features": []},
    "platform-requirements.yaml": {"version": 1, "provided": False, "requirements": []},
    "integration-requirements.yaml": {"version": 1, "provided": False, "integrations": []},
    "content-requirements.yaml": {"version": 1, "provided": False, "requirements": []},
    "data-context.yaml": {"version": 1, "provided": False, "entities": []},
    "constraints.yaml": {"version": 1, "provided": False, "constraints": []},
    "open-questions.yaml": {"version": 1, "provided": False, "questions": []},
}

_COLLECTION_TEMPLATES = {
    "brand": {"brand-input.yaml": {"version": 1, "provided": False, "facts": []}},
    "references": {"references.yaml": {"version": 1, "provided": False, "references": []}},
    "assets": {"asset-manifest.yaml": {"version": 1, "provided": False, "assets": []}},
    "source-documents": {"source-documents.yaml": {"version": 1, "provided": False, "documents": []}},
}

_DIRECTORIES = [
    "input",
    "input/brand",
    "input/brand/brand-assets",
    "input/references",
    "input/references/current-app",
    "input/references/competitor",
    "input/references/inspiration",
    "input/assets",
    "input/assets/products",
    "input/assets/categories",
    "input/assets/banners",
    "input/assets/sellers",
    "input/assets/videos",
    "input/source-documents",
    "derived",
    "resources",
    "directions",
    "prototype",
]

_EMPTY_DIRECTORIES = [
    "resources",
    "directions",
    "prototype",
    "input/brand/brand-assets",
    "input/references/current-app",
    "input/references/competitor",
    "input/references/inspiration",
    "input/assets/products",
    "input/assets/categories",
    "input/assets/banners",
    "input/assets/sellers",
    "input/assets/videos",
]


def initialize_client(root: Path, client_id: str, display_name: str | None = None) -> Path:
    if not CLIENT_ID_RE.fullmatch(client_id):
        raise ValueError("client_id must use lowercase letters, numbers, and hyphens")

    client_dir = root / "client-projects" / client_id
    if client_dir.exists():
        raise FileExistsError(f"client already exists: {client_id}")

    name = display_name or client_id

    for rel in _DIRECTORIES:
        (client_dir / rel).mkdir(parents=True, exist_ok=True)

    input_dir = client_dir / "input"
    (input_dir / "client-input.yaml").write_text(
        yaml.safe_dump(
            {
                "version": 1,
                "client": {"id": client_id, "display_name": name},
                "source_status": "client_supplied",
                "modules": {},
                "collections": {},
                "unresolved_input": True,
            },
            sort_keys=False,
        ),
        encoding="utf-8",
    )

    for filename, content in _MODULE_TEMPLATES.items():
        (input_dir / filename).write_text(yaml.safe_dump(content, sort_keys=False), encoding="utf-8")

    for subdir, files in _COLLECTION_TEMPLATES.items():
        for filename, content in files.items():
            (input_dir / subdir / filename).write_text(yaml.safe_dump(content, sort_keys=False), encoding="utf-8")

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
    (client_dir / "derived" / "client-profile.yaml").write_text(
        yaml.safe_dump(profile, sort_keys=False), encoding="utf-8"
    )

    for rel in _EMPTY_DIRECTORIES:
        (client_dir / rel / ".gitkeep").write_text("", encoding="utf-8")

    (client_dir / "brief.md").write_text(f"# {name}\n\nClient brief pending.\n", encoding="utf-8")
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
