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

## Task table

| Task | Scope | Status | Commit |
|------|-------|--------|--------|
| 1 | Foundation + semantic token contracts | PENDING | — |
| 2 | Theme presets + reference resolver | PENDING | — |
| 3 | Client brand + direction overrides | PENDING | — |
| 3r | Task 3 review | PENDING | — |
| 4 | Runtime bundle integration | PENDING | — |
| 5 | Flutter ThemeData + AgencyThemeTokens | PENDING | — |
| 6 | High-value UI migration | PENDING | — |
| 7 | Repository validation + CI freshness | PENDING | — |
| 8 | Docs + full verification + PR | PENDING | — |

## Progress log

- 2026-09-16 — Pre-flight complete. Ledger initialized. No tasks started.
