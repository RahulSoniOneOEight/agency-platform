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
