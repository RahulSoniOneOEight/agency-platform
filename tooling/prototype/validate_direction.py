from __future__ import annotations

REQUIRED_FIELDS = (
    "id",
    "name",
    "strategic_goal",
    "navigation",
    "primary_journey",
    "discovery_model",
    "merchandising",
    "density",
    "transaction_model",
    "patterns",
    "components",
    "strengths",
    "tradeoffs",
)


def validate_direction(direction: dict) -> list[str]:
    errors: list[str] = []
    for field in REQUIRED_FIELDS:
        value = direction.get(field)
        if value is None or value == "" or value == []:
            errors.append(f"missing required direction field: {field}")
    for field in ("patterns", "components", "strengths", "tradeoffs"):
        value = direction.get(field)
        if value is not None and not isinstance(value, list):
            errors.append(f"direction field must be a list: {field}")
    if direction.get("density") not in {None, "airy", "balanced", "dense"}:
        errors.append("density must be one of: airy, balanced, dense")
    return errors
