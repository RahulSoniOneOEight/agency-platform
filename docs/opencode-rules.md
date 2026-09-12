# OpenCode Operating Rules

OpenCode acts as the main command center for reference lookup, design-system reuse, app composition, code changes, visual-fix loops, and optional Penpot/Flutter mapping.

## Before creating anything new

Follow this exact lookup order:

1. Existing client component?
2. Agency design-system component?
3. Existing variant or pattern?
4. Approved Penpot component or pattern?
5. Approved GitHub reference?
6. Approved `pub.dev` package?
7. Only then create something new.

## When using an external reference

1. Record or place it in the resource pool.
2. Check license, compatibility, dependencies, maintainability, visual usefulness, and duplication.
3. Normalize it into agency concepts.
4. Map design values to shared design-contract names.
5. Generalize component APIs.
6. Add reusable results to the shared agency layer rather than directly to a client app.

## Design implementation

- Prefer tokens to hard-coded values when a shared token exists.
- Prefer variants to duplicate components.
- Keep reusable behavior in `packages/agency_flutter_ui/` once implementation begins.
- Keep starter composition in `starters/`.
- Keep client-only behavior in `client-projects/`.
- Do not make Penpot mandatory for implementation.

## Visual quality

When visual QA is implemented, inspect rendered Flutter UI using Widgetbook/full app runs and screenshots. Check spacing, alignment, clipping, overflow, wrapping, hierarchy, card consistency, image ratios, typography, icon consistency, responsiveness, and design-system violations. Apply fixes in code, render again, and protect stable output with golden tests.

## Current phase

Step 1 is structure only. Do not implement production UI or integrations until a later step is explicitly started.
