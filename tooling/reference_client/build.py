"""Deterministic build entry point for the reference-commerce client.

Composes the prototype through the existing platform composer and generates the
runtime bundle through the existing runtime-bundle builder. No shortcuts: this
is the normal platform flow.

Usage::

    py -3.12 -m tooling.reference_client.build
"""

from __future__ import annotations

import argparse
from pathlib import Path

from tooling.prototype.build_prototype import compose_prototype
from tooling.prototype.build_runtime_bundle import build_runtime_bundle

DEFAULT_CLIENT_DIR = Path("client-projects") / "reference-commerce"
GENERATED_RELATIVE = Path("apps") / "prototype_app" / "assets" / "generated"


def build_reference_client(root: Path, client_dir: Path) -> list[str]:
    """Compose the prototype and generate the bundle; ``[]`` on success."""
    try:
        compose_prototype(root, client_dir)
        build_runtime_bundle(root, client_dir, root / GENERATED_RELATIVE)
    except (OSError, UnicodeError, ValueError) as exc:
        return [str(exc)]
    return []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tooling.reference_client.build",
        description="Compose the reference-commerce prototype and generate its runtime bundle.",
    )
    parser.add_argument(
        "client_dir",
        nargs="?",
        default=str(DEFAULT_CLIENT_DIR),
        help="Client project directory (default: client-projects/reference-commerce).",
    )
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[2]
    client_dir = Path(args.client_dir)
    if not client_dir.is_absolute():
        client_dir = root / client_dir

    errors = build_reference_client(root, client_dir)
    if errors:
        print("Reference client build failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"Composed prototype manifest: {client_dir / 'prototype' / 'prototype-manifest.yaml'}")
    print(f"Generated runtime bundle: {root / GENERATED_RELATIVE / f'{client_dir.name}.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
