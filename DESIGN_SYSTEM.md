# Agency Design System Policy

## Purpose

This file defines the design-system rules agents must follow when changing shared UI, tokens, components, patterns, variants, or themes.

## Architecture

```text
foundations
→ primitives
→ domain components
→ patterns
→ variants
→ themes
```

## Foundations

The shared foundation covers:

- color
- typography
- spacing
- radius
- elevation
- motion
- icon rules
- imagery rules

## Primitives

Typical primitives include:

- buttons
- inputs
- chips
- cards
- sheets
- navigation primitives

## Domain components

Examples include:

- `ProductCard`
- `CategoryTile`
- `PromoTile`
- `CartItem`
- `OrderCard`

## Patterns

Examples include:

- Home
- PLP
- PDP
- Search
- Cart
- Checkout

## Mandatory rules

1. Search for an existing implementation before creating anything new.
2. Use design-contract tokens instead of hard-coded visual values when tokens exist.
3. Prefer extending an existing shared component over creating a second implementation.
4. Prefer a controlled variant over duplicating a component.
5. Keep reusable APIs generalized and source-agnostic.
6. Keep client branding primarily in themes and token overrides.
7. Create client-specific widgets only for genuinely client-specific workflows.
8. Keep component, pattern, and variant naming aligned with `design-contract/`.

## Mandatory lookup order

Before creating a new reusable component, pattern, screen-level building block, or package-level implementation, check:

1. current client application
2. `packages/agency_flutter_ui/`
3. existing design-contract patterns and variants
4. approved Penpot references
5. approved GitHub references
6. approved `pub.dev` packages
7. only then create something new

## Normalization rule

External implementation or visual reference:

```text
useful structure / UX idea
→ remove source-specific styling
→ remove unnecessary dependencies
→ map to agency tokens
→ generalize API
→ choose reuse / extension / variant / new component
→ agency design system
```

Never allow an external component to bypass this normalization path into a client app.

## Variants, not duplicates

A visual or behavioral difference should normally become a documented variant when the underlying component purpose remains the same. A new component is justified only when its responsibility, interaction model, or data contract is materially different.

## Relationship to AGENTS.md

`AGENTS.md` is the master control file. Agents must read this policy before shared design-system or Flutter UI work.
