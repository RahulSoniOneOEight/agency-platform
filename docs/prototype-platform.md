# Prototype Platform

Milestone B turns validated Experience Directions into runnable Flutter prototypes without creating client-specific app forks.

## Core architecture

```text
client profile + A/B/(optional C) directions
→ tooling.prototype validation/composition
→ client prototype manifest + runtime directions + deterministic fixtures
→ apps/prototype_app
→ packages/agency_flutter_ui
→ screenshots + visual QA
→ client selection/mixing
→ approved-experience.yaml
```

## Direction contract boundary

Strategic directions are the canonical human/product-consulting source of truth. Runtime
directions are compact, execution-oriented projections generated deterministically from
strategic directions:

```text
canonical strategic direction YAML
→ canonical strategic schema validation
→ project_direction.py
→ generated runtime direction JSON
→ prototype manifest
→ Flutter runtime (B.1B consumer)
```

Rules:

- Strategic direction YAML is canonical; runtime JSON is generated and disposable.
- Exactly 2 or 3 directions are supported: A and B are mandatory, C is optional.
- Density uses one canonical vocabulary across the pipeline: `compact`, `normal`, `spacious`.
- Generated runtime direction JSON must never be hand-authored. The composer rebuilds it from
  strategic directions, and repository validation fails on manifest/runtime mismatch.

Strategic artifacts live at `client-projects/<client>/directions/direction-<id>.yaml` and are
validated against `tooling/knowledge/direction.schema.json`. Generated runtime artifacts live at
`client-projects/<client>/prototype/runtime/direction-<id>.json` and are validated against
`tooling/prototype/runtime_direction.schema.json`.

## Shared Flutter system

`packages/agency_flutter_ui/` contains:

- semantic tokens and Material 3 theme
- reusable primitives
- commerce/trade domain components
- pattern shells and canonical pattern registry

Reusable widgets must map to Design Contract concepts and must not contain client-specific branding/business logic.

## One prototype runtime

`apps/prototype_app/` is the only prototype application source tree. Directions configure it; they do not duplicate it.

Stable Flutter Web review URLs use:

```text
/?client=<client-id>&direction=a
/?client=<client-id>&direction=b
/?client=<client-id>&direction=c
```

The internal selector supports rapid comparison in the same running app.

The app loads `assets/generated/<client-id>.json` at startup, resolves the requested direction
from that bundle, and never silently falls back to Direction A. An explicit unknown client or
direction renders a governed error screen. Local startup without a `client` parameter uses the
checked-in regression client `prototype-demo`; omitting `direction` uses that client's
`default_direction`.

## Client prototype artifacts

`tooling.prototype.build_prototype.compose_prototype(...)` writes:

```text
client-projects/<client>/prototype/
├── prototype-manifest.yaml
├── runtime/
│   ├── direction-a.json
│   ├── direction-b.json
│   └── direction-c.json (optional)
├── fixtures/
│   └── demo.yaml
├── screenshots/
└── qa/
    └── screenshot-manifest.yaml
```

The manifest references `apps/prototype_app` and points each direction key at its generated
`runtime/direction-<id>.json`; it does not copy Flutter source.

`tooling.prototype.build_runtime_bundle.build_runtime_bundle(...)` then composes one
deterministic, self-contained client bundle at the Flutter asset boundary:

```text
apps/prototype_app/assets/generated/
└── <client-id>.json
```

The bundle carries directions, fixtures, theme seed, and canonical B.1C resource bindings.
It is regenerated from source by the composer and never hand-edited; repository validation
fails when a checked-in bundle is missing, invalid, or stale.

Initial deterministic fixture packs cover:

- electronics/appliances
- furniture/home
- grocery/FMCG
- services/booking

## Pattern registry

Canonical runtime pattern IDs come from `design-contract/patterns/` and are preserved
unchanged in generated bundles and runtime directions:

- commerce.home
- commerce.search
- commerce.plp
- commerce.pdp
- commerce.cart
- commerce.rfq
- commerce.reorder
- commerce.trade-dashboard

The Flutter app translates canonical IDs to internal `agency_flutter_ui` registry keys through
an explicit allowlisted adapter at
`apps/prototype_app/lib/registry/canonical_pattern_adapter.dart`. Heuristic prefix stripping is
forbidden, and two canonical IDs must not collide on one internal key. A valid canonical pattern
ID with no Flutter implementation fails visibly rather than silently creating ad-hoc UI.

## Widgetbook

`apps/widgetbook/` is the internal review surface for shared primitives, ProductCard variants, trade components, merchandising tiles, and reusable patterns.

Widgetbook is not the client runtime and is not copied into client projects.

## Visual QA

The prototype composer generates a screenshot manifest for:

- 360×800
- 390×844
- 430×932
- 768×1024
- 1440×900

Visual findings live at `prototype/qa/visual-findings.yaml`. Client review is blocked while unresolved critical findings exist.

## Approval contract

Client review produces `approved-experience.yaml` using either:

- one full selected direction; or
- a mixed contract with a base direction plus explicit `source_direction` per mixed section.

This file is the productionization input. Meeting notes or prototype screenshots are not substitutes.

## Scope boundary

Milestone B is local/demo prototype infrastructure. Production backend/ERP/auth/payment/shipping/CRM/WhatsApp/Supabase/n8n and release infrastructure remain later milestones.
