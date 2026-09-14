# Milestone B.1A — Canonical Direction Contract + Runtime Projection

## Purpose

Close the first contract-integrity gap identified in the architecture review by establishing one canonical strategic direction artifact and one deterministic runtime projection consumed by prototype composition.

This milestone does **not** yet make Flutter load per-client generated assets. That is Milestone B.1B. B.1A creates the stable contract that B.1B will consume.

## Problem

The repository currently has overlapping, incompatible direction contracts:

- `templates/direction.yaml` is the workflow/consulting authoring shape.
- `tooling/prototype/direction_schema.json` is a different prototype-specific schema.
- `apps/prototype_app/lib/direction/prototype_direction.dart` models the prototype-specific shape.
- reference client direction files follow the prototype-specific shape rather than the workflow template.
- the workflow permits 2–3 selected directions while the router/composer assumes exactly A/B/C.

As a result, a direction produced according to the workflow template cannot reliably enter prototype composition without manual reshaping.

## Design decision

Use **two deliberately different contracts** with a deterministic adapter between them:

```text
Strategic Direction (canonical authoring artifact)
        ↓ validate
Direction Projection Adapter
        ↓ deterministic projection
Runtime Direction (prototype execution contract)
        ↓ validate
Prototype Manifest
```

The strategic direction remains rich enough for consulting, rationale, trade-offs, personas, journeys, success metrics, and client review. The runtime direction remains compact and implementation-oriented.

The two contracts must never be independently hand-maintained for the same client direction. Runtime directions are generated from strategic directions.

## Canonical strategic direction

### Location

- template: `templates/direction.yaml`
- schema: `tooling/knowledge/direction.schema.json`
- client artifacts: `client-projects/<client>/directions/direction-<id>.yaml`

### Required fields

The canonical strategic artifact contains:

- `id`
- `name`
- `archetype`
- `strategy_family`
- `thesis`
- `strategic_goal`
- `primary_personas`
- `primary_jobs`
- `rationale`
- `information_architecture`
- `navigation`
- `primary_journey`
- `secondary_journeys`
- `discovery_model`
- `search`
- `merchandising`
- `density`
- `transaction_model`
- `patterns`
- `components`
- `component_variants`
- `required_resources`
- `strengths`
- `tradeoffs`
- `risks`
- `success_metrics`
- `score`

### Canonical vocabulary

Use one density vocabulary across the direction pipeline:

- `compact`
- `normal`
- `spacious`

The runtime projection may map these to Flutter presentation values internally, but client-authored and strategic artifacts must not use a second density vocabulary.

`navigation` remains a structured object in the strategic artifact, with at least `model` and optional supporting fields.

`primary_journey` remains a structured/list representation suitable for consulting. Runtime projection derives the primary journey identifier/summary required for execution.

`tradeoffs` replaces `weaknesses` as the canonical decision field. Existing reference artifacts using `weaknesses` must be migrated.

## Runtime direction contract

### Location

- schema: `tooling/prototype/runtime_direction.schema.json`
- generated artifacts: `client-projects/<client>/prototype/runtime/direction-<id>.json`

### Required fields

Runtime direction contains only execution-relevant fields:

- `id`
- `name`
- `strategic_goal`
- `navigation_model`
- `primary_journey`
- `discovery_model`
- `merchandising_model`
- `density`
- `transaction_model`
- `patterns`
- `components`
- `component_variants`
- `required_resources`

No consulting rationale, scores, strengths, risks, or success metrics are duplicated into runtime configuration unless the runtime explicitly needs them later.

## Projection adapter

### Location

`tooling/prototype/project_direction.py`

### Responsibilities

The adapter must:

1. accept one validated canonical strategic direction;
2. reject missing/invalid required fields;
3. derive runtime scalar fields from structured strategic fields;
4. preserve canonical component and pattern IDs;
5. preserve density vocabulary unchanged;
6. emit deterministic output for identical input;
7. never infer missing strategic content silently;
8. fail loudly when a required runtime mapping cannot be derived.

### Example mappings

```text
strategic.navigation.model        → runtime.navigation_model
strategic.primary_journey         → runtime.primary_journey
strategic.merchandising.emphasis  → runtime.merchandising_model
strategic.patterns                → runtime.patterns
strategic.components              → runtime.components
```

If `primary_journey` is structured, the canonical schema must define the stable identifier used for projection rather than relying on free-text parsing.

## Direction cardinality

The platform supports **2 or 3 directions**.

Rules:

- direction A and B are mandatory;
- direction C is optional;
- `comparison.yaml` compares only directions that exist;
- prototype composition discovers available validated directions rather than assuming A/B/C;
- manifest `allowed_values` is generated from the actual direction set;
- screenshot manifests use the actual direction set;
- router/workflow readiness requires at least A and B, not necessarily C.

The platform must reject 1 direction and more than 3 directions in this milestone.

## Prototype composer integration

`tooling/prototype/build_prototype.py` must stop validating strategic files against the runtime schema.

Instead it must:

1. load available strategic directions (A/B plus optional C);
2. validate each against the canonical strategic schema;
3. project each through `project_direction.py`;
4. validate each generated runtime direction;
5. write runtime JSON under `prototype/runtime/`;
6. write manifest references to runtime direction JSON rather than strategic YAML;
7. derive `allowed_values` and screenshot jobs from the actual direction set.

Strategic YAML remains the client/consulting source of truth. Generated runtime JSON is disposable/rebuildable output.

## Validation

### New validation expectations

- schema validation for canonical strategic directions;
- schema validation for runtime directions;
- adapter determinism test;
- adapter rejects incomplete strategic direction;
- adapter preserves canonical pattern/component IDs;
- 2-direction client composes successfully;
- 3-direction client composes successfully;
- 1-direction client is rejected;
- manifest contains exactly the available direction IDs;
- screenshot manifest contains exactly the available direction IDs;
- reference example directions use the canonical strategic shape.

### Regression boundary

B.1A is complete when this flow is proven in tests:

```text
canonical strategic direction YAML
→ strategic schema validation
→ deterministic runtime projection
→ runtime schema validation
→ prototype manifest generation
```

Flutter loading of the generated runtime files is explicitly deferred to B.1B.

## Migration

Migrate the reference prototype client directions to the canonical strategic schema.

Existing runtime-specific direction schema usage is replaced by the new runtime schema. Any old prototype-specific validation entry point should either:

- become an alias/wrapper around runtime validation for compatibility, or
- be removed only after all callers are migrated in the same change.

No unrelated client, design-system, visual-QA, token, productionization, or documentation cleanup belongs in B.1A.

## Error handling

The pipeline must fail visibly for:

- invalid strategic direction schema;
- missing A or B;
- more than 3 directions;
- duplicate direction IDs;
- unknown or unprojectable structured values;
- invalid runtime projection;
- mismatch between manifest direction IDs and generated runtime files.

No unknown direction may silently fall back to A in tooling.

## Compatibility and boundaries

- Preserve repository-driven workflow semantics.
- Preserve one shared Flutter package and one prototype app.
- Do not copy Flutter source into client projects.
- Do not add production integrations.
- Do not solve Design Contract token alignment in this milestone.
- Do not implement screenshot capture in this milestone.

## Success criteria

Milestone B.1A succeeds when:

1. there is one canonical strategic direction schema used by workflow/client artifacts;
2. there is one runtime direction schema used by prototype execution artifacts;
3. runtime directions are generated, never hand-authored;
4. 2–3 direction cardinality is supported consistently;
5. the prototype manifest references generated runtime directions;
6. tests demonstrate the full strategic → projection → manifest contract path;
7. existing repository validation remains green.
