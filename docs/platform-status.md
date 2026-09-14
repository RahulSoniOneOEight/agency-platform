# Agency Platform Status

## Merged baseline

- Step 1 — Control structure: merged.
- Step 2 — OpenCode control + policy layer: merged.
- Milestone A — Knowledge Platform: merged via PR #4.
- Workflow Runtime Layer: merged via PR #5.
- Milestone B — Prototype Platform: merged via PR #6.

## Current implemented platform

### Knowledge Platform

- Resource Registry + provenance/source routing
- normalization contracts
- Shared Design Contract schemas + seed commerce metadata
- business-model, 12 industry, and use-case presets
- Experience Pattern Library
- client-profile schema + regression fixtures
- preset resolver
- deterministic Design Contract index builder
- Experience Direction Engine v1

### Workflow Runtime

- stored stage workflows under `workflows/`
- client workspace initializer
- machine-readable `workflow-state.yaml`
- artifact-aware stage router
- runtime validation + CI contract
- approved-experience production gate

### Prototype Platform

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
- Flutter analyze/tests + Flutter Web CI build

## Client information architecture alignment

Being aligned to the canonical 20-stage flow through PR #7:

- `input/` separates supplied client facts/attachments from agent inference
- `derived/` stores client profile, resolved presets, intelligence map, capability map, gaps, and resource requirements
- existing eight runtime workflows map to the 20 detailed consulting/delivery stages
- `docs/operating-flow.md` is the detailed canonical operating model

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
- full production release automation for stages 19–20
