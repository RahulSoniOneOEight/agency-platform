"""Schema and authority helpers for automated QA contracts.

This module is the Python half of the provider-neutral Visual QA seam. It owns:

- the comparison **authority hierarchy** (approved experience → design contract →
  accepted baseline → linked reference → general heuristics), serialized
  explicitly so a lower layer can never be represented as overriding a higher one;
- strict validation of provider *candidates* (the structured output a Visual AI
  provider may return) and of persisted `QAFinding` records;
- the stable **deduplication identity** shared with the Dart domain.

Provider candidates can only ever become `QAFinding` records. This module has no
concept of feedback, review status, approval, blocking, or a single design score,
and it rejects any candidate that tries to smuggle one in.
"""

from __future__ import annotations

import json
from pathlib import Path

from .errors import VisualQaSchemaInvalid

AUTHORITY_ORDER = [
    "approved_experience",
    "design_contract",
    "accepted_baseline",
    "linked_reference",
    "visual_heuristic",
]

ALLOWED_SEVERITIES = ("info", "minor", "major", "blocker")

ALLOWED_SURFACES = ("prototype", "widgetbook")

# Keys a provider must never emit: automated QA may not express review authority.
FORBIDDEN_CANDIDATE_KEYS = frozenset(
    {
        "feedback_id",
        "blocking",
        "review_status",
        "approval",
        "approved",
        "resolved",
        "resolution",
        "quality_score",
        "score",
        "overall_score",
        "merge_gate",
    }
)

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCHEMA_DIR = _REPO_ROOT / "client-projects" / "schema"

_REQUIRED_CANDIDATE_FIELDS = (
    "category",
    "severity",
    "summary",
    "surface",
    "state",
    "rule_source",
    "rule_ref",
)


def load_qa_schema(name: str = "qa-finding.schema.json") -> dict:
    """Load a governed QA JSON schema from ``client-projects/schema``."""
    path = _SCHEMA_DIR / name
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VisualQaSchemaInvalid(f"cannot load QA schema {name}: {error}") from error


def validate_finding_against_schema(finding: object, schema: dict | None = None) -> None:
    """Validate a persisted finding against the governed schema."""
    try:
        import jsonschema
    except ImportError as error:  # pragma: no cover - CI installs jsonschema
        raise VisualQaSchemaInvalid("jsonschema is required to validate QA findings") from error

    if schema is None:
        schema = load_qa_schema()
    try:
        jsonschema.validate(finding, schema)
    except jsonschema.ValidationError as error:
        raise VisualQaSchemaInvalid(
            f"QA finding failed schema validation: {error.message}"
        ) from error


def _require_non_empty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise VisualQaSchemaInvalid(f"QA candidate requires {label}")
    return value.strip()


def _optional_non_empty_string(value: object, label: str) -> str | None:
    if value is None:
        return None
    return _require_non_empty_string(value, label)


def normalize_region(region: object) -> dict:
    """Validate and normalize a normalized evidence region (unit square)."""
    if not isinstance(region, dict):
        raise VisualQaSchemaInvalid("QA region must be a mapping")
    values: dict[str, float] = {}
    for key in ("x", "y", "width", "height"):
        value = region.get(key)
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise VisualQaSchemaInvalid(f"QA region {key} must be numeric")
        number = float(value)
        if number != number or number in (float("inf"), float("-inf")):
            raise VisualQaSchemaInvalid(f"QA region {key} must be finite")
        values[key] = number
    if values["width"] <= 0 or values["height"] <= 0:
        raise VisualQaSchemaInvalid("QA region width and height must be positive")
    if (
        values["x"] < 0
        or values["y"] < 0
        or values["x"] + values["width"] > 1.0000001
        or values["y"] + values["height"] > 1.0000001
    ):
        raise VisualQaSchemaInvalid("QA region must lie inside the unit square")
    return values


def region_canonical(region: dict) -> str:
    return (
        f"{region['x']:.4f},{region['y']:.4f},"
        f"{region['width']:.4f},{region['height']:.4f}"
    )


def validate_candidate(candidate: object) -> dict:
    """Validate a Visual AI candidate; return its normalized form.

    Rejects free-form/unstructured output and any attempt to express review
    authority (feedback, blocking, approval, or a single quality score).
    """
    if not isinstance(candidate, dict):
        raise VisualQaSchemaInvalid("QA candidate must be a mapping")

    forbidden = FORBIDDEN_CANDIDATE_KEYS.intersection(candidate.keys())
    if forbidden:
        raise VisualQaSchemaInvalid(
            "QA candidate must not express review authority: "
            + ", ".join(sorted(forbidden))
        )

    for field in _REQUIRED_CANDIDATE_FIELDS:
        if field not in candidate:
            raise VisualQaSchemaInvalid(f"QA candidate missing field: {field}")

    category = _require_non_empty_string(candidate.get("category"), "category")
    severity = _require_non_empty_string(candidate.get("severity"), "severity")
    if severity not in ALLOWED_SEVERITIES:
        raise VisualQaSchemaInvalid(f"QA candidate has unknown severity: {severity}")
    summary = _require_non_empty_string(candidate.get("summary"), "summary")
    surface = _require_non_empty_string(candidate.get("surface"), "surface")
    if surface not in ALLOWED_SURFACES:
        raise VisualQaSchemaInvalid(f"QA candidate has unknown surface: {surface}")
    state = _require_non_empty_string(candidate.get("state"), "state")
    rule_source = _require_non_empty_string(candidate.get("rule_source"), "rule_source")
    if rule_source not in AUTHORITY_ORDER:
        raise VisualQaSchemaInvalid(
            f"QA candidate has unknown rule source: {rule_source}"
        )
    rule_ref = _require_non_empty_string(candidate.get("rule_ref"), "rule_ref")

    screen = _optional_non_empty_string(candidate.get("screen"), "screen")
    story = _optional_non_empty_string(candidate.get("story"), "story")
    if surface == "prototype" and screen is None:
        raise VisualQaSchemaInvalid("prototype QA candidate requires a screen")
    if surface == "widgetbook" and story is None:
        raise VisualQaSchemaInvalid("widgetbook QA candidate requires a story")

    confidence = candidate.get("confidence")
    if confidence is not None:
        if not isinstance(confidence, (int, float)) or isinstance(confidence, bool):
            raise VisualQaSchemaInvalid("QA candidate confidence must be numeric")
        if confidence < 0 or confidence > 1:
            raise VisualQaSchemaInvalid("QA candidate confidence must be within [0, 1]")

    region = candidate.get("region")
    normalized_region = None if region is None else normalize_region(region)

    evidence = candidate.get("evidence", [])
    if not isinstance(evidence, list):
        raise VisualQaSchemaInvalid("QA candidate evidence must be a list")
    normalized_evidence: list[dict] = []
    for item in evidence:
        if not isinstance(item, dict):
            raise VisualQaSchemaInvalid("QA candidate evidence must be a mapping")
        entry: dict = {}
        if item.get("region") is not None:
            entry["region"] = normalize_region(item["region"])
        ref = _optional_non_empty_string(item.get("ref"), "evidence ref")
        note = _optional_non_empty_string(item.get("note"), "evidence note")
        if ref is not None:
            entry["ref"] = ref
        if note is not None:
            entry["note"] = note
        if not entry:
            raise VisualQaSchemaInvalid("QA candidate evidence requires content")
        normalized_evidence.append(entry)

    return {
        "category": category,
        "severity": severity,
        "summary": summary,
        "surface": surface,
        "screen": screen,
        "story": story,
        "state": state,
        "direction": _optional_non_empty_string(candidate.get("direction"), "direction"),
        "mix_ref": _optional_non_empty_string(candidate.get("mix_ref"), "mix_ref"),
        "section": _optional_non_empty_string(candidate.get("section"), "section"),
        "region": normalized_region,
        "rule_source": rule_source,
        "rule_ref": rule_ref,
        "baseline_ref": _optional_non_empty_string(
            candidate.get("baseline_ref"), "baseline_ref"
        ),
        "confidence": None if confidence is None else float(confidence),
        "evidence": normalized_evidence,
    }


def dedupe_key(candidate: dict, client_id: str) -> str:
    """Stable deduplication identity; must match the Dart domain exactly."""
    normalized = validate_candidate(candidate)
    region = normalized["region"]
    return "|".join(
        [
            "qa-dedupe:v1",
            _require_non_empty_string(client_id, "client_id"),
            normalized["surface"],
            normalized["screen"] or normalized["story"] or "",
            normalized["rule_source"],
            normalized["rule_ref"],
            normalized["category"],
            normalized["section"] or "",
            "" if region is None else region_canonical(region),
            normalized["baseline_ref"] or "",
        ]
    )


def build_authority_bundle(
    *,
    approved_experience: dict | None = None,
    design_contract: dict | None = None,
    accepted_baseline: dict | None = None,
    linked_references: list[dict] | None = None,
    visual_heuristics: list[dict] | None = None,
) -> dict:
    """Build an explicitly ordered authority bundle for a provider request.

    Layers are emitted highest-authority first and always declare
    ``overrides_higher_authority: False``: the bundle can describe lower layers
    but can never assert that they supersede a higher one.
    """
    supplied = {
        "approved_experience": approved_experience,
        "design_contract": design_contract,
        "accepted_baseline": accepted_baseline,
        "linked_reference": linked_references,
        "visual_heuristic": visual_heuristics,
    }
    layers: list[dict] = []
    for rank, source in enumerate(AUTHORITY_ORDER):
        payload = supplied[source]
        if payload is None:
            refs: list[dict] = []
        elif isinstance(payload, list):
            refs = [dict(item) for item in payload]
        else:
            refs = [dict(payload)]
        layers.append(
            {
                "source": source,
                "authority_rank": rank,
                "refs": refs,
                "overrides_higher_authority": False,
            }
        )
    return {"version": 1, "layers": layers}


def validate_authority_bundle(bundle: object) -> dict:
    """Validate that an authority bundle preserves the authority hierarchy."""
    if not isinstance(bundle, dict):
        raise VisualQaSchemaInvalid("authority bundle must be a mapping")
    layers = bundle.get("layers")
    if not isinstance(layers, list) or not layers:
        raise VisualQaSchemaInvalid("authority bundle requires layers")
    sources = [layer.get("source") for layer in layers]
    if sources != AUTHORITY_ORDER:
        raise VisualQaSchemaInvalid(
            "authority bundle layers must be ordered highest-authority first"
        )
    for rank, layer in enumerate(layers):
        if layer.get("authority_rank") != rank:
            raise VisualQaSchemaInvalid("authority bundle rank is inconsistent")
        if layer.get("overrides_higher_authority") is not False:
            raise VisualQaSchemaInvalid(
                "no authority layer may override higher authority"
            )
    return bundle
