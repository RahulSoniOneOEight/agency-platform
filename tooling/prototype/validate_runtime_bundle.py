from __future__ import annotations

import re

from .project_direction import validate_runtime_direction


_CLIENT_ID = re.compile(r"[A-Za-z0-9._-]+")
_SEED_COLOR = re.compile(r"#[0-9A-Fa-f]{6}")
_CANONICAL_RESOURCE_ID = re.compile(
    r"(?:asset|icon|motion|resource)(?:\.[A-Za-z0-9_-]+)+"
)
_RESOURCE_PREFIXES = {
    "image": "asset.",
    "icon": "icon.",
    "motion": "motion.",
}


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _validate_fixture_item(
    item: object,
    *,
    path: str,
    string_fields: tuple[str, ...],
    number_fields: tuple[str, ...],
    integer_fields: tuple[str, ...],
) -> list[str]:
    if not isinstance(item, dict):
        return [f"{path} must be an object"]

    errors: list[str] = []
    for field in string_fields:
        value = item.get(field)
        if not isinstance(value, str) or not value:
            errors.append(f"{path}.{field} must be a non-empty string")
    for field in number_fields:
        if not _is_number(item.get(field)):
            errors.append(f"{path}.{field} must be a number")
    for field in integer_fields:
        value = item.get(field)
        if not isinstance(value, int) or isinstance(value, bool):
            errors.append(f"{path}.{field} must be an integer")
    return errors


def _validate_fixtures(fixtures: object) -> list[str]:
    if not isinstance(fixtures, dict):
        return ["fixtures must be an object"]

    errors: list[str] = []
    industry = fixtures.get("industry")
    if not isinstance(industry, str) or not industry:
        errors.append("fixtures.industry must be a non-empty string")
    seed = fixtures.get("seed")
    if not isinstance(seed, int) or isinstance(seed, bool):
        errors.append("fixtures.seed must be an integer")

    products = fixtures.get("products")
    if not isinstance(products, list):
        errors.append("fixtures.products must be an array")
    else:
        for index, product in enumerate(products):
            errors.extend(
                _validate_fixture_item(
                    product,
                    path=f"fixtures.products.{index}",
                    string_fields=("id", "sku", "name", "category"),
                    number_fields=("price", "compare_at", "rating"),
                    integer_fields=("stock",),
                )
            )

    services = fixtures.get("services")
    if not isinstance(services, list):
        errors.append("fixtures.services must be an array")
    else:
        for index, service in enumerate(services):
            errors.extend(
                _validate_fixture_item(
                    service,
                    path=f"fixtures.services.{index}",
                    string_fields=("id", "name"),
                    number_fields=("price", "rating"),
                    integer_fields=("duration_minutes",),
                )
            )
    return errors


def _validate_resource_binding(binding: object, path: str) -> list[str]:
    if not isinstance(binding, dict):
        return [f"{path} must be an object"]

    errors: list[str] = []
    for field in ("candidate_id", "source", "type"):
        value = binding.get(field)
        if not isinstance(value, str) or not value:
            errors.append(f"{path}.{field} must be a non-empty string")
    if not isinstance(binding.get("asset"), dict):
        errors.append(f"{path}.asset must be an object")
    return errors


def _validate_binding_group(group: object, path: str) -> list[str]:
    if not isinstance(group, dict):
        return [f"{path} must be an object"]

    errors: list[str] = []
    candidate_owners: dict[str, str] = {}
    for canonical_id, binding in group.items():
        binding_path = f"{path}.{canonical_id}"
        if (
            not isinstance(canonical_id, str)
            or not _CANONICAL_RESOURCE_ID.fullmatch(canonical_id)
        ):
            errors.append(f"{binding_path}: invalid canonical resource id")
        errors.extend(_validate_resource_binding(binding, binding_path))
        if not isinstance(binding, dict):
            continue

        resource_type = binding.get("type")
        expected_prefix = _RESOURCE_PREFIXES.get(resource_type, "resource.")
        if isinstance(canonical_id, str) and not canonical_id.startswith(expected_prefix):
            errors.append(
                f"{binding_path}: canonical resource id must start with "
                f"{expected_prefix!r} for type {resource_type!r}"
            )

        candidate_id = binding.get("candidate_id")
        if isinstance(candidate_id, str) and candidate_id:
            existing_owner = candidate_owners.get(candidate_id)
            if existing_owner is not None and existing_owner != canonical_id:
                errors.append(
                    f"{path}: canonical resource collision for candidate {candidate_id!r} "
                    f"between {existing_owner!r} and {canonical_id!r}"
                )
            else:
                candidate_owners[candidate_id] = canonical_id
    return errors


def _validate_resources(resources: object, direction_ids: set[str]) -> list[str]:
    if not isinstance(resources, dict):
        return ["resources must be an object"]

    base = {key: value for key, value in resources.items() if key != "direction_overrides"}
    errors = _validate_binding_group(base, "resources")
    if "direction_overrides" not in resources:
        return errors

    overrides = resources["direction_overrides"]
    if not isinstance(overrides, dict):
        return errors + ["resources.direction_overrides must be an object"]
    for direction_id, group in overrides.items():
        path = f"resources.direction_overrides.{direction_id}"
        if direction_id not in direction_ids:
            errors.append(f"{path} references unknown direction")
        errors.extend(_validate_binding_group(group, path))
    return errors


def validate_runtime_bundle(bundle: dict) -> list[str]:
    if not isinstance(bundle, dict):
        return ["runtime bundle must be an object"]

    errors: list[str] = []
    version = bundle.get("version")
    if not isinstance(version, int) or isinstance(version, bool) or version != 1:
        errors.append("version must equal 1")

    client_id = bundle.get("client_id")
    if not isinstance(client_id, str) or not _CLIENT_ID.fullmatch(client_id):
        errors.append("client_id must be a non-empty safe ID matching [A-Za-z0-9._-]+")

    directions = bundle.get("directions")
    direction_ids: set[str] = set()
    expected_order: list[str] = []
    if not isinstance(directions, dict):
        errors.append("directions must be an object")
    else:
        direction_ids = {key for key in directions if isinstance(key, str)}
        expected_order = sorted(direction_ids)
        if not 2 <= len(directions) <= 3:
            errors.append("directions must contain exactly 2 or 3 entries")
        if not {"a", "b"}.issubset(direction_ids):
            errors.append("directions must include a and b")
        if (
            not direction_ids.issubset({"a", "b", "c"})
            or len(direction_ids) != len(directions)
        ):
            errors.append("direction IDs must be a, b, and optional c")
        for direction_id, direction in directions.items():
            path = f"directions.{direction_id}"
            if not isinstance(direction, dict):
                errors.append(f"{path} must be an object")
                continue
            errors.extend(
                f"{path}.{error}" for error in validate_runtime_direction(direction)
            )
            if direction.get("id") != direction_id:
                errors.append(
                    f"{path}: direction key {direction_id!r} must equal embedded id "
                    f"{direction.get('id')!r}"
                )

    default_direction = bundle.get("default_direction")
    if not isinstance(default_direction, str) or default_direction not in direction_ids:
        errors.append("default_direction must identify an existing direction")

    review = bundle.get("review")
    if not isinstance(review, dict):
        errors.append("review must be an object")
    elif review.get("allowed_directions") != expected_order:
        errors.append(
            "review.allowed_directions must exactly equal direction keys in "
            f"deterministic order {expected_order!r}"
        )

    errors.extend(_validate_fixtures(bundle.get("fixtures")))

    theme = bundle.get("theme")
    if not isinstance(theme, dict):
        errors.append("theme must be an object")
    else:
        seed_color = theme.get("seed_color")
        if not isinstance(seed_color, str) or not _SEED_COLOR.fullmatch(seed_color):
            errors.append("theme.seed_color must be a #RRGGBB color")

    errors.extend(_validate_resources(bundle.get("resources"), direction_ids))
    return errors
