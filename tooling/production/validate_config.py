"""Deterministic validation of the reference production environment configs.

The validator only reads JSON text. It never contacts Supabase, a payment
provider, or any other service, so it is safe in normal CI where no production
credentials exist.

Each runtime environment (``dev``, ``staging``, ``production``) must have a
``production/config/<environment>.json`` file whose keys are exactly the
client-safe :class:`~agency_production_core.EnvironmentConfig` allowlist. A
config is rejected when:

- an environment file is missing;
- the JSON is malformed or is not an object;
- the declared ``environment`` does not match the file name;
- a key is not on the client-safe allowlist;
- a key name (at any nesting depth) contains a privileged fragment
  (``service_role``, ``secret``, ``private_key``, ``webhook_secret``,
  ``erp_password``, ``payment_secret``, ``whatsapp_token``);
- a value has the wrong type.

Errors are returned as a stable sorted list of strings (``[]`` means valid).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED_ENVIRONMENTS: tuple[str, ...] = ("dev", "staging", "production")

# Exactly the EnvironmentConfig allowlist (controller ruling R4). Any other key
# makes ``EnvironmentConfig.fromJson`` throw, so it is rejected here too.
ALLOWED_KEYS: frozenset[str] = frozenset(
    {
        "environment",
        "api_base_url",
        "supabase_url",
        "supabase_anon_key",
        "analytics_enabled",
        "feature_flags",
        "integration_modes",
        "app_version",
    }
)

# Privileged key fragments (controller ruling R2 / task brief). A key whose
# normalized name contains any of these is never client-safe.
FORBIDDEN_KEY_FRAGMENTS: tuple[str, ...] = (
    "service_role",
    "secret",
    "private_key",
    "webhook_secret",
    "erp_password",
    "payment_secret",
    "whatsapp_token",
)

CONFIG_RELATIVE = Path("production") / "config"


def _relative(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def _normalize_key(key: str) -> str:
    return key.strip().lower().replace("-", "_")


def _contains_forbidden_fragment(key: str) -> bool:
    normalized = _normalize_key(key)
    return any(fragment in normalized for fragment in FORBIDDEN_KEY_FRAGMENTS)


def _walk_keys(value: object, prefix: str = ""):
    """Yield every mapping key path in ``value``, depth-first."""
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                continue
            path = f"{prefix}.{key}" if prefix else key
            yield path
            yield from _walk_keys(child, path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk_keys(child, f"{prefix}[{index}]")


def _validate_value_types(relative: str, payload: dict) -> list[str]:
    errors: list[str] = []

    def is_string(value: object) -> bool:
        return isinstance(value, str)

    api_base_url = payload.get("api_base_url")
    if not isinstance(api_base_url, str) or not api_base_url.strip():
        errors.append(f"{relative}: api_base_url must be a non-empty string")

    for key in ("supabase_url", "supabase_anon_key", "app_version"):
        if key in payload and not is_string(payload[key]):
            errors.append(f"{relative}: {key} must be a string")

    if "analytics_enabled" in payload and not isinstance(
        payload["analytics_enabled"], bool
    ):
        errors.append(f"{relative}: analytics_enabled must be a boolean")

    feature_flags = payload.get("feature_flags")
    if feature_flags is not None:
        if not isinstance(feature_flags, dict):
            errors.append(f"{relative}: feature_flags must be an object")
        elif any(
            not isinstance(name, str) or not isinstance(flag, bool)
            for name, flag in feature_flags.items()
        ):
            errors.append(f"{relative}: feature_flags must map strings to booleans")

    integration_modes = payload.get("integration_modes")
    if integration_modes is not None:
        if not isinstance(integration_modes, dict):
            errors.append(f"{relative}: integration_modes must be an object")
        elif any(
            not isinstance(name, str) or not isinstance(mode, str)
            for name, mode in integration_modes.items()
        ):
            errors.append(
                f"{relative}: integration_modes must map strings to strings"
            )

    return errors


def _validate_config_file(path: Path, environment: str, root: Path) -> list[str]:
    relative = _relative(path, root)
    if not path.is_file():
        return [f"{relative}: missing {environment} environment config"]

    raw = path.read_text(encoding="utf-8", errors="replace")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as error:
        return [f"{relative}: invalid JSON: {error.msg}"]

    if not isinstance(payload, dict):
        return [f"{relative}: config must be a JSON object"]

    errors: list[str] = []

    declared = payload.get("environment")
    if declared != environment:
        errors.append(
            f"{relative}: environment must be {environment!r}, found {declared!r}"
        )

    for key in payload:
        if key not in ALLOWED_KEYS:
            errors.append(f"{relative}: unsupported configuration key: {key}")

    for key_path in _walk_keys(payload):
        if _contains_forbidden_fragment(key_path.split(".")[-1]):
            errors.append(f"{relative}: privileged configuration key: {key_path}")

    errors.extend(_validate_value_types(relative, payload))

    return errors


def validate_production_config(root: Path, client_dir: Path) -> list[str]:
    """Return stable sorted config errors for ``client_dir`` (``[]`` == valid)."""
    root = Path(root)
    client_dir = Path(client_dir)
    config_dir = client_dir / CONFIG_RELATIVE

    if not config_dir.is_dir():
        return [
            f"{_relative(config_dir, root)}: missing production config directory"
        ]

    errors: list[str] = []
    for environment in REQUIRED_ENVIRONMENTS:
        path = config_dir / f"{environment}.json"
        errors.extend(_validate_config_file(path, environment, root))

    return sorted(set(errors))


def main(argv: list[str] | None = None) -> int:
    """CLI entry point: validate configs, print errors, return exit code."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    root = Path(__file__).resolve().parents[2]
    client_dir = (
        Path(arguments[0])
        if arguments
        else root / "client-projects" / "reference-commerce"
    )
    errors = validate_production_config(root, client_dir)
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
