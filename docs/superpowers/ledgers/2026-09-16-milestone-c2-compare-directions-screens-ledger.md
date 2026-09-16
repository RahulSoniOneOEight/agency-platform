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
| 1 | Direction summary card | PENDING | — |
| 2 | Screen availability adapter | PENDING | — |
| 3 | Responsive comparison layout | PENDING | — |
| 4 | Direction comparison surface | PENDING | — |
| 5 | Screen comparison surface + shell wiring | PENDING | — |
| 6 | Restored selection seeds preview | PENDING | — |
| 7 | Reference-client + architecture regressions | PENDING | — |
| 8 | Full verification + final review + PR | PENDING | — |

## Progress log

- 2026-09-16 — Pre-flight complete. C.1 merged to main (PR #17, `43ab19e`). Branch created.
  Design + plan written and approved. Ledger initialized.
