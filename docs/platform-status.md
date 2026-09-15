# Agency Platform Status

## Merged baseline

- Step 1 — Control structure: merged.
- Step 2 — OpenCode control + policy layer: merged.
- Milestone A — Knowledge Platform: merged via PR #4.
- Workflow Runtime Layer: merged via PR #5.

## Milestone B — Prototype Platform

Implemented on `milestone-b-prototype-platform` / PR #6 pending review/merge:

- shared `packages/agency_flutter_ui` Flutter design-system implementation
- semantic tokens + Material 3 theme
- reusable primitives and commerce/trade components
- canonical Flutter pattern registry and responsive pattern shells
- one configurable `apps/prototype_app` runtime for A/B/C
- query-parameter and internal direction switching
- deterministic fixture generation for four initial industry packs
- direction validation + direction-to-prototype composer
- client prototype manifest/fixture/screenshot-manifest artifacts
- `apps/widgetbook` review surface
- standard screenshot viewport contract + capture-job planning
- structured visual-QA findings and critical-issue gate
- approved-experience validation for selected or mixed directions
- Workflow Runtime activation through build-prototype → visual-qa → client-review
- Prototype Platform validation and Flutter Web CI build

### Milestone B.1 — Runtime integrity, resource intelligence, client runtime loading

- B.1A — canonical direction contract: merged via PR #10.
- B.1A1 — client input contract: merged via PR #11.
- B.1C — resource selection and canonical bindings: merged via PR #12.
- B.1B — client runtime loading: implemented on `milestone-b1b-client-runtime-loading`
  (PR pending review/merge):
  - one shared `apps/prototype_app` runtime that loads generated client bundles
  - `tooling/prototype/build_runtime_bundle.py` composes one deterministic bundle per client
  - generated asset boundary at `apps/prototype_app/assets/generated/<client-id>.json`
  - `?client=<client-id>&direction=<direction-id>` with no silent fallback
  - canonical B.1A direction vocabulary plus an app-layer canonical pattern adapter
  - runtime fixtures, theme seed, and B.1C canonical resource bindings loaded from the bundle
  - direction selector reflects only the client's declared directions
  - governed, visible runtime errors with stable codes
  - deterministic generation plus repository validation of bundle freshness
  - approved canonical Cart, Reorder, and Trade Dashboard Design Contract pattern entries

## Still deferred to later milestones

- production backend/ERP integrations
- production authentication and authorization
- payment and shipping integrations
- CRM/WhatsApp integrations
- Supabase/Postgres operational runtime
- n8n production workflows
- production analytics/observability implementation
- deployment/app-store release pipelines
- automated browser screenshot execution in CI where no UI runner is available
