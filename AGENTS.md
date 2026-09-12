# Agent Operating Rules

## Governing architecture

Primary architecture source:

`docs/source/agency_flutter_opencode_delivery_system_v2.txt`

Read it before architectural or structural changes. This file defines implementation behavior for agents working in this repository; it must not contradict the governing architecture source.

## Mandatory lookup order

Before creating any new UI component, pattern, or package-level implementation, check in this order:

1. Existing client component.
2. Agency Flutter UI component.
3. Existing variant or pattern.
4. Approved Penpot component or pattern.
5. Approved GitHub reference.
6. Approved `pub.dev` package.
7. Only then create something new.

## Reference and normalization rules

- Never copy external UI code or components directly into `client-projects/`.
- New external material enters through `resources/incoming/`.
- Evaluate licensing, Flutter compatibility, dependency quality, maintainability, visual usefulness, and duplication before approval.
- Adopted references must pass through normalization before entering the agency design system.
- Remove unnecessary source-specific styling and dependencies.
- Map color, spacing, typography, radius, icon, imagery, and motion decisions to agency design-contract concepts.
- Prefer reusable, generalized component APIs over source-specific APIs.

## Design-system rules

- Use shared tokens instead of hard-coded design values when tokens exist.
- Prefer variants over duplicated widgets.
- Keep client-specific changes focused on brand/theme, selected UX variants, and genuinely unique workflows.
- The shared design contract aligns token names, component names, variants, patterns, and interaction rules.

## Source-of-truth rules

- GitHub is the production source of truth.
- Flutter is authoritative for production implementation.
- Penpot is optional for visual reference, selected prototypes, representative screens, and client review.
- Do not depend on perfect Penpot ↔ Flutter round-tripping.

## Step 1 guardrail

Until Step 2 is explicitly approved, do not add production Flutter components, starter implementations, backend services, Supabase, n8n, deployment pipelines, or Penpot automation.
