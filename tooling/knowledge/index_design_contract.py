from __future__ import annotations

from pathlib import Path

from tooling.knowledge.io import load_yaml, yaml_files


def _index_directory(path: Path) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for file_path in yaml_files(path):
        item = load_yaml(file_path)
        if not isinstance(item, dict) or "id" not in item:
            continue
        result[item["id"]] = item
    return dict(sorted(result.items()))


def build_indexes(root: Path) -> dict[str, dict[str, dict]]:
    base = root / "design-contract"
    return {
        "components": _index_directory(base / "components"),
        "patterns": _index_directory(base / "patterns"),
        "journeys": _index_directory(base / "journeys"),
    }
