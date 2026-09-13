from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def yaml_files(path: Path) -> list[Path]:
    if not path.exists():
        return []
    return sorted([*path.glob("*.yaml"), *path.glob("*.yml")])
