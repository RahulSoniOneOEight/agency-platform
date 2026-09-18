"""Deterministic, non-executing validation of versioned Supabase migrations.

The validator only reads migration text. It never connects to a database and
never executes SQL, so it is safe in normal CI where no Supabase project is
available.

Each migration lives at ``supabase/migrations/<version>_<name>.sql`` and must
carry exactly one explicit metadata header::

    -- migration-class: additive|transformative|destructive

Migration class semantics (see ``MIGRATION_CLASS_SEMANTICS``):

- ``additive`` — new table/column/index; existing data is left untouched.
- ``transformative`` — backfill or reshape of existing data/relationships; the
  affected rows are preserved.
- ``destructive`` — rename/drop/removal of tables, columns or data.

Errors are returned as a stable sorted list of strings (``[]`` means valid).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

MIGRATIONS_RELATIVE = Path("supabase") / "migrations"
MIGRATIONS_PREFIX = MIGRATIONS_RELATIVE.as_posix()

MIGRATION_CLASS_SEMANTICS: dict[str, str] = {
    "additive": "new table/column/index; existing data is left untouched",
    "transformative": (
        "backfill or reshape of existing data/relationships; rows are preserved"
    ),
    "destructive": "rename/drop/removal of tables, columns or data",
}

SUPPORTED_CLASSES = frozenset(MIGRATION_CLASS_SEMANTICS)

_FILENAME = re.compile(r"^(?P<version>\d{12,14})_(?P<name>[a-z0-9_]+)\.sql$")
_CLASS_HEADER = re.compile(r"^--\s*migration-class:\s*(\S+)\s*$", re.MULTILINE)


def validate_migrations(root: Path) -> list[str]:
    """Return stable sorted migration errors for ``root`` (``[]`` == valid)."""
    migrations = Path(root) / MIGRATIONS_RELATIVE
    if not migrations.is_dir():
        return [f"{MIGRATIONS_PREFIX}: missing migrations directory"]

    errors: list[str] = []
    versions: dict[str, list[str]] = {}

    for path in sorted(candidate for candidate in migrations.iterdir() if candidate.is_file()):
        if path.suffix != ".sql":
            continue
        relative = f"{MIGRATIONS_PREFIX}/{path.name}"
        match = _FILENAME.match(path.name)
        if match is None:
            errors.append(f"{relative}: invalid migration filename")
            continue

        versions.setdefault(match.group("version"), []).append(path.name)

        text = path.read_text(encoding="utf-8", errors="replace")
        headers = _CLASS_HEADER.findall(text)
        if not headers:
            errors.append(f"{relative}: missing migration-class header")
            continue
        if len(headers) > 1:
            declared = ", ".join(sorted(set(headers)))
            errors.append(
                f"{relative}: multiple migration-class headers ({declared})"
            )
            continue
        migration_class = headers[0]
        if migration_class not in SUPPORTED_CLASSES:
            errors.append(f"{relative}: unsupported migration-class {migration_class!r}")

    for version, names in sorted(versions.items()):
        if len(names) > 1:
            duplicates = ", ".join(sorted(names))
            errors.append(
                f"{MIGRATIONS_PREFIX}: duplicate migration version {version} ({duplicates})"
            )

    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate migrations, print errors, return exit code."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    root = Path(arguments[0]) if arguments else Path(__file__).resolve().parents[2]
    errors = validate_migrations(root)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
