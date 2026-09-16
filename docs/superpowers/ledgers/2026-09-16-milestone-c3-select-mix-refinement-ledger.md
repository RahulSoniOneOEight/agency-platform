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
| 1 | ReviewState v2 + v1 migration | PENDING | — |
| 2 | Governed section registry + compatibility | PENDING | — |
| 3 | Canonical decision normalizer | PENDING | — |
| 4 | Hierarchical ReviewController mutations | PENDING | — |
| 5 | Mixed preview + source-direction theming | PENDING | — |
| 6 | Select + Mix client workspace | PENDING | — |
| 7 | Reference-client + architecture regressions | PENDING | — |
| 8 | Full verification + final review + PR | PENDING | — |

## Progress log

- 2026-09-16 — Preflight complete. Branch created from C.2 baseline; spec/plan present. R1–R8 recorded;
  section-seam ruling R2/R3 established because B.1D has no section model.
