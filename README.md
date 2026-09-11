# Agency Platform

`agency-platform` is the shared workspace for an OpenCode-centric Flutter app delivery system. It is intentionally a platform skeleton at this stage: the repository defines boundaries, governance, and validation before reusable Flutter components or client applications are implemented.

## Operating model

```text
Client Brief
  → Product / UX Contract
  → Reference Resource Pool
  → Curation + Normalization
  → Shared Design Contract
  → Flutter UI Kit / optional Penpot library / App Starters
  → Client App
  → Visual QA
  → Client Review
  → Productionization
  → GitHub / CI / Release
```

OpenCode is the primary engineering/orchestration environment. GitHub is the production source of truth. Flutter will be the production implementation. Penpot is optional and exists for visual reference, selected prototypes, representative screens, and client-facing design work.

## Repository map

- `resources/` — incoming, approved, rejected, and categorized external references/assets.
- `design-contract/` — shared tokens, component specifications, patterns, variants, and themes.
- `packages/agency_flutter_ui/` — future reusable production Flutter package.
- `starters/` — future reusable application shells by product type.
- `penpot/` — optional design-system and starter design references.
- `client-projects/` — client-specific applications; external references must never enter here directly.
- `tooling/` — future normalization, generation, screenshot, golden-test, visual-review, and validation utilities.
- `docs/` — architecture, operating rules, and delivery documentation.

## Core rules

1. Reuse before creating.
2. External references are curated and normalized before adoption.
3. The shared design contract aligns references, Penpot, and Flutter.
4. Prefer controlled variants over duplicate widgets.
5. Flutter is authoritative for production behavior and implementation.
6. Penpot and Nowa-like tools are optional visual layers, not production sources of truth.
7. Rendered UI will later be reviewed through Flutter/Widgetbook screenshots, AI vision, and golden tests.

See `AGENTS.md` for agent rules and `docs/source/agency_flutter_opencode_delivery_system_v2.txt` for the governing architecture source.

## Step 1 scope

This repository currently contains structure and governance only. It does **not** yet contain production Flutter UI components, implemented starters, backend integrations, Penpot automation, or client application code.

## Validation

From the repository root:

```bash
python tooling/validation/validate_repo.py
python -m unittest tooling.validation.test_validate_repo -v
```
