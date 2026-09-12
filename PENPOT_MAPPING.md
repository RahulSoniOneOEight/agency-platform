# Penpot Mapping Policy

## Purpose

Penpot is an optional visual/reference and client-review layer. Flutter remains the production implementation.

## Mapping model

```text
Penpot component or pattern
→ design-contract component / pattern / variant
→ Flutter implementation
```

Example:

```text
Penpot:
Product Card / Marketplace

Design contract:
ProductCard
variant: marketplace

Flutter:
PIProductCard(
  variant: PIProductCardVariant.marketplace,
)
```

## Mandatory rules

1. Do not treat raw Penpot structure as production Flutter architecture.
2. Search `packages/agency_flutter_ui/` before creating a new Flutter widget for a Penpot element.
3. Prefer extending an existing shared component or adding a variant.
4. Map Penpot colors, typography, spacing, radius, elevation, icons, and motion to agency design-contract tokens and rules.
5. Keep component, pattern, and variant names aligned with `design-contract/`.
6. A new Penpot component does not automatically justify a new Flutter component.
7. Maintain important components, representative screens, variants, and key flows in Penpot; do not attempt to mirror every production screen.
8. Do not depend on perfect Flutter ↔ Penpot round-tripping.

## Penpot → Flutter

When implementing an approved Penpot reference:

- identify the matching design-contract component or pattern
- search for an existing Flutter implementation
- reuse or extend the shared Flutter component where possible
- normalize any new design decisions before implementation
- create a new reusable component only when existing abstractions are insufficient

## Flutter → Penpot

Do not automatically reconstruct the whole Flutter application in Penpot. Update representative components, key screens, flows, and meaningful variants using shared naming and screenshots where useful.

## Relationship to AGENTS.md

`AGENTS.md` is the master control file. Agents doing Penpot-related work must read and follow this policy before implementation.
