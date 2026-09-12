# Agency Platform — Agent Operating Contract

These instructions are mandatory for all agent work in this repository.

## Governing architecture

Primary architecture source:

`docs/source/agency_flutter_opencode_delivery_system_v2.txt`

Read it before architectural or structural changes. This operating contract must not contradict the governing architecture source.

## Source of truth

- GitHub is the production source of truth.
- Flutter is authoritative for production implementation.
- OpenCode is the primary engineering/orchestration layer.
- Penpot is optional for visual reference, selected prototypes, representative screens, and client review.
- Do not depend on perfect Penpot ↔ Flutter round-tripping.

## Mandatory policy routing

Before reference discovery, evaluation, adoption, or normalization, read:

`REFERENCE_POLICY.md`

Before shared UI, tokens, components, patterns, variants, or themes, read:

`DESIGN_SYSTEM.md`

Before completing meaningful UI work, read:

`VISUAL_QA.md`

Before Penpot-related work, read:

`PENPOT_MAPPING.md`

Only load policies relevant to the current task, but never skip a relevant policy.

## Mandatory lookup order

Before creating any new reusable UI component, pattern, screen-level building block, or package-level implementation, check in this order:

1. Current client application.
2. `packages/agency_flutter_ui/`.
3. Existing design-contract patterns and variants.
4. Approved Penpot components or patterns.
5. Approved GitHub references.
6. Approved `pub.dev` packages.
7. Only then create something new.

## Mandatory pre-implementation lookup report

Before creating a new reusable component or pattern, report:

```text
Client app:
Agency Flutter UI:
Patterns / variants:
Approved Penpot:
Approved GitHub:
Approved pub.dev:

Decision:
- reuse
- extend
- add variant
- normalize external reference
- create new
```

Do not implement a new reusable component or pattern until this lookup is complete and the decision is stated.

## Reference and normalization rules

- Never copy external UI code or components directly into `client-projects/`.
- New external material enters through `resources/incoming/`.
- Evaluate licensing, Flutter compatibility, dependency quality, maintainability, visual usefulness, accessibility implications, and duplication before approval.
- Adopted references must pass through normalization before entering the agency design system.
- Approval does not mean production-ready.
- Remove unnecessary source-specific styling and dependencies.
- Map color, spacing, typography, radius, elevation, icon, imagery, and motion decisions to agency design-contract concepts.
- Prefer reusable, generalized component APIs over source-specific APIs.

Required flow:

```text
external source
→ resources/incoming/
→ review
→ resources/approved/ OR resources/rejected/
→ normalization
→ design contract / agency_flutter_ui
→ client usage
```

## Design-system rules

- Use shared tokens instead of hard-coded design values when tokens exist.
- Prefer reuse over creation.
- Prefer extending an existing component over adding a duplicate.
- Prefer variants over duplicated widgets.
- Keep client-specific changes focused on brand/theme, selected UX variants, and genuinely unique workflows.
- Keep component, pattern, and variant naming aligned with `design-contract/`.
- The shared design contract aligns token names, component names, variants, patterns, and interaction rules.

## Visual completion rule

Meaningful UI work is not complete based on Dart analysis or unit tests alone. Follow `VISUAL_QA.md`: render the UI, inspect the result, correct issues, and add golden regression coverage where appropriate.

## Scope guardrail

Step 2 establishes the OpenCode control layer only. Do not add production Flutter components, starter implementations, backend services, Supabase, n8n, deployment pipelines, Penpot automation, or screenshot/vision automation unless a later step explicitly authorizes that work.
