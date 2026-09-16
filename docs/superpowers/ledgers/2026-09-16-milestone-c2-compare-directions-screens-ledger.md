# Milestone C.2 — Compare Directions + Screens — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-c2-compare-directions-screens`
- Base: C.1 merged baseline (`43ab19e`, PR #17)
- Spec: `docs/superpowers/specs/2026-09-16-milestone-c2-compare-directions-screens-design.md`
- Plan: `docs/superpowers/plans/2026-09-16-milestone-c2-compare-directions-screens-implementation.md`
- Mode: TDD, one task at a time, fresh reviewer per task, no merge.
- Started: 2026-09-16

## Resume protocol

1. `git branch --show-current` — confirm `milestone-c2-compare-directions-screens`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first task not marked `ACCEPTED`; re-run its focused tests first.

## Pre-flight state (from C.1)

- `lib/review/` contains: `review_state.dart`, `review_state_validator.dart`,
  `review_repository.dart`, `memory_review_repository.dart`, `review_controller.dart`,
  `review_route.dart`, `review_shell.dart`, `review_overview.dart`, `review_directions.dart`,
  `review_screens.dart`, `review_selection.dart`, `review_comments.dart`,
  `review_screen_registry.dart`, `review_comparison_host.dart`.
- `ReviewScreenRegistry.screenIdsFor(runtime)` = sorted union of `direction.patterns`.
- `ReviewComparisonHost(runtime, fixtures, directionId, screenId)` wraps
  `PrototypeRegistry.buildPattern(...)` in `AgencyTheme.light(runtime.themeForDirection(id))`.
- Reference generated bundle: `apps/prototype_app/assets/generated/prototype-demo.json`
  (tracked). Directions `a,b,c`; `a` supports search/plp/pdp/cart/rfq; `b` supports
  trade-dashboard/reorder/cart; `c` supports home/plp/pdp/rfq/trade-dashboard.
- Shell destinations: Overview, Directions, Screens, Selection, Comments.

## Rulings

- **R1 — Subsystem layout.** C.2 comparison components live under `apps/prototype_app/lib/review/`;
  tests under `apps/prototype_app/test/review/`.
- **R2 — Availability source.** Availability is derived from `direction.patterns` only, via a thin
  `ReviewScreenAvailability` adapter that delegates screen listing/labels to `ReviewScreenRegistry`.
  No second registry.
- **R3 — Supersede, don't duplicate.** `review_directions.dart` and `review_screens.dart` are removed
  once the new comparison surfaces replace them; their shell tests are migrated.
- **R4 — Model-routing deviation.** Only `explore`/`general` subagents are available; no
  DeepSeek/GPT model roles from this session. Fresh `general` implementer + reviewer per task; final
  whole-branch review by a fresh `general` reviewer.
- **R5 — No new persisted state.** Comparison preview/mode state is ephemeral UI state; C.1
  `ReviewState` is unchanged.
- **R6 — Preview helper.** `resolvePreviewDirection(runtime, state) => selectedDirection ?? default`.
- **R7 — Neutrality.** Direction comparison renders no score/rank/best/recommended/winner
  vocabulary; deterministic order is `runtime.allowedDirections`.

## Task table

| Task | Scope | Status | Commit |
|------|-------|--------|--------|
| 1 | Direction summary card | ACCEPTED | `2ffa28d` |
| 2 | Screen availability adapter | ACCEPTED | `0e9441d` |
| 3 | Responsive comparison layout | ACCEPTED | `e47fa8b` |
| 4 | Direction comparison surface | ACCEPTED | `abe9534` |
| 5 | Screen comparison surface + shell wiring | ACCEPTED | `e546b87` |
| 6 | Restored selection seeds preview | ACCEPTED | `2127b36` |
| 7 | Reference-client + architecture regressions | ACCEPTED | `52d4741` |
| 8 | Full verification + final review + PR | IN_PROGRESS | — |

## Progress log

- 2026-09-16 — Pre-flight complete. C.1 merged to main (PR #17, `43ab19e`). Branch created.
  Design + plan written and approved. Ledger initialized.
- 2026-09-16 — Task 1 implemented (`2ffa28d`, 9 tests): `ReviewDirectionSummary` neutral card reading
  all metadata from `PrototypeDirection`; optional explicit `Select this direction`. Independent
  review found one major (metadata test could pass with hard-coded constants) plus minors; fixed by
  testing two directions with distinct names/goals, widening the neutrality regex, wrapping the
  header, per-direction semantics label, and a doc comment. Plan Task 1 API synced (`cardKey`).
  9/9 focused tests; analyze clean. ACCEPTED.
- 2026-09-16 — Task 4 implemented (`abe9534`, 9 tests): `ReviewDirectionComparison` neutral surface
  (panels in `allowedDirections` order, short switcher labels, ephemeral preview seeded from
  `defaultDirection`, explicit select via `ReviewController`). Independent review found one major
  (ordering test could not detect a sort regression); fixed with a non-alphabetical declared order
  (`['c','a','b']`) plus a non-first default seeding test, and neutrality asserted at wide+compact.
  9/9 focused tests; analyze clean. ACCEPTED.
- 2026-09-16 — Task 5 implemented (`e546b87`, 9 new + shell tests; 177 review tests green):
  `ReviewScreenComparison` (persistent governed screen selector, per-direction panels in runtime
  order, explicit availability via `ReviewScreenAvailability.isSupported`, `ReviewComparisonHost`
  for supported pairs, keyed neutral unavailable state otherwise, no substitution, no selection
  side effects). Shell wired to the new C.2 surfaces; superseded `review_directions.dart` /
  `review_screens.dart` deleted (no dangling refs). Independent review found no blockers/majors;
  added switcher-swap + mode-toggle coverage and hardened a Theme finder. analyze clean. ACCEPTED.
  - **Known pre-existing defect (out of C.2 scope):** `HomePattern`/`PlpPattern`
    (`mainAxisExtent: 270`) overflow with the reference theme's `ProductCard`. Reproduced in NORMAL
    prototype mode (`PrototypeApp`, reference bundle, direction `c`) at 1280x800 and 390x844, and in
    the review panels for `commerce.home`/`commerce.plp` at 1200-1600px; `commerce.search`/
    `commerce.pdp` are unaffected. C.2 does not touch shared pattern code and does not worsen it
    (overflow is height-driven, width-independent). Deferred to a shared-UI/visual-QA fix.
- 2026-09-16 — Task 6 implemented (`2127b36`, 189 review tests green): `resolvePreviewDirection`
  (`selectedDirection ?? defaultDirection`); both surfaces seed the preview from it, track
  `_userPreviewed`, and sync via a controller listener so a restored selection arriving after the
  async `load()` seeds the preview while a user preview wins. Display-only (no `selectDirection`
  from preview). Independent review: no blockers/majors (minors latent: no `didUpdateWidget`,
  out-of-range clamps to 0). analyze clean. ACCEPTED.
- 2026-09-16 — Task 7 implemented (`52d4741`, 22 new tests): reference-client regression suite using
  the committed generated bundle (order, per-pair availability, theme discrimination, renderer
  reuse, unavailable state) + C.2 architecture guards (no duplicate screen widgets, B.1B
  immutability, B.1D delegation/no alias table, B.1E per-panel themes, C.1 ReviewState 7-key
  contract, no approval artifacts, neutrality). Corrected two inaccurate spec/plan claims (search is
  declared only by `a`, not `a`/`b`; direction themes share one brand primary and differ in
  density/section/radius). Independent review: no blockers/majors; applied test-quality minors.
  22/22 focused; 209 review tests green; analyze clean. ACCEPTED.
- 2026-09-16 — Task 2 implemented (`0e9441d`, 13 tests): `ReviewScreenAvailability` thin adapter
  (`orderedDirections` = runtime order; `screens` = sorted union delegated to `ReviewScreenRegistry`;
  `isSupported` from `direction.patterns`, unknown → false; `labelFor` delegates). Independent review
  found no blockers/majors; applied minors (defensive sort, immutability test, 2-direction order test).
  13/13 focused tests; analyze clean. ACCEPTED.
- 2026-09-16 — Task 3 implemented (`e47fa8b`, 9 tests): `ReviewComparisonLayout` +
  `ReviewComparisonPanel` responsive primitive (wide Row / compact switcher + active panel / optional
  wide focus toggle); same child instances in both modes; empty + out-of-range handled. Independent
  review found no blockers/majors; applied minors (ellipsised switcher labels, same-instance identity
  test, negative index test, empty-render assertions). 9/9 focused tests; analyze clean. ACCEPTED.
