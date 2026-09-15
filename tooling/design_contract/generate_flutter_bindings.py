from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .flutter_bindings import load_flutter_bindings


GENERATED_RELATIVE = (
    Path("apps") / "prototype_app" / "lib" / "registry" / "generated_design_bindings.dart"
)

_HEADER = (
    "// GENERATED FILE. DO NOT EDIT.\n"
    "// Source: design-contract/bindings/flutter/*.yaml\n"
    "\n"
)

_CLASS = """class DesignBinding {
  const DesignBinding({
    required this.id,
    required this.kind,
    required this.registryKey,
    required this.symbol,
    required this.variants,
    required this.states,
    required this.density,
  });

  final String id;
  final String kind;
  final String registryKey;
  final String symbol;
  final Map<String, String> variants;
  final Map<String, String> states;
  final Map<String, String> density;
}

"""


def _dart_string(value: object) -> str:
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", "\\$")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )


def _render_map(name: str, mapping: object) -> str:
    if not isinstance(mapping, dict) or not mapping:
        return f"    {name}: <String, String>{{}},"
    entries = "\n".join(
        f"      '{_dart_string(key)}': '{_dart_string(mapping[key])}',"
        for key in sorted(mapping, key=str)
    )
    return f"    {name}: <String, String>{{\n{entries}\n    }},"


def _render_binding(binding_id: str, binding: dict) -> str:
    implementation = binding["implementation"]
    lines = [
        f"  '{_dart_string(binding_id)}': DesignBinding(",
        f"    id: '{_dart_string(binding_id)}',",
        f"    kind: '{_dart_string(binding['kind'])}',",
        f"    registryKey: '{_dart_string(implementation['registry_key'])}',",
        f"    symbol: '{_dart_string(implementation['symbol'])}',",
        _render_map("variants", binding.get("variants")),
        _render_map("states", binding.get("states")),
        _render_map("density", binding.get("density")),
        "  ),",
    ]
    return "\n".join(lines)


def render_flutter_bindings(root: Path) -> str:
    """Return the deterministic Dart projection of approved Flutter bindings."""
    bindings = load_flutter_bindings(root)
    approved = {
        binding_id: binding
        for binding_id, binding in bindings.items()
        if binding.get("status") == "approved"
    }
    blocks = "\n".join(
        _render_binding(binding_id, approved[binding_id])
        for binding_id in sorted(approved)
    )
    return (
        _HEADER
        + _CLASS
        + "const Map<String, DesignBinding> generatedDesignBindings = "
        + "<String, DesignBinding>{\n"
        + blocks
        + "\n};\n"
    )


def write_flutter_bindings(root: Path) -> Path:
    """Write the generated Dart projection and return its path."""
    path = root / GENERATED_RELATIVE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_flutter_bindings(root), encoding="utf-8", newline="\n")
    return path


def check_flutter_bindings_fresh(root: Path) -> list[str]:
    """Return a deterministic error list when the checked projection is not fresh.

    Comparison is byte-exact (including line endings) so a CRLF or otherwise
    re-encoded projection is reported stale.
    """
    relative = GENERATED_RELATIVE.as_posix()
    path = root / GENERATED_RELATIVE
    if not path.exists():
        return [f"{relative}: generated Flutter binding projection is missing"]
    expected = render_flutter_bindings(root).encode("utf-8")
    if path.read_bytes() != expected:
        return [
            f"{relative}: generated Flutter binding projection is stale; regenerate with "
            "python -m tooling.design_contract.generate_flutter_bindings --write"
        ]
    return []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate Flutter design bindings.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="write the projection")
    group.add_argument("--check", action="store_true", help="check freshness only")
    parser.add_argument("--root", type=Path, default=None)
    args = parser.parse_args(argv)

    root = args.root if args.root is not None else Path(__file__).resolve().parents[2]

    if args.write:
        path = write_flutter_bindings(root)
        print(f"Wrote {path}")
        return 0

    errors = check_flutter_bindings_fresh(root)
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Generated Flutter binding projection is fresh.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
