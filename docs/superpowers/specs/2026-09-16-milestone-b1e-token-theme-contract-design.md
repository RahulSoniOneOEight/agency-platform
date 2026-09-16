# Milestone B.1E — Token + Theme Contract

## Purpose

Introduce a governed visual design layer that resolves agency foundation tokens, semantic tokens, reusable theme presets, client brand overrides, and direction-specific overrides into a deterministic resolved theme consumed by Flutter. B.1E builds on B.1D's canonical Design Contract ↔ Flutter binding layer and B.1B's client runtime bundle.

## Current State

- `design-contract/tokens/` and `design-contract/themes/` exist but contain no governed token/theme records.
- `AgencyTheme.light()` is still primarily seed-color driven and includes a small number of hard-coded Material theme values.
- B.1B runtime bundles already provide the correct client-specific runtime boundary.
- B.1D now governs canonical pattern/component IDs, variants, density, and Flutter implementation bindings.

B.1E should complete the visual contract without introducing another source of truth.

## Design Principles

1. `design-contract/` remains the canonical visual contract authority.
2. Flutter consumes resolved semantic values; it does not independently infer brand/theme decisions.
3. Foundation tokens define reusable scales; semantic tokens define meaning.
4. Theme presets express reusable visual character, not client identity.
5. Client brand inputs override approved semantic paths only.
6. Direction-specific differences are controlled overrides, not independent design systems.
7. Resolved themes are deterministic build artifacts and must be freshness-checked in CI.
8. Major active prototype styling should consume semantic tokens rather than ad-hoc hard-coded values.
9. Nowa may refine Flutter visually, but persistent reusable changes must be reconciled back into governed tokens/components/configuration.

## Architecture

```text
Agency Foundation Tokens
        ↓
Semantic Token Defaults
        ↓
Theme / Visual Preset
        ↓
Client Brand Overrides
        ↓
Direction Overrides
        ↓
Theme Compiler + Validation
        ↓
Resolved Theme
        ↓
Client Runtime Bundle
        ↓
Flutter ThemeData
        +
AgencyThemeTokens ThemeExtension
```

## Canonical Token Layers

### Foundation Tokens

Foundation tokens are reusable raw scales and primitives. They are implementation-neutral and should not be consumed directly by most widgets.

Initial B.1E groups:

- `color`
- `typography`
- `spacing`
- `radius`
- `elevation`
- `size`
- `density`
- `motion`
- `breakpoints`

Example:

```yaml
version: 1
color:
  neutral:
    0: "#FFFFFF"
    50: "#F7F8FA"
    900: "#16181D"
  blue:
    600: "#2454FF"
spacing:
  1: 4
  2: 8
  3: 12
  4: 16
  6: 24
  8: 32
radius:
  sm: 6
  md: 12
  lg: 20
motion:
  fast_ms: 150
  normal_ms: 250
```

### Semantic Tokens

Semantic tokens express design meaning and are the normal consumption boundary for Flutter widgets.

Initial semantic shape:

```yaml
version: 1
color:
  primary: "{foundation.color.blue.600}"
  on_primary: "{foundation.color.neutral.0}"
  surface: "{foundation.color.neutral.0}"
  surface_muted: "{foundation.color.neutral.50}"
  text_primary: "{foundation.color.neutral.900}"
  text_secondary: "#626874"
  border: "#E4E6EB"
spacing:
  inline: "{foundation.spacing.2}"
  control: "{foundation.spacing.3}"
  card: "{foundation.spacing.4}"
  section: "{foundation.spacing.8}"
radius:
  control: "{foundation.radius.md}"
  card: "{foundation.radius.lg}"
motion:
  fast_ms: "{foundation.motion.fast_ms}"
  normal_ms: "{foundation.motion.normal_ms}"
```

The compiler resolves references before the runtime bundle is produced. Flutter never receives unresolved token references.

## Theme Presets

Reusable visual themes live under:

`design-contract/themes/`

Initial examples may include:

- `premium-modern.yaml`
- `compact-commerce.yaml`
- `editorial-commerce.yaml`

A theme preset contains semantic overrides only. It should not duplicate the entire semantic token set.

Example:

```yaml
id: premium-modern
status: approved
semantic_overrides:
  spacing:
    section: "{foundation.spacing.8}"
  radius:
    card: "{foundation.radius.lg}"
    control: "{foundation.radius.md}"
  density:
    default: spacious
  typography:
    heading_emphasis: strong
```

Theme presets are reusable agency knowledge, not client-specific records.

## Client Brand Overrides

Client-specific brand input remains under the client project. The exact existing client-input contract should be extended rather than replaced.

Allowed conceptual inputs:

```yaml
brand:
  primary_color: "#1155CC"
  secondary_color: "#EF8A23"
  font_family: Inter
  visual_character: soft
```

Client configuration must not directly specify implementation details such as `ProductCard.padding` or arbitrary widget radii.

The compiler maps approved client brand fields to semantic token overrides.

## Direction Overrides

A/B/C directions may apply a small, governed set of semantic differences.

Examples:

- Discovery-first: more spacious default density, larger section spacing, stronger image emphasis.
- Search-first: normal density, stronger control/search emphasis.
- Trade-first: compact density, smaller radius, tighter information spacing.

Direction overrides remain semantic and must not fork the entire token system.

## Resolution Precedence

The compiler uses one explicit precedence order:

```text
foundation
< semantic defaults
< theme preset
< client brand overrides
< direction overrides
```

Later layers may override only approved semantic paths. Unknown or disallowed override paths fail validation.

## Theme Compiler

Add deterministic tooling under `tooling/design_contract/` or the nearest existing design-contract compiler location.

Responsibilities:

1. load foundation tokens;
2. load semantic defaults;
3. validate token/reference syntax;
4. load an approved theme preset;
5. derive client brand semantic overrides;
6. apply direction overrides;
7. resolve all references;
8. validate the fully resolved semantic theme;
9. emit deterministic output;
10. provide a freshness check used by repository validation and CI.

The compiler must stable-sort keys and emit UTF-8/LF with one trailing newline for checked generated artifacts.

## Runtime Bundle Integration

B.1E extends the B.1B runtime bundle's existing theme payload without changing direction contract semantics.

Resolved runtime shape should be explicit and versioned, for example:

```json
{
  "theme": {
    "version": 1,
    "color": {},
    "typography": {},
    "spacing": {},
    "radius": {},
    "elevation": {},
    "size": {},
    "density": {},
    "motion": {},
    "breakpoints": {}
  }
}
```

The runtime bundle contains resolved values only. It does not contain inheritance logic, unresolved token references, or compiler precedence rules.

## Flutter Consumption

`agency_flutter_ui` should consume resolved theme data through two layers:

### Standard Material ThemeData

Use resolved semantic values to configure appropriate Material concerns such as:

- `ColorScheme`
- `TextTheme`
- `CardTheme`
- `InputDecorationTheme`
- button/control themes
- scaffold/surface defaults

### AgencyThemeTokens ThemeExtension

Introduce an `AgencyThemeTokens` ThemeExtension (or equivalent focused extensions if implementation review proves necessary) for semantics not represented cleanly by Material ThemeData.

Examples:

- `sectionSpacing`
- `cardRadius`
- `tileGap`
- `heroSpacing`
- `compactControlHeight`
- `motionFast`
- `motionNormal`

Active prototype components/patterns should migrate major repeated styling decisions to semantic theme consumption. B.1E does not require tokenizing every pixel in the repository.

## Typography

B.1E should define a semantic type scale and family selection contract without introducing external font downloading at runtime.

The resolved theme may include:

- font family identifier;
- display/headline/title/body/label sizes;
- line heights;
- weights;
- emphasis semantics.

If a requested client font is unavailable to the Flutter project, validation/build tooling should fail governedly or use an explicitly declared approved fallback. Silent platform-dependent font substitution should not become design authority.

## Density

Canonical direction density remains `compact | normal | spacious` from B.1A/B.1D.

B.1E may derive semantic spacing/control sizing from direction density, but must not rename or replace the canonical density values.

The resolved theme should make density effects explicit rather than allowing individual widgets to invent their own compactness rules.

## Motion

B.1E v1 governs motion timing semantics only, such as fast/normal/slow durations and basic easing identifiers if already supported by Flutter implementation.

It does not introduce a general animation orchestration engine.

## Breakpoints

Breakpoints are governed semantic layout thresholds used consistently by shared Flutter UI. B.1E should define them centrally but does not redesign all responsive behavior.

## Nowa Compatibility

Nowa remains an optional visual Flutter workbench.

Operating rule:

```text
Nowa visual change
    ↓
Does an existing semantic token govern it?
    ├─ Yes → update token/theme/client override as appropriate
    └─ No
        ↓
Is the decision reusable?
        ├─ Yes → propose a new semantic token or Design Contract change
        └─ No → keep as an explicit client-local implementation exception
```

No Nowa-only persistent state is permitted. Any retained change must exist as ordinary Flutter/configuration code in GitHub.

## Validation

Repository validation should reject:

1. malformed foundation or semantic token records;
2. invalid color values;
3. invalid numeric token values;
4. unknown token references;
5. cyclic token references;
6. unresolved references after compilation;
7. unknown theme preset IDs;
8. unapproved theme presets used by current runtime clients;
9. unsupported client override paths;
10. unsupported direction override paths;
11. missing required semantic tokens;
12. stale generated/resolved theme artifacts;
13. runtime bundles whose theme differs from a fresh compile;
14. Flutter-required semantic fields missing from the compiler output.

Validation errors must be deterministically ordered.

## Migration Scope

B.1E should migrate the highest-value active styling surfaces first:

- app/root theme;
- surfaces/backgrounds;
- text hierarchy;
- cards;
- inputs/search;
- buttons/primary controls;
- shared spacing/radius semantics;
- active prototype product/list/detail/trade patterns where major hard-coded values duplicate governed semantics.

It should not block on converting every literal size or decorative constant in the whole codebase.

## Testing

### Python

Cover at minimum:

- valid foundation/semantic catalogs;
- valid preset application;
- correct precedence order;
- client brand overrides;
- direction overrides;
- unknown/disallowed override paths;
- token reference resolution;
- unknown references;
- cycle detection;
- deterministic output;
- runtime bundle theme parity;
- insertion-order-independent error reporting.

### Flutter

Cover at minimum:

- resolved runtime theme parses successfully;
- ThemeData is built from resolved semantic colors/typography;
- AgencyThemeTokens exposes spacing/radius/motion semantics;
- compact/normal/spacious density maps explicitly;
- invalid/missing required theme fields fail governedly;
- active shared widgets read semantic theme values for targeted high-value styling;
- no silent fallback to the old single-seed theme behavior for valid B.1E runtime bundles.

### Full Verification

Before merge:

- focused Python token/theme tests;
- full Python/repository validation;
- knowledge/workflow/prototype validators;
- token/theme compiler freshness check;
- Flutter analyze for prototype app, shared UI package, Widgetbook;
- Flutter tests for all three packages;
- Flutter Web build;
- final whole-branch review.

## Non-Goals

B.1E does not:

- build Flutter Review Mode;
- integrate BugDrop;
- automate screenshots;
- add Visual AI QA;
- create a full animation engine;
- dynamically load arbitrary external fonts;
- tokenize every pixel or one-off decorative value;
- replace B.1A direction density;
- change B.1D canonical Flutter binding authority;
- make Nowa a source of truth.

## Success Criteria

B.1E is complete when:

1. governed foundation and semantic token contracts exist under `design-contract/tokens/`;
2. approved reusable theme presets exist under `design-contract/themes/`;
3. client brand/theme overrides have an explicit governed mapping to semantic tokens;
4. direction-specific theme overrides are explicit and constrained;
5. one deterministic compiler resolves all theme layers using the documented precedence;
6. current client runtime bundles carry a versioned fully resolved theme;
7. Flutter consumes the resolved theme through ThemeData + governed agency-specific semantic tokens;
8. `AgencyTheme` is no longer primarily driven by a single seed color for B.1E runtime clients;
9. major active prototype styling surfaces consume semantic tokens rather than duplicated hard-coded values;
10. stale or invalid resolved themes fail repository validation/CI;
11. B.1D component/pattern binding behavior remains intact;
12. repository and Flutter CI pass.

## Dependency on Later Milestones

After B.1E, the prototype has both governed structural UI contracts (B.1D) and governed visual semantics (B.1E). The next milestone should define the Nowa-compatible refinement operating workflow and then build Flutter Review Mode for compare/select/mix/comment/approve flows.