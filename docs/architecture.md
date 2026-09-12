# Architecture

## Purpose

The platform supports rapid, reusable Flutter app delivery without allowing external references or client-specific work to fragment the agency design system.

## Delivery pipeline

```text
Client Brief
    ↓
Product / UX Contract
    ↓
Reference Resource Pool
GitHub • pub.dev • Penpot • icons • images • animations • UX examples
    ↓
Curation + Normalization
    ↓
Shared Design Contract
(tokens • components • patterns • variants)
    ↓
┌────────────────┬──────────────────┬─────────────────┐
│ Penpot Library │ Flutter UI Kit   │ App Starters    │
│ visual ref.    │ production code  │ reusable shells │
└────────────────┴────────┬─────────┴─────────────────┘
                         ↓
                     Client App
                         ↓
                     Visual QA
                         ↓
                   Client Review
                         ↓
                  Productionization
                         ↓
                 GitHub → CI → Release
```

## Architectural boundaries

### Reference resource pool
External sources provide breadth. They are not production dependencies by default and must not flow directly into client apps.

### Curation and normalization
Normalization preserves useful structure or UX ideas while removing source-specific styling/dependencies and mapping decisions into one agency design language.

### Shared design contract
The contract is the bridge among external references, optional Penpot representations, and Flutter production implementation. It will define shared token names, component names, variants, patterns, and interaction rules.

### Flutter UI kit
The reusable Flutter package will become the production implementation of the agency design system.

### App starters
Starters will assemble reusable patterns into product-specific shells such as ecommerce, marketplace, B2B commerce, grocery, booking, and customer portal.

### Client projects
Client applications should be compositions of shared UI, a starter, a client theme, selected UX variants, and unique client workflows.

### Visual QA
A later phase will use rendered Flutter/Widgetbook output, screenshots, AI vision, and golden tests. Quality must be judged from rendered UI, not inferred only from Dart code.
