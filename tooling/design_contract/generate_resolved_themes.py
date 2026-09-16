from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

from tooling.prototype.build_runtime_bundle import (
    build_runtime_bundle,
    compose_runtime_bundle,
)

OUTPUT_RELATIVE = Path("apps") / "prototype_app" / "assets" / "generated"


def client_manifests(root: Path) -> list[Path]:
    projects = root / "client-projects"
    if not projects.exists():
        return []
    return sorted(projects.glob("**/prototype/prototype-manifest.yaml"))


def _client_id(manifest_path: Path) -> str | None:
    try:
        manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, yaml.YAMLError):
        return None
    if not isinstance(manifest, dict):
        return None
    client_id = manifest.get("client_id")
    return client_id if isinstance(client_id, str) and client_id else None


def write_resolved_bundles(root: Path) -> list[Path]:
    """Regenerate every checked client runtime bundle from source."""
    written: list[Path] = []
    for manifest_path in client_manifests(root):
        client_dir = manifest_path.parent.parent
        written.append(build_runtime_bundle(root, client_dir, root / OUTPUT_RELATIVE))
    return written


def check_resolved_bundles_fresh(root: Path) -> list[str]:
    """Return deterministic errors for missing or stale generated runtime bundles."""
    errors: list[str] = []
    for manifest_path in client_manifests(root):
        client_dir = manifest_path.parent.parent
        client_id = _client_id(manifest_path)
        if client_id is None:
            errors.append(f"{manifest_path}: client_id must be a non-empty string")
            continue

        bundle_path = root / OUTPUT_RELATIVE / f"{client_id}.json"
        if not bundle_path.exists():
            errors.append(
                f"{bundle_path}: missing generated runtime bundle for client {client_id!r}"
            )
            continue

        try:
            fresh = compose_runtime_bundle(root, client_dir)
            expected = (
                json.dumps(fresh, indent=2, sort_keys=True, allow_nan=False) + "\n"
            ).encode("utf-8")
        except (OSError, UnicodeError, ValueError) as exc:
            errors.append(f"{bundle_path}: cannot recompose runtime bundle: {exc}")
            continue

        if bundle_path.read_bytes() != expected:
            errors.append(
                f"{bundle_path}: generated runtime bundle is stale; regenerate with "
                "python -m tooling.design_contract.generate_resolved_themes --write"
            )

    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate or check resolved client runtime bundles."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="write resolved bundles")
    group.add_argument("--check", action="store_true", help="check freshness only")
    parser.add_argument("--root", type=Path, default=None)
    args = parser.parse_args(argv)

    root = args.root if args.root is not None else Path(__file__).resolve().parents[2]

    if args.write:
        for path in write_resolved_bundles(root):
            print(f"Wrote {path}")
        return 0

    errors = check_resolved_bundles_fresh(root)
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Resolved client runtime bundles are fresh.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
