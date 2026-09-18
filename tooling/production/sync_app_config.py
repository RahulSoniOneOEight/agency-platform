"""Sync the validated production configs into the Flutter app asset boundary.

The canonical environment files live under
``client-projects/reference-commerce/production/config/<environment>.json`` and
are validated by :mod:`tooling.production.validate_config`. The Flutter app can
only load assets from inside its own package, so the canonical files are copied
byte-for-byte into ``apps/production_app/assets/config/``. This keeps the
runtime from silently drifting away from the validated files.

- Default mode writes the assets.
- ``--check`` mode writes nothing and reports missing or byte-stale assets.

Errors are returned as a stable sorted list of strings (``[]`` means in sync).
"""

from __future__ import annotations

import sys
from pathlib import Path

from tooling.production.validate_config import (
    CONFIG_RELATIVE,
    REQUIRED_ENVIRONMENTS,
)

APP_ASSETS_RELATIVE = Path("apps") / "production_app" / "assets" / "config"


def _relative(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def sync_app_config(
    root: Path,
    client_dir: Path,
    *,
    check: bool = False,
) -> list[str]:
    """Copy (or ``--check``) the canonical configs into the app asset boundary.

    Returns stable sorted errors (``[]`` means every asset is present and, in
    check mode, byte-identical to its canonical source).
    """
    root = Path(root)
    client_dir = Path(client_dir)
    source_dir = client_dir / CONFIG_RELATIVE
    target_dir = root / APP_ASSETS_RELATIVE

    if not source_dir.is_dir():
        return [f"{_relative(source_dir, root)}: missing production config directory"]

    errors: list[str] = []
    for environment in REQUIRED_ENVIRONMENTS:
        source = source_dir / f"{environment}.json"
        target = target_dir / f"{environment}.json"
        target_relative = _relative(target, root)

        if not source.is_file():
            errors.append(
                f"{_relative(source, root)}: missing {environment} environment config"
            )
            continue

        source_bytes = source.read_bytes()

        if check:
            if not target.is_file():
                errors.append(f"{target_relative}: missing app config asset")
            elif target.read_bytes() != source_bytes:
                errors.append(
                    f"{target_relative}: app config asset is stale; "
                    f"run python -m tooling.production.sync_app_config"
                )
            continue

        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source_bytes)

    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: sync (or ``--check``) app config assets."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    check = "--check" in arguments
    positional = [argument for argument in arguments if not argument.startswith("--")]

    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(positional[0])
        if positional
        else root / "client-projects" / "reference-commerce"
    )

    errors = sync_app_config(root, client_dir, check=check)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
