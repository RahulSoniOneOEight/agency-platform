# Milestone C.3 — Select + Mix Refinement — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-c3-select-mix-refinement`
- Base: C.2 merged baseline (`fc5bcc2`, PR #18)
- Spec: `docs/superpowers/specs/2026-09-16-milestone-c3-select-mix-refinement-design.md` (`b7092e1`)
- Plan: `docs/superpowers/plans/2026-09-16-milestone-c3-select-mix-refinement-implementation.md` (`6bc0cc3`)
- Mode: TDD, one task at a time, fresh reviewer per task, no merge.
- Started: 2026-09-16

## Resume protocol

1. `git branch --show-current` — confirm `milestone-c3-select-mix-refinement`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first task not marked `ACCEPTED`; re-run its focused tests first.

## Preflight consistency scan (recorded before Task 1)

### Repository state (C.1/C.2 baseline)
- `ReviewState` (v1): `Map<String, String> screenSelections`; `currentVersion == 1`.
- `ReviewController`: `selectDirection(String?)`, `selectScreenDirection(String, String)`,
  `clearScreenDirection(String)`, `addComment`, `updateComment`, `setStatus`, `advanceRound`,
  `load`, `_persistAndNotify` (save-then-notify), `_copyWith`.
- `review_state_validator.dart`: runtime-aware v1 validation.
- `ReviewSelection` (C.1): overall `RadioGroup` + per-screen `SegmentedButton`.
- `ReviewShell` (C.2): 5 destinations; Directions/Screens use C.2 comparison surfaces.
- `PrototypeRegistry.buildPattern(canonicalPatternId, direction, fixtures)` renders whole patterns.
- `DesignContractResolver` + `generatedDesignBindings` are B.1D authority (patterns + components).

### B.1D section-boundary reality (drives the main ruling)
- `design-contract/patterns/*.yaml` expose `compatible_components` and metadata only — **no
  section/slot model**.
- `packages/agency_flutter_ui/lib/patterns/*.dart` are monolithic widgets that compose components
  inline (`AgencyPatternShell` + direct children). There is **no governed independently renderable
  section boundary**.
- Governed, independently renderable components that exist as Flutter widgets:
  `ProductCard`, `PriceDisplay`, `AgencySearchField`, `CreditSummary`, `QuoteCard`.

### Reference client (`prototype-demo`) availability
- directions `a`: patterns search/plp/pdp/cart/rfq; components product-card/price-display/search-field/quote-card.
- directions `b`: patterns trade-dashboard/reorder/cart; components credit-summary/quote-card/product-card.
- directions `c`: patterns home/plp/pdp/rfq/trade-dashboard; components product-card/price-display/quote-card/credit-summary.
- Cross-direction screen overlap: `plp`/`pdp`/`rfq` (a,c), `cart` (a,b), `trade-dashboard` (b,c).
- Therefore a meaningful cross-direction **section** mix exists for `plp`/`pdp` (a↔c) using
  `commerce.product-card` / `commerce.price-display`.

### Plan-vs-repository conflicts resolved
- Plan Task 2/5 assume section boundaries exist. They do not → R2/R3 below.

## Rulings

- **R1 — Subsystem layout.** C.3 code lives under `apps/prototype_app/lib/review/`; tests under
  `apps/prototype_app/test/review/`; shared section seam under `packages/agency_flutter_ui/lib/sections/`.
- **R2 — Section seam (startup ruling #6).** B.1D has no section/slot model and patterns are
  monolithic. C.3 introduces the **smallest governed section seam**: patterns are expressed as an
  ordered list of `PatternSection`s built by a shared `patternComposition(...)` function; both the
  pattern widget and the review mixed preview consume the same list. No parallel rendering stack, no
  duplicated full-screen implementation; normal Prototype Mode renders the same section widgets.
- **R3 — Governed section set.** Only sections that map to a real composition slot AND an
  independently renderable B.1D component are registered:
  `home.product-grid` (commerce.product-card), `plp.product-grid` (commerce.product-card),
  `search.search-field` (commerce.search-field), `search.results-grid` (commerce.product-card),
  `pdp.price` (commerce.price-display). No speculative hero/recommendations sections.
- **R4 — Model-routing deviation.** Only `explore`/`general` subagents are available; fresh `general`
  implementer + reviewer per task + final whole-branch reviewer. Direct implementation is used where
  a subagent cannot safely complete a step; recorded per task.
- **R5 — v2 migration.** `ReviewState.currentVersion = 2`; `fromJson` accepts canonical v2 and valid
  v1 (`screen -> direction` string) and always returns the in-memory v2 model; malformed/ambiguous
  legacy values fail with `FormatException`; serialization emits canonical v2 only.
- **R6 — Minimal persistence.** Persist only explicit, valid, non-redundant overrides; inherited
  values are computed. A null `selected_direction` is never invented.
- **R7 — Reset scope.** C.3 provides per-screen reset only; no global reset.
- **R8 — No synthetic runtime.** Mixed preview is ephemeral; runtime bundle and B.1D/E/F artifacts are
  read-only inputs.

## Task table

| Task | Scope | Status | Commit |
|------|-------|--------|--------|
| 1 | ReviewState v2 + v1 migration | ACCEPTED | `11c0e52` |
| 2 | Governed section registry + compatibility | ACCEPTED | `0956781` + `eb9d921` |
| 3 | Canonical decision normalizer | ACCEPTED | `c08a8fa` |
| 4 | Hierarchical ReviewController mutations | ACCEPTED | `7a843ea` |
| 5 | Mixed preview + source-direction theming | ACCEPTED | `d97c5e9` |
| 6 | Select + Mix client workspace | ACCEPTED | `cabc085` + `7ddc23b` |
| 7 | Reference-client + architecture regressions | ACCEPTED | `ca57011` |
| 8 | Full verification + final review + PR | IN_PROGRESS | — |

## Progress log

- 2026-09-16 — Preflight complete. Branch created from C.2 baseline; spec/plan present. R1–R8 recorded;
  section-seam ruling R2/R3 established because B.1D has no section model.
- 2026-09-16 — Task 1 implemented (`11c0e52`, 233 review tests / 295 app tests green):
  `ReviewScreenDecision` immutable value object; `ReviewState.currentVersion = 2` with
  `Map<String, ReviewScreenDecision>`; deterministic v1→v2 migration (v1 `screen -> direction`),
  malformed legacy rejected; validator structural rules; controller/selection adapted. Independent
  review found one major (`review_selection.dart` force-unwrapped a nullable `direction`, crashing on
  a valid section-only decision) — fixed with a null-aware selection set and a regression test;
  also hardened v2 screen-map key parsing. Deferred to later tasks per plan: minimal-persistence
  normalization (Task 3) and registry/availability/compatibility validator rules (Tasks 2/3).
  ACCEPTED.
- 2026-09-16 — Task 2 implemented (`0956781` + `eb9d921`, 317 app / 42 shared tests green):
  R2 section seam — `PatternSection`/`PatternComposition` + shared section widgets in
  `agency_flutter_ui/lib/sections/`; home/plp/search/pdp refactored to compose from them (rendering
  preserved; pattern widget types retained so C.1 reuse tests still pass); `PrototypeRegistry
  .compositionFor` exposes the composition. R3 governed section set: home.product-grid,
  plp.product-grid, search.search-field, search.results-grid, pdp.price. `ReviewSectionRegistry` +
  `ReviewSectionCompatibility` (availability = source declares screen AND governed component;
  compatibility adds B.1D binding + density support). Independent review: no blockers/majors; applied
  minors (widget-type mapping guard, test rename, doc fix). Deferred/accepted: compositionFor vs
  buildPattern mapping mirror (structural, both call the same builders), variant/state constraints
  (no current renderer constraint). ACCEPTED.
- 2026-09-16 — Task 3 implemented (`c08a8fa`, 272 review tests green):
  `review_decision_normalizer.dart` (pure `effectiveScreenDirection`/`effectiveSectionDirection`/
  `normalizeReviewDecisions`: drop redundant screen/section overrides, drop stale/unknown/
  incompatible sections, drop empty screens, preserve everything else, deterministic + idempotent,
  never invents a null overall). Validator extended with canonical v2 semantic rules. Independent
  review: no blockers/majors. R9 added: a screen direction override must be a direction that declares
  the screen (`screen <id> direction <d> does not include this screen`), with dependent section checks
  short-circuited. Also fixed comment rule numbering, base-layout validator test, and screen
  availability test. ACCEPTED.
- 2026-09-16 — Task 4 implemented (`7a843ea`, 294 review tests green): `ReviewController` now requires
  `runtime`; single `_apply` path (normalize → validate → save → adopt → notify); new
  `setScreenDirection`/`setSectionDirection`/`clearScreenDirection`/`clearSectionDirection`/
  `resetScreenMix`; `selectScreenDirection` removed; `load` normalizes before validating. Independent
  review found one major (the still-live C.2 Selection UI offered unavailable directions and now hit
  the validating throw) — fixed by filtering screen direction options to directions that declare the
  screen; also added a failing-save transactional test, a redundant-v1 load-normalization test, and
  updated the selection availability test. ACCEPTED.
- 2026-09-16 — Task 5 implemented (`d97c5e9`, 362 app tests green): `ReviewMixedPreview` — base
  shell/layout = effective screen direction under its resolved theme; inherited sections under base
  theme; explicit overrides render the same shared section widget built for the source direction,
  scoped in that direction's resolved theme (siblings/base uncontaminated); unresolved/absent base
  handled neutrally; runtime never mutated; no synthetic runtime. ACCEPTED.
- 2026-09-16 — Task 5 review fix (`b8d3635`): non-section screens now render under the base
  direction's resolved theme; the preview guards override availability/compatibility before applying
  (defense in depth); added explicit-screen-override, unknown-base, incompatible-override fallback,
  non-section-screen theme, and token-isolation tests. ACCEPTED.
- 2026-09-16 — Task 6 implemented (`cabc085` + `7ddc23b`, 371 app tests green): `ReviewSelection`
  is now the Select + Mix workspace (nullable overall, per-screen `Inherit from overall (X)` +
  disabled-with-reason unavailable directions, per-section `Inherit from <Screen> (X)` +
  compatibility reasons, effective summary, per-screen reset with confirmation, live
  `ReviewMixedPreview` reading controller state, responsive wide/compact). Independent review: no
  blockers/majors; fixed empty-screen guard and empty-reset disabling. Deferred minor: a screen that
  inherits an overall direction which does not declare it still shows a base label (model question,
  no false rendering). ACCEPTED.
- 2026-09-16 — Task 7 implemented (`ca57011`, 324 review tests green): `review_mix_architecture_test.dart`
  (runtime/bundle immutability across mix ops, no file I/O in `lib/review`, no concrete pattern
  widgets, `ReviewSectionRegistry` sole section-id authority, no component-level mix API, no
  refinement, no approval artifacts, v1→v2 migration) + real reference-client mix regressions
  (`plp.product-grid`/`pdp.price` c→a compatible; `pdp.price` rendered with source theme; unavailable
  from b rejected with zero side effects) + extended C.1/C.2 architecture guarantees. ACCEPTED.
- 2026-09-16 — Task 8 verification: app `flutter test` 387, analyze clean; agency_flutter_ui 42 +
  clean; widgetbook 1 + clean; `flutter build web` built; Python 283 unittest OK + validate_repo (98
  paths) + knowledge/workflow/prototype validators; B.1D/B.1E freshness fresh.
