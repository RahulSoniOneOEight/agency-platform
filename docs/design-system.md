# Agency Design System

## Goal

Maintain one reusable agency design system rather than creating a separate design system for every client.

## Future layers

### Foundations
Colors, typography, spacing, radius, elevation, and motion.

### Primitives
Buttons, inputs, chips, cards, sheets, and other generic building blocks.

### Domain components
Reusable business-facing widgets such as product cards, category tiles, promo tiles, cart items, and order cards.

### Patterns
Composed experiences such as Home, PLP, PDP, Search, Cart, and Checkout.

### Variants
Controlled alternatives should represent legitimate UX differences. For example, one ProductCard may expose compact, standard, premium, or marketplace variants rather than four unrelated implementations.

### Themes
Client brand expression should primarily flow through tokens/themes: colors, fonts, imagery, radius/elevation personality, and selected UX variants.

## Client composition model

```text
Agency Design System
      +
Client Theme
      +
Selected UX Patterns
      =
Client App
```

The governing architecture targets a largely shared system, with client-specific work reserved for branding, selected variants, and unique workflows.

## Step 1 status

This document defines boundaries only. No production design tokens or Flutter widgets are implemented yet.
