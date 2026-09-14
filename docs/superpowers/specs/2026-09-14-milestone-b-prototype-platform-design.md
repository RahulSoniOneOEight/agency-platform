# Milestone B — Prototype Platform Design Specification

## Goal

Add the executable prototype layer that turns validated Experience Directions into runnable Flutter prototypes, supports A/B/C comparison from one shared codebase, performs structural and visual QA, and enables client selection/mixing into `approved-experience.yaml`.

## Context

The repository already contains:

- OpenCode operating rules and policy routing;
- Milestone A Knowledge Platform;
- Design Intelligence, Resource Intelligence, presets, experience patterns, and Direction Engine v1;
- repository-driven Workflow Runtime with stages from intake through productionization;
- an explicit `prototype-platform-not-installed` block at `build-prototype`.

Milestone B removes that block by adding the first real Flutter runtime implementation layer.

GitHub remains the source of truth. OpenCode remains the orchestrator. Flutter becomes the executable prototype and future production UI foundation.

## Core Design Principle

Milestone B uses **one shared Flutter system and one configurable prototype application**.

It must not create three independent client apps for A/B/C.

The model is:

```text
Experience Direction YAML
        ↓
Direction Parser + Validator
        ↓
Prototype Config
        ↓
Shared Flutter Design System
        ↓
Shared Pattern Registry
        ↓
Single Prototype App
        ↓
Direction A / B / C runtime selection
```

A/B/C must differ through product strategy and composition — navigation, primary journey, search/discovery model, merchandising, density, transaction model, or interaction model — not by duplicating the application or changing theme alone.

## Scope

Included:

1. Shared Flutter design-system package.
2. Reusable commerce/domain components.
3. Reusable screen/pattern shells.
4. One prototype starter application.
5. Direction config parser and registry-based composer.
6. Runtime A/B/C selector and URL/query selection for Flutter Web.
7. Deterministic demo/fixture data.
8. Initial industry-aware fixture packs.
9. Widgetbook component/variant review surface.
10. Flutter tests and high-value golden tests.
11. Screenshot capture tooling at standard viewports.
12. Structured visual-QA finding contract.
13. Workflow Runtime integration for `build-prototype`, `visual-qa`, and `client-review`.
14. Client selection/mixing into validated `approved-experience.yaml`.

Excluded:

- production ERP/backend integration;
- production authentication;
- payment gateway integration;
- shipping/CRM/WhatsApp integrations;
- Supabase/Postgres runtime;
- n8n workflows;
- app-store/release automation;
- production analytics implementation;
- production infrastructure/deployment beyond a buildable Flutter Web prototype artifact.

## Repository Structure

```text
agency-platform/
├── packages/
│   └── agency_flutter_ui/
│       ├── pubspec.yaml
│       ├── lib/
│       │   ├── agency_flutter_ui.dart
│       │   ├── foundation/
│       │   │   ├── color_tokens.dart
│       │   │   ├── spacing_tokens.dart
│       │   │   ├── typography_tokens.dart
│       │   │   ├── radius_tokens.dart
│       │   │   └── motion_tokens.dart
│       │   ├── primitives/
│       │   ├── domain/
│       │   ├── patterns/
│       │   └── themes/
│       └── test/
│
├── apps/
│   └── prototype_app/
│       ├── pubspec.yaml
│       ├── lib/
│       │   ├── main.dart
│       │   ├── prototype_app.dart
│       │   ├── direction/
│       │   ├── registry/
│       │   ├── fixtures/
│       │   └── screens/
│       ├── test/
│       └── web/
│
├── apps/
│   └── widgetbook/
│       ├── pubspec.yaml
│       └── lib/
│
├── tooling/
│   └── prototype/
│       ├── direction_schema.json
│       ├── validate_direction.py
│       ├── build_prototype.py
│       ├── fixture_generator.py
│       ├── screenshot_manifest.py
│       └── validate_visual_qa.py
│
├── templates/
│   ├── prototype-manifest.yaml
│   ├── visual-qa-findings.yaml
│   └── approved-experience.yaml
│
└── client-projects/<client>/
    ├── directions/
    ├── prototype/
    │   ├── prototype-manifest.yaml
    │   ├── fixtures/
    │   ├── screenshots/
    │   └── qa/
    └── approved-experience.yaml
```

The exact Flutter-generated platform folders may vary, but the architectural boundaries above are mandatory.

## 1. Shared Flutter Design System

Package: `packages/agency_flutter_ui/`

This package is the implementation counterpart to `design-contract/`.

### Foundations

Implement semantic foundations first:

- color roles;
- typography roles;
- spacing scale;
- radius scale;
- elevation where required;
- motion durations/curves.

Do not hard-code client brand values directly inside reusable widgets. Client appearance is applied through theme/config layers.

### Primitives

Initial primitives:

- primary/secondary/text button;
- icon button;
- text field;
- search field shell;
- chips/filter chips;
- badges;
- card/surface;
- bottom sheet/dialog shell;
- section header;
- quantity control.

### Domain Components

Initial commerce components:

- ProductCard;
- ProductImage;
- PriceDisplay;
- RatingStars;
- CategoryTile;
- PromoTile;
- CollectionHeader;
- CartItem;
- OrderCard;
- QuoteCard;
- CreditSummary;
- RFQLineItem;
- DeliveryOption;
- MerchandisingSplitTile.

Widget names and supported variants must map back to Design Contract IDs.

### Patterns

Initial reusable pattern shells:

- Home;
- Search;
- PLP;
- PDP;
- Cart;
- Checkout;
- Quick Order;
- RFQ;
- Trade Dashboard;
- Reorder;
- Booking/Service landing shell.

Patterns may compose domain components, but must not contain client branding or client-specific business logic.

## 2. Prototype Application

Application: `apps/prototype_app/`

This app is a client-review runtime, not a production backend-connected app.

Responsibilities:

- load a prototype manifest;
- load direction A/B/C configuration;
- select a direction by query parameter, route, or internal selector;
- apply client theme;
- resolve pattern/component IDs through registries;
- load deterministic fixtures;
- render navigable flows;
- provide stable routes for screenshot capture.

### Direction selection

Flutter Web must support a stable selection interface such as:

```text
/?client=acme&direction=a
/?client=acme&direction=b
/?client=acme&direction=c
```

An internal direction switcher may also be shown in prototype/debug builds.

The direction selector must not create separate application source trees.

## 3. Direction-to-Prototype Composer

Milestone B introduces a strict translation layer from direction config to Flutter runtime configuration.

### Inputs

- `client-profile.yaml`;
- `resolved-intelligence.yaml`;
- `directions/direction-a.yaml`;
- `directions/direction-b.yaml`;
- `directions/direction-c.yaml`;
- `directions/comparison.yaml`;
- design-contract indexes;
- available Flutter implementation registry;
- selected Resource Intelligence entries;
- client theme/brand configuration if present.

### Output

`client-projects/<client>/prototype/prototype-manifest.yaml`

The manifest must include:

- client ID;
- available direction IDs;
- route/navigation model;
- home pattern;
- search strategy;
- PLP pattern/variant;
- PDP pattern/variant;
- merchandising strategy;
- transaction model;
- density;
- theme reference;
- fixture-pack reference;
- component/pattern implementation mappings;
- resource references.

### Registry model

Flutter code must expose explicit registries for:

- components;
- patterns;
- themes;
- navigation models;
- transaction models.

A direction file may only reference supported registry IDs.

Unknown IDs fail validation. They must never silently fall back to a generic widget because that would hide gaps in the shared system.

## 4. Demo Data Runtime

Milestone B uses deterministic fixtures rather than live production services.

Initial domains:

- products;
- categories;
- collections;
- banners/promotions;
- customers;
- orders;
- cart;
- quotes;
- RFQs;
- trade credit;
- delivery options;
- service/booking availability.

### Seed packs

Add initial deterministic packs for:

1. B2B electronics;
2. D2C furniture/home;
3. grocery/FMCG;
4. services/booking.

Each pack uses stable IDs and predictable data so screenshots and tests are reproducible.

Fixture generation may vary content by seed, but test/CI defaults must use a fixed seed.

## 5. Widgetbook

Widgetbook is the internal review surface for shared Flutter UI.

It must expose, at minimum:

- major primitives;
- domain components;
- supported variants;
- states;
- density choices;
- mobile widths;
- light theme/client-theme examples where relevant.

Widgetbook is not the client-review prototype. The prototype app remains the client-facing experience surface.

## 6. Visual QA

Milestone B converts `VISUAL_QA.md` from policy into an executable review loop.

### Standard viewports

At minimum:

- 360 × 800;
- 390 × 844;
- 430 × 932;
- representative tablet viewport;
- representative desktop/web viewport.

### Screenshot manifest

For each client/direction, record:

- route/screen;
- direction;
- viewport;
- output path;
- capture status.

### QA finding contract

Each finding contains:

- ID;
- client;
- direction;
- screen/route;
- viewport;
- severity;
- category;
- component/pattern;
- evidence/screenshot path;
- finding description;
- recommended correction;
- status.

Categories include:

- layout;
- overflow;
- spacing;
- typography;
- image/resource fit;
- hierarchy;
- consistency;
- navigation;
- state/interaction;
- accessibility;
- responsiveness.

### AI vision

Milestone B must prepare screenshot artifacts and structured finding contracts so AI vision can review them.

The repository implementation does not need to hard-code a specific external vision provider. OpenCode/ChatGPT vision may consume the screenshot set and write findings back to the structured QA file.

This keeps visual QA provider-independent.

## 7. Golden and Widget Testing

Use golden tests selectively for stable, high-value shared components and patterns.

Do not golden-test every screen or every client prototype.

Recommended initial golden coverage:

- ProductCard core variants;
- CategoryTile;
- Promo/Merchandising tile;
- PriceDisplay;
- QuoteCard;
- CreditSummary;
- one representative Home composition;
- one representative PLP composition.

Normal widget tests cover behavior and registry resolution.

## 8. Workflow Runtime Integration

### `build-prototype`

Milestone B changes this stage from blocked to executable.

The stage succeeds only when:

- A/B/C directions validate;
- all referenced component/pattern IDs resolve;
- prototype manifest is generated;
- fixture data exists;
- Flutter prototype app builds.

Output state advances to `visual-qa`.

### `visual-qa`

The stage succeeds only when:

- required screenshot manifest exists;
- required viewports/routes are represented;
- structured QA findings file exists;
- blocking QA findings are resolved or explicitly accepted.

Output state advances to `client-review`.

### `client-review`

The stage supports:

- select Direction A/B/C;
- mix named sections/patterns from multiple directions;
- reject/refine selected areas.

The result is written into validated `approved-experience.yaml`.

### `approved-experience.yaml`

The contract records at minimum:

- selected source direction for major experience areas;
- navigation model;
- home pattern;
- search model;
- PLP/PDP variants;
- transaction model;
- theme;
- density;
- component overrides;
- resource references;
- primary/secondary journeys;
- explicit client-specific exceptions;
- approval status.

All references must resolve before the Workflow Runtime can advance to `productionize`.

## 9. Client Theme Model

Client theme is an input layer over the agency design system, not a fork.

A client theme may configure:

- semantic colors;
- typography family/scale within supported constraints;
- radius style;
- imagery direction;
- surface treatment;
- density preference.

It may not redefine widget behavior or duplicate components merely for branding.

## 10. Resource Handling

Prototype resources follow Resource Intelligence rules.

Priority:

1. client-owned resources;
2. agency-approved local resources;
3. approved external providers;
4. demo/generated fallback when explicitly permitted.

The prototype manifest references selected assets/resources through stable metadata. Provenance must remain available from the Resource Intelligence layer.

## 11. Validation

Milestone B adds validators that check:

- Flutter implementation registry IDs match design-contract IDs where mapped;
- direction configs reference known registry IDs;
- prototype manifest is complete;
- required fixtures exist;
- screenshot manifest is structurally valid;
- visual-QA findings use valid statuses/severities;
- approved-experience references valid components/patterns/resources;
- Workflow Runtime no longer reports `prototype-platform-not-installed` once prototype package/app markers are installed.

## 12. CI

Extend CI with a distinct Prototype Platform lane.

Required checks:

```text
Repository Validation
Knowledge Platform Validation
Workflow Runtime Validation
Prototype Contract Validation
Flutter analyze — shared package
Flutter test — shared package
Flutter analyze — prototype app
Flutter test — prototype app
Flutter Web build — prototype app
Widgetbook analyze/test
selected golden tests
```

Screenshot automation may run in CI if stable in the runner environment; otherwise CI validates screenshot tooling/manifests while actual capture remains an explicit local/OpenCode workflow step.

## 13. Error Handling / Failure Behavior

The platform must fail loudly and structurally when:

- a direction references an unimplemented component/pattern;
- fixture pack is missing;
- prototype manifest is invalid;
- theme reference is unknown;
- screenshot coverage is incomplete;
- client review references a nonexistent direction/component/pattern;
- blocking QA findings remain unresolved.

Do not silently substitute implementation defaults when a direction explicitly requested something unavailable.

## 14. Initial Deliverable Boundary

Milestone B is considered complete when the repository can demonstrate one end-to-end fixture client through:

```text
validated client profile
→ validated A/B/C directions
→ generated prototype manifest
→ runnable Flutter Web prototype
→ A/B/C direction switching
→ deterministic demo fixtures
→ Widgetbook component review
→ screenshot manifest / visual QA findings
→ client selection/mixing
→ validated approved-experience.yaml
```

The demonstration should use one existing Knowledge Platform regression profile, preferably B2B electronics, because it exercises Search/SKU, RFQ/trade, repeat-order, and credit concepts.

The same system must also validate fixture-pack compatibility for furniture, grocery, and services without requiring separate Flutter apps.

## 15. Recommended Implementation Sequence

1. Flutter workspace/package/app skeleton and CI lane.
2. Foundations + primitives.
3. Domain components + implementation registry.
4. Core pattern shells.
5. Direction schema/parser/composer.
6. Deterministic fixture runtime.
7. Prototype app and A/B/C switching.
8. Widgetbook.
9. Screenshot manifest + visual-QA tooling.
10. Workflow Runtime activation.
11. Client selection/mixing + approved-experience validation.
12. End-to-end B2B electronics demonstration.

## Success Criteria

Milestone B succeeds when OpenCode can take a client whose Workflow Runtime is at `build-prototype` and, without inventing a separate app architecture:

1. generate a valid prototype manifest from A/B/C directions;
2. validate all requested UI/pattern IDs;
3. produce deterministic fixtures;
4. build one Flutter prototype app;
5. render any of the three directions from the same codebase;
6. provide stable Flutter Web URLs/routes for client review;
7. expose reusable components/variants in Widgetbook;
8. capture/review required visual states;
9. record client selection/mixing;
10. produce a valid `approved-experience.yaml`;
11. advance the Workflow Runtime to `productionize`.

## Key Principle

```text
Knowledge Platform = what the experience should be
Workflow Runtime = what stage should run
Prototype Platform = executable proof of the experience
Flutter shared package = reusable UI implementation
Prototype manifest = bridge from direction to runtime
Widgetbook = internal component review
Visual QA = rendered quality gate
approved-experience.yaml = client-approved production contract
```
