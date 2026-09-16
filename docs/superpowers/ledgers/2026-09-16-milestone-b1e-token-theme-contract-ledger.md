# Milestone B.1E — Token + Theme Contract — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming this run
> after compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-b1e-token-theme-contract`
- Base: B.1D merged baseline (merge commit `e262468`, PR #14)
- Spec: `docs/superpowers/specs/2026-09-16-milestone-b1e-token-theme-contract-design.md` (`b20f2ab`)
- Plan: `docs/superpowers/plans/2026-09-16-milestone-b1e-token-theme-contract-implementation.md` (`ea6034b`)
- Mode: TDD, one task at a time, fresh reviewer per task, no merge.
- Started: 2026-09-16

## Resume protocol

1. `git status` / `git branch --show-current` — confirm on `milestone-b1e-token-theme-contract`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Read this ledger's task table; resume at the first task not marked `ACCEPTED`.
4. Re-run the task's focused tests before continuing (never trust an unverified claim).

## Pre-flight plan consistency scan (recorded before Task 1)

### Repository state
- `design-contract/tokens/` and `design-contract/themes/` exist but contain only `.gitkeep`.
- `design-contract/schema/` has component/pattern/journey/flutter-binding schemas.
- `tooling/design_contract/` has `flutter_bindings.py`, `generate_flutter_bindings.py`, `__init__.py`.
- `tooling/prototype/build_runtime_bundle.py` composes the bundle; `compose_runtime_bundle(client_dir)`
  takes only `client_dir` and copies `manifest["theme"]` verbatim.
- `tooling/prototype/validate_runtime_bundle.py` validates `theme.seed_color` as `#RRGGBB`.
- `apps/prototype_app/lib/runtime/prototype_runtime.dart` parses `theme.seed_color`.
- `apps/prototype_app/lib/prototype_app.dart` builds `AgencyTheme.light(seedColor: ...)`.
- `packages/agency_flutter_ui/lib/themes/agency_theme.dart` is seed-color driven.
- `packages/agency_flutter_ui/lib/foundation/agency_tokens.dart` holds static `AgencyTokens` consts.
- Widgets consume `AgencyTokens.*` static constants (product_card, promo_tile, category_tile, etc.).
- `client-projects/examples/prototype-demo/input/brand/brand-input.yaml` has only `facts` (name).
- `client-projects/examples/prototype-demo/prototype/prototype-manifest.yaml` has `theme.seed_color`.

### Task-to-task shared files / interfaces
- `tooling/design_contract/theme_contract.py` is created by Task 1 and modified by Tasks 2 and 3.
  Interfaces must remain stable: `load_foundation_tokens`, `load_semantic_tokens`,
  `validate_token_catalogs` (T1); `load_theme_presets`, `resolve_theme` (T2);
  `brand_to_semantic_overrides`, `validate_direction_theme_overrides` (T3).
- `design-contract/tokens/*` (T1) and `design-contract/themes/*` (T2) are consumed by T3/T4/T7.
- Task 3 modifies `client-projects/schema/input/brand-input.schema.json` and
  `tooling/knowledge/direction.schema.json`; Task 4 consumes the new fields.
- Task 4 modifies `tooling/prototype/build_runtime_bundle.py` + `validate_runtime_bundle.py` and
  regenerates `apps/prototype_app/assets/generated/*.json`.
- Task 5 creates `apps/prototype_app/lib/runtime/runtime_theme.dart`,
  `packages/agency_flutter_ui/lib/themes/agency_theme_tokens.dart`, modifies `agency_theme.dart`,
  and rewires `prototype_runtime.dart` + `prototype_app.dart` + `main.dart`.
- Task 6 modifies shared widgets in `packages/agency_flutter_ui/lib/` to consume the extension.
- Task 7 modifies `tooling/validation/validate_repo.py`, `test_validate_repo.py`, CI workflows,
  `.gitattributes`.
- Task 8 docs + full verification + PR.

### Producer / consumer contracts
- `resolve_theme(root, preset_id, client_brand, direction_overrides) -> dict` (T2) is the single
  resolution entry point consumed by T3/T4 and by repository freshness checks (T7).
- Resolved theme shape: `{"version": 1, <9 semantic groups>}` with zero `{foundation...}` strings.
- Runtime bundle: `theme` (resolved base) + `direction_themes` (resolved per-direction overrides);
  Dart `RuntimeTheme.fromJson` (T5) is the only consumer.
- `AgencyTheme.light(<resolved theme>)` (T5) produces `ThemeData` + `AgencyThemeTokens` extension;
  active widgets (T6) read `Theme.of(context)` / `AgencyThemeTokens.of(context)`.

### Task internal consistency
- T1 forbids reference resolution; T2 adds it. T1 validation must accept `{foundation.<path>}`
  syntax without resolving.
- T1 must seed all nine semantic groups because T4 requires them and T5 requires specific fields.
- T5's `AgencyThemeTokens` fields must all exist as required semantic tokens (see Ruling R6).
- T4's bundle validation and T7's repo validation must reuse `resolve_theme`; no duplicated logic.

### Conflicts with Global Constraints — resolved
- Old `seed_color` path conflicts with "no seed-color authority". Ruling R1/R7 replace it.
- Per-direction visual differences conflict with a single `theme` object. Ruling R1 adds
  `direction_themes`.
- Client override allowlisting must reject widget implementation keys. Ruling R3 + T3 allowlist.

## Rulings (made to avoid pausing on normal ambiguity)

- **R1 — Runtime theme shape.** The bundle keeps a top-level `theme` = fully resolved theme for the
  default direction *without* direction overrides (backward-compatible single object), and adds
  `direction_themes: {<direction-id>: <resolved theme>}` for every direction that declares
  non-empty theme overrides. Flutter resolves the active theme as
  `direction_themes[directionId] ?? theme`. Runtime carries resolved values only.
- **R2 — Preset selection.** The approved theme preset is declared in the client brand input as
  `visual.preset`; other brand visual fields live under `visual:` too (`primary_color`,
  `secondary_color`, `font_family`, `font_fallback`, `visual_character`). `brand-input.schema.json`
  is extended, not replaced.
- **R3 — Direction override location.** Direction theme overrides live in the strategic direction
  YAML under `theme_overrides:` (an allowlisted semantic subset). They are consumed by the theme
  compiler and are NOT projected into the B.1A runtime direction JSON (schema unchanged).
- **R4 — Model routing deviation.** The environment exposes only `explore` and `general` task
  subagents; `@builder`/`@worker` (DeepSeek) and `@reviewer` (GPT-5.6 Sol) are not invocable from
  this session. Implementers and reviewers are fresh `general` subagents; the final whole-branch
  review uses the strongest available independent reviewer. Recorded as a deviation.
- **R5 — Density.** Canonical density stays exactly `compact | normal | spacious`. Resolved theme
  `density.default` = the effective density (direction density for `direction_themes`, preset
  default for the base `theme`). `AgencyThemeTokens` exposes the canonical density name.
- **R6 — Required semantic token set (v1).** color: `primary, on_primary, secondary, on_secondary,
  surface, surface_muted, text_primary, text_secondary, border, error, on_error`;
  typography: `font_family, font_fallback, display, headline, title, body, label, line_height_body,
  weight_regular, weight_emphasis, heading_emphasis`; spacing: `inline, control, card, tile,
  section`; radius: `control, card`; elevation: `card, overlay`; size: `control_height,
  control_height_compact, icon`; density: `default`; motion: `fast_ms, normal_ms, slow_ms, easing`;
  breakpoints: `mobile, tablet, desktop`. These are the minimum Flutter-required fields.
- **R7 — Manifest theme.** The prototype manifest's `theme` becomes `{preset: <approved-preset-id>}`.
  The runtime bundle's `theme` is compiled by the theme compiler, never copied from the manifest.
  `compose_runtime_bundle` gains a `root` parameter so it can load `design-contract/` catalogs;
  `build_runtime_bundle` and `validate_repo` are updated accordingly.
- **R8 — Fonts.** No runtime font download. `typography.font_family` is a logical identifier and
  `typography.font_fallback` is the concrete family used by Flutter. Compilation fails governed if
  the fallback is empty; unknown requested families fall back to the declared fallback (recorded in
  the resolved theme), never silently to a platform-dependent substitute.
- **R9 — Nowa.** No Nowa-specific state or tooling is added. Documentation records the operating
  rule only.
- **R10 — Implementer delegation.** Core contract/compiler tasks are implemented by the orchestrator
  with strict TDD; every task is reviewed by a fresh independent `general` reviewer subagent before
  continuing, and a final whole-branch review is dispatched. This preserves the review gates while
  keeping cross-task interfaces coherent.
- **R11 — Direction density.** The canonical direction `density` field is authoritative for a
  direction theme's `density.default`. Direction `theme_overrides` may not set `density` (excluded
  from the allowlist); it may set approved spacing/radius/size/typography-emphasis paths only.
- **R12 — visual_character.** `visual_character` is validated metadata in v1 (approved enum) with no
  semantic token mapping yet; `brand_to_semantic_overrides` intentionally ignores it.
- **R14 — Material-derived roles.** Flutter derives un-tokenized Material roles (containers/tones)
  from the resolved `color.primary` via `ColorScheme.fromSeed`, then overrides the explicit semantic
  roles. Tokenizing every Material role is out of B.1E scope; explicit semantic roles are governed.
- **R13 — direction_themes.** The bundle's `theme` is the resolved base (preset + brand, preset
  density). `direction_themes` carries a fully resolved theme for every declared direction (that
  direction's canonical density + allowlisted `theme_overrides`). Flutter selects
  `direction_themes[id] ?? theme`. `compose_runtime_bundle(root, client_dir)` compiles both; the
  manifest carries only `theme: {preset}`.

## Task table

| Task | Scope | Status | Commit |
|------|-------|--------|--------|
| 1 | Foundation + semantic token contracts | ACCEPTED | `8220de3` + `ff90e0d` |
| 2 | Theme presets + reference resolver | ACCEPTED | `5a19267` + `7f7dc9a` |
| 3 | Client brand + direction overrides | ACCEPTED | `927bbe5` + `4ac25bf` |
| 4 | Runtime bundle integration | ACCEPTED | `ddae18a` + `d4e62dc` |
| 5 | Flutter ThemeData + AgencyThemeTokens | ACCEPTED | `9dc5daf` + `4545b6d` |
| 6 | High-value UI migration | ACCEPTED | `0931fa3` + `a7892f3` |
| 7 | Repository validation + CI freshness | PENDING | — |
| 8 | Docs + full verification + PR | PENDING | — |

## Progress log

- 2026-09-16 — Pre-flight complete. Ledger initialized.
- 2026-09-16 — Task 1 implemented (`8220de3`, 28 tests) and independently reviewed (no blockers).
  Review corrections `ff90e0d`: reject empty groups, non-numeric literals in numeric semantic
  groups, and boolean `version`; removed dead constant. 32 tests green. ACCEPTED.
- 2026-09-16 — Task 2 implemented (`5a19267`, 51 tests): preset loader/validator, brand mapping,
  `resolve_theme` with DFS reference resolution + cycle detection, 3 approved presets, preset schema.
  Independent review found one Major (type-changing overrides for typography/motion accepted).
  Corrections `7f7dc9a`: per-leaf numeric/string enforcement, preset unknown-key rejection, duplicate
  preset id rejection, strict resolution regex. 56 tests; full suite 226 green. ACCEPTED.
  Note: `load_theme_presets` raises on duplicate id; `resolve_theme` revalidates the resolved theme.
- 2026-09-16 — Task 3 implemented (`927bbe5`): brand-input `visual` schema + reference client visual
  (preset `premium-modern`), `theme_overrides` on the three reference directions, direction schema
  property, `validate_client_brand_visual` + `validate_direction_theme_overrides` + allowlists.
  Review found no blockers; corrections `4ac25bf`: never-raise on mixed keys, reject empty disallowed
  override groups, tolerate `visual.preset`. 77 focused / 236 full tests green. ACCEPTED.
  Deferred to Task 4/7: invoke `validate_direction_theme_overrides` at the strategic direction
  validation entry point (repo validation) — currently only `resolve_theme` enforces it.
- 2026-09-16 — Task 4 implemented (`ddae18a`): `compose_runtime_bundle(root, client_dir)` compiles
  `theme` + `direction_themes` via `resolve_theme`; manifest carries `theme: {preset}`; runtime
  validator uses `validate_resolved_theme`; `generate_resolved_themes` CLI (`--write`/`--check`);
  bundle regenerated (brand primary `#1155CC`, direction densities a=compact b/c=normal). Review
  found no blockers; corrections `d4e62dc`: template `theme.preset`, cycle-safe `_walk_leaves`,
  dedup `_write_preset`, compact/normal/spacious density coverage. 243 tests green. ACCEPTED.
  Deferred to Task 7: wire `validate_direction_theme_overrides` into strategic direction validation;
  dedupe `validate_repo` freshness against `check_resolved_bundles_fresh`; consider orphan-bundle
  detection. Also Task 8: update `docs/client-runtime.md` seed-color reference.
- 2026-09-16 — Task 5 implemented (`9dc5daf`): `AgencyResolvedTheme` (strict `fromJson`),
  `AgencyThemeTokens` ThemeExtension, `AgencyTheme.light(resolved)` + explicit agency default,
  `RuntimeTheme` alias, `PrototypeRuntime` parses `theme`/`direction_themes` + `themeForDirection`,
  app themes with the active direction theme; seed-color authority removed. Review found no blockers;
  corrections `4545b6d`: strict integral numbers, expose `overlayElevation`/`iconSize`, governed
  input error/disabled borders, added parser/theme-switch tests. 33 package + 63 app + 1 widgetbook
  tests green. ACCEPTED. Known limitation recorded as R14.
- 2026-09-16 — Task 6 implemented (`0931fa3`): high-value primitives/domain/patterns read
  `AgencyThemeTokens.of(context)` / `Theme.of(context)`; semantic migration tests added. Review found
  one Major (PDP detail still hard-coded radius 16 / spacing) and button width regression;
  corrections `a7892f3`: PDP + search/trade/rfq/booking/quote/credit spacing migrated, button
  min-width fix, `inlineSpacing`/`controlSpacing` exposed, PlpPattern density test. 42 package +
  63 app + 1 widgetbook tests green. ACCEPTED.
