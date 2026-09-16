# Token + Theme Contract (B.1E)

B.1E introduces a governed visual design layer: agency foundation tokens, semantic tokens,
reusable theme presets, client brand overrides, and direction overrides resolve into a
deterministic, fully resolved runtime theme consumed by Flutter.

## Authority chain

```text
client brand facts + direction intent
        ↓
Design Contract token/theme compiler   (tooling/design_contract/theme_contract.py)
        ↓
resolved runtime theme                  (apps/prototype_app/assets/generated/<client>.json)
        ↓
Flutter ThemeData + AgencyThemeTokens
        ↓
Nowa may refine implementation, but GitHub/configuration remains authority
```

`design-contract/` is the canonical visual contract authority. Flutter registry keys, Dart class
names, and widget factories remain implementation details (B.1D).

## Token layers

- **Foundation tokens** — `design-contract/tokens/foundation.yaml`: reusable raw scales for
  `color`, `typography`, `spacing`, `radius`, `elevation`, `size`, `density`, `motion`, and
  `breakpoints`. Implementation-neutral; not consumed directly by most widgets.
- **Semantic tokens** — `design-contract/tokens/semantic.yaml`: the normal consumption boundary.
  Values are literals or complete `{foundation.<path>}` references.
- **Theme presets** — `design-contract/themes/*.yaml`: reusable visual character (semantic
  overrides only). Only `status: approved` presets are consumable.
- **Client brand** — `client-projects/<client>/input/brand/brand-input.yaml` `visual:` block:
  `preset`, `primary_color`, `secondary_color`, `font_family`, `font_fallback`, `visual_character`.
- **Direction overrides** — `client-projects/<client>/directions/direction-*.yaml`
  `theme_overrides:`: an allowlisted semantic subset (spacing, radius, size, typography emphasis).
  Direction density is the canonical B.1A `density` field, not a `theme_overrides` entry.

## Resolution precedence

```text
foundation < semantic defaults < theme preset < client brand overrides < direction overrides
```

Later layers may override only approved semantic paths. Unknown or disallowed override paths fail
validation. Client configuration may never specify widget implementation details such as
`ProductCard.padding` or `SearchBar.radius`.

## Compiler and artifacts

`tooling/design_contract/theme_contract.py` loads and validates the layers, resolves references
(with cycle detection), applies the precedence order, and validates the fully resolved theme.

`tooling/design_contract/generate_resolved_themes.py` writes/checks the generated client bundles:

```text
python -m tooling.design_contract.generate_resolved_themes --write
python -m tooling.design_contract.generate_resolved_themes --check
```

Generated artifacts are deterministic (stable key ordering, UTF-8, LF, one trailing newline) and
freshness-checked by repository validation.

## Runtime bundle theme

The B.1B runtime bundle's `theme` payload becomes a versioned, fully resolved theme (all nine
groups) with no unresolved references and no inheritance logic. The bundle also carries
`direction_themes: {<direction-id>: <resolved theme>}` for each declared direction; Flutter selects
`direction_themes[id] ?? theme`. The prototype manifest carries only `theme: {preset: <id>}`.

## Flutter consumption

`apps/prototype_app/lib/runtime/runtime_theme.dart` parses the resolved theme
(`RuntimeTheme.fromJson`), and `PrototypeRuntime.themeForDirection(...)` selects the active theme.

`packages/agency_flutter_ui` builds Material 3 `ThemeData` from the resolved values
(`AgencyTheme.light(AgencyResolvedTheme)`) and exposes an `AgencyThemeTokens` `ThemeExtension` for
agency-specific semantics (section/card/tile spacing, control/card radius, control height, motion,
breakpoints, density). High-value active surfaces read these semantic values rather than hard-coded
literals.

There is no silent fallback to a single seed color for valid B.1E runtime bundles. A seed color is
used only to derive un-tokenized Material container/tone roles from the resolved `color.primary`.

## Fonts

No external fonts are downloaded at runtime. `typography.font_family` is a logical identifier and
`typography.font_fallback` is the concrete family used by Flutter.

## Nowa operating rule

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

No Nowa-only persistent state is permitted. Any retained change must exist as ordinary
Flutter/configuration code in GitHub.

## Validation

Repository validation (`tooling/validation/validate_repo.py`) rejects malformed/invalid token
catalogs, invalid colors/numbers, unknown or cyclic references, unresolved references after
compilation, unknown or unapproved presets, unsupported client/direction override paths, missing
required semantic tokens, stale resolved themes, and runtime bundles that differ from a fresh
compile. Validation errors are deterministically ordered.
