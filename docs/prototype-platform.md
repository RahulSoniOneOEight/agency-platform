# Prototype Platform

Milestone B turns validated Experience Directions into runnable Flutter prototypes without creating client-specific app forks.

## Core architecture

```text
derived/client-profile.yaml + A/B/C directions
→ tooling.prototype validation/composition
→ client prototype manifest + deterministic fixtures
→ apps/prototype_app
→ packages/agency_flutter_ui
→ screenshots + visual QA
→ client selection/mixing
→ approved-experience.yaml
```

The client information architecture is defined in `docs/operating-flow.md`. Prototype tooling reads the canonical derived profile; legacy root-level profiles are migration-only read fallback.

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

The internal A/B/C selector supports rapid comparison in the same running app.

## Client prototype artifacts

`tooling.prototype.build_prototype.compose_prototype(...)` reads `derived/client-profile.yaml` and writes:

```text
client-projects/<client>/prototype/
├── prototype-manifest.yaml
├── fixtures/
│   └── demo.yaml
├── screenshots/
└── qa/
    └── screenshot-manifest.yaml
```

The manifest references `apps/prototype_app`; it does not copy Flutter source.

Initial deterministic fixture packs cover:

- electronics/appliances
- furniture/home
- grocery/FMCG
- services/booking

## Pattern registry

Initial canonical runtime patterns:

- home
- search
- plp
- pdp
- cart
- checkout
- quick-order
- rfq
- trade-dashboard
- reorder
- booking

Unknown pattern IDs fail rather than silently creating ad-hoc UI.

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