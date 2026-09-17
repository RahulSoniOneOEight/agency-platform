"""Deterministic synthetic reference-client fixture contract.

The fixture is the single source of synthetic B2C+B2B commerce data for the
``reference-commerce`` client. It is entirely invented (no PII) and must be
byte-reproducible: identity is a content hash over canonical sorted JSON.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

SUPPORTED_FIXTURE_VERSIONS = frozenset({1})

FIXTURE_RELATIVE = Path("reference-e2e") / "fixture.yaml"
SCHEMA_RELATIVE = (
    Path("client-projects") / "schema" / "reference-client-fixture.schema.json"
)

ENTITY_LISTS: dict[str, str] = {
    "categories": "id",
    "collections": "id",
    "products": "id",
    "variants": "id",
    "promotions": "id",
    "accounts": "id",
    "quotations": "id",
    "rfqs": "id",
    "carts": "id",
    "orders": "id",
    "validation_states": "id",
}

REQUIRED_ENTITY_LISTS = tuple(ENTITY_LISTS)


def load_fixture(path: Path) -> dict[str, Any]:
    """Load and shape-check a fixture document.

    Raises ``ValueError`` when the document is not a mapping or does not declare
    ``client_id`` / ``fixture_version``.
    """
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"fixture must be a mapping: {path}")
    if not isinstance(data.get("client_id"), str) or not data["client_id"]:
        raise ValueError(f"fixture requires a non-empty client_id: {path}")
    if "fixture_version" not in data:
        raise ValueError(f"fixture requires fixture_version: {path}")
    return data


def _schema_errors(root: Path, fixture: dict[str, Any]) -> list[str]:
    schema_path = root / SCHEMA_RELATIVE
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(fixture), key=lambda error: list(error.path))
    return [
        f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}"
        for error in errors
    ]


def _duplicate_id_errors(fixture: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for name, id_key in ENTITY_LISTS.items():
        entries = fixture.get(name)
        if not isinstance(entries, list):
            continue
        seen: set[Any] = set()
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            entry_id = entry.get(id_key)
            if entry_id is None:
                continue
            if entry_id in seen:
                errors.append(f"{name}.{index}: duplicate {id_key} {entry_id!r}")
            seen.add(entry_id)
    return errors


def _required_entity_errors(fixture: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for name in REQUIRED_ENTITY_LISTS:
        entries = fixture.get(name)
        if not isinstance(entries, list) or not entries:
            errors.append(f"{name}: missing required entity list")
    return errors


def _credit_errors(fixture: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    accounts = fixture.get("accounts")
    if not isinstance(accounts, list):
        return errors
    for index, account in enumerate(accounts):
        if not isinstance(account, dict):
            continue
        account_id = account.get("id", index)
        limit = account.get("credit_limit")
        available = account.get("available_credit")
        is_trade = account.get("type") == "trade"
        if is_trade and (limit is None or available is None):
            errors.append(f"accounts.{index} ({account_id}): trade account requires credit_limit and available_credit")
            continue
        for label, value in (("credit_limit", limit), ("available_credit", available)):
            if value is None:
                continue
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                errors.append(f"accounts.{index} ({account_id}): {label} must be a number")
            elif value < 0:
                errors.append(f"accounts.{index} ({account_id}): {label} must not be negative")
        if (
            isinstance(limit, (int, float))
            and not isinstance(limit, bool)
            and isinstance(available, (int, float))
            and not isinstance(available, bool)
            and available > limit
        ):
            errors.append(
                f"accounts.{index} ({account_id}): available_credit exceeds credit_limit"
            )
    return errors


def _reference_errors(fixture: dict[str, Any]) -> list[str]:
    def ids(name: str) -> set[Any]:
        entries = fixture.get(name)
        if not isinstance(entries, list):
            return set()
        return {
            entry.get("id")
            for entry in entries
            if isinstance(entry, dict) and entry.get("id") is not None
        }

    category_ids = ids("categories")
    product_ids = ids("products")
    variant_ids = ids("variants")
    account_ids = ids("accounts")

    errors: list[str] = []

    products = fixture.get("products")
    if isinstance(products, list):
        for index, product in enumerate(products):
            if not isinstance(product, dict):
                continue
            category = product.get("category")
            if category is not None and category not in category_ids:
                errors.append(f"products.{index}: unknown category {category!r}")
            variant_refs = product.get("variant_ids")
            if isinstance(variant_refs, list):
                for position, variant_id in enumerate(variant_refs):
                    if variant_id not in variant_ids:
                        errors.append(
                            f"products.{index}.variant_ids.{position}: unknown variant {variant_id!r}"
                        )

    variants = fixture.get("variants")
    if isinstance(variants, list):
        for index, variant in enumerate(variants):
            if not isinstance(variant, dict):
                continue
            product_id = variant.get("product_id")
            if product_id is not None and product_id not in product_ids:
                errors.append(f"variants.{index}: unknown product {product_id!r}")

    collections = fixture.get("collections")
    if isinstance(collections, list):
        for index, collection in enumerate(collections):
            if not isinstance(collection, dict):
                continue
            refs = collection.get("category_ids")
            if isinstance(refs, list):
                for position, category_id in enumerate(refs):
                    if category_id not in category_ids:
                        errors.append(
                            f"collections.{index}.category_ids.{position}: unknown category {category_id!r}"
                        )

    for name in ("quotations", "rfqs", "carts", "orders"):
        entries = fixture.get(name)
        if not isinstance(entries, list):
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                continue
            account_id = entry.get("account_id")
            if account_id is not None and account_id not in account_ids:
                errors.append(f"{name}.{index}: unknown account {account_id!r}")
            for collection_key in ("lines", "items", "line_items"):
                line_items = entry.get(collection_key)
                if not isinstance(line_items, list):
                    continue
                for position, item in enumerate(line_items):
                    if not isinstance(item, dict):
                        continue
                    product_id = item.get("product_id")
                    if product_id is not None and product_id not in product_ids:
                        errors.append(
                            f"{name}.{index}.{collection_key}.{position}: "
                            f"unknown product {product_id!r}"
                        )
                    variant_id = item.get("variant_id")
                    if variant_id is not None and variant_id not in variant_ids:
                        errors.append(
                            f"{name}.{index}.{collection_key}.{position}: "
                            f"unknown variant {variant_id!r}"
                        )

    validation_states = fixture.get("validation_states")
    if isinstance(validation_states, list):
        for index, entry in enumerate(validation_states):
            if not isinstance(entry, dict):
                continue
            target = entry.get("target")
            if not isinstance(target, str) or ":" not in target:
                continue
            kind, _, ref = target.partition(":")
            known = {
                "product": product_ids,
                "variant": variant_ids,
                "account": account_ids,
                "category": category_ids,
            }.get(kind)
            if known is not None and ref not in known:
                errors.append(
                    f"validation_states.{index}.target: unknown {kind} {ref!r}"
                )

    return errors


def validate_fixture(root: Path, client_dir: Path) -> list[str]:
    """Return deterministic, stable-sorted fixture errors (``[]`` == valid)."""
    path = client_dir / FIXTURE_RELATIVE
    if not path.exists():
        return [f"{path}: missing fixture"]
    try:
        fixture = load_fixture(path)
    except (OSError, UnicodeError, yaml.YAMLError, ValueError) as exc:
        return [f"{path}: {exc}"]

    errors: list[str] = []
    fixture_version = fixture.get("fixture_version")
    if fixture_version not in SUPPORTED_FIXTURE_VERSIONS:
        errors.append(f"{path}: unsupported fixture_version {fixture_version!r}")

    errors.extend(_schema_errors(root, fixture))
    errors.extend(_duplicate_id_errors(fixture))
    errors.extend(_required_entity_errors(fixture))
    errors.extend(_credit_errors(fixture))
    errors.extend(_reference_errors(fixture))
    return sorted({f"{path}: {error}" for error in errors})


def fixture_identity(fixture: dict[str, Any]) -> str:
    """Return the deterministic ``sha256:<hex>`` identity of a fixture."""
    canonical = json.dumps(
        fixture, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    )
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
