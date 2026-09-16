# Milestone C.1 — Flutter Review Mode — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-c1-flutter-review-mode`
- Base: B.1F merged baseline (`299856b`, PR #16)
- Spec: `docs/superpowers/specs/2026-09-16-milestone-c1-flutter-review-mode-design.md` (`c0d193d`)
- Plan: `docs/superpowers/plans/2026-09-16-milestone-c1-flutter-review-mode-implementation.md` (`fcef1cf`)
- Mode: TDD, one task at a time, fresh reviewer per task, no merge.
- Started: 2026-09-16

## Resume protocol

1. `git branch --show-current` — confirm `milestone-c1-flutter-review-mode`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first task not marked `ACCEPTED`; re-run its focused tests first.

## Pre-flight plan consistency scan (recorded before Task 1)

### Repository state (current Flutter app)
- `apps/prototype_app/lib/main.dart` — `PrototypeBootstrap` reads `Uri.base.queryParameters`
  (`client`, `direction`), loads via `RuntimeLoader.loadClient`, renders `PrototypeApp`.
- `PrototypeRuntime` exposes `clientId`, `defaultDirection`, `directions`, `allowedDirections`,
  `theme`, `directionThemes`, `themeForDirection(id)`, `fixtures`, `resources`.
- `PrototypeRegistry.buildPattern(canonicalPatternId, direction, fixtures)` and `labelFor(id)`
  resolve canonical pattern IDs through the B.1D adapter.
- `PrototypeShell(direction, fixtures)` renders a single direction's patterns.
- `FixtureRepository.fromRuntime(runtime)`.
- `RuntimeException` codes: `client_not_found`, `invalid_bundle`, `direction_not_found`.
- No named routes; review entry is detected from `Uri`.
- Test fixtures in `test/support/runtime_fixtures.dart` (single pattern per direction today).

### Task-to-task shared files / interfaces
- T1 → `review_state.dart` (`ReviewState`, `ReviewComment`, `ReviewStatus`, `ReviewCommentScope`)
  and `review_state_validator.dart` (`validateReviewState(state, runtime, {required screenIds})`).
- T2 → `review_repository.dart` (`ReviewRepository`), `memory_review_repository.dart`,
  `review_controller.dart` (`ReviewController extends ChangeNotifier`); consumes T1.
- T3 → `review_screen_registry.dart` (`screenIdsFor`, `labelFor`) and
  `review_comparison_host.dart`; consumes `PrototypeRegistry` + `PrototypeRuntime`.
- T4 → `review_route.dart` (`ReviewRouteRequest`, `parseReviewRoute`); modifies `main.dart`.
- T5 → `review_shell.dart`, `review_overview.dart`, `review_directions.dart`, `review_screens.dart`;
  consumes T2/T3; modifies `main.dart`.
- T6 → `review_selection.dart`; modifies `review_shell.dart`.
- T7 → `review_comments.dart`; modifies `review_overview.dart`, `review_shell.dart`.
- T8 → `test/review/review_architecture_test.dart`; full verification + PR.

### Producer / consumer contracts
- `validateReviewState` is the single runtime-aware validator (T1), reused by T2/T8.
- `ReviewController` mutations: `selectDirection(String?)`, `selectScreenDirection(String, String)`,
  `addComment(ReviewComment)`, `updateComment(ReviewComment)`, `setStatus(ReviewStatus)`,
  `advanceRound()`.
- `ReviewComparisonHost(runtime, fixtures, directionId, screenId)` is the only reviewed-surface
  renderer; it must delegate to `PrototypeRegistry.buildPattern`.
- `parseReviewRoute(Uri) -> ReviewRouteRequest` is the only entry parser.

### Internal consistency
- T1's `screenIds` parameter is supplied by T3's `screenIdsFor`; T2 keeps runtime validation out of
  the controller (R3).
- T5 must expose all five destinations even though T6/T7 add interactive Selection/Comments (R7).
- T4 must not require `kDefaultClientId` for review mode (explicit client ID only).

### Conflicts with Global Constraints — resolved
- One app / no duplicate screens → T3 reuses `PrototypeRegistry.buildPattern`; T8 regressions.
- Runtime read-only → T8 regressions; no file I/O in T2 (R9).
- `selected_direction` nullable / never A → T1/T5/T6/T8.
- Statuses/scopes exact, deterministic validation → T1.
- No approval artifact / BugDrop / screenshots / Visual AI / backend → T8.

### Conflicts with the C.1 spec — resolved
- `/review` route with Flutter hash hosting → R2.
- Controller vs runtime validation boundary → R3.

## Rulings

- **R1 — Subsystem layout.** Review code under `apps/prototype_app/lib/review/`; tests under
  `apps/prototype_app/test/review/`.
- **R2 — Routing.** `parseReviewRoute(uri)` treats `uri.path == '/review'` (trailing slash tolerated)
  or a fragment path beginning `/review` (hash-based hosting) as Review Mode. Review Mode requires an
  explicit `client` query parameter and never substitutes `kDefaultClientId`; a missing client is a
  governed `RuntimeException(client_not_found)`. Normal prototype URLs are unchanged.
- **R3 — Validation boundary.** The controller enforces structural invariants (round ≥ 1; duplicate
  comment IDs rejected with `StateError`) and persists after each mutation. Runtime-aware validation
  (direction/screen existence) lives in `validateReviewState` and is applied at the UI/test boundary.
- **R4 — Model-routing deviation.** Only `explore`/`general` subagents are available; there is no
  DeepSeek Pro/Flash or GPT-5.6 Sol routing from this session. Fresh `general` implementer + reviewer
  per task; final whole-branch review by a fresh `general` reviewer.
- **R5 — Screen registry.** `ReviewScreenRegistry.screenIdsFor(runtime)` is the deterministic union of
  canonical pattern IDs across all runtime directions; no new alias table. `labelFor` delegates to
  `PrototypeRegistry.labelFor`.
- **R6 — Theme protection.** Only the reviewed client surface is wrapped in
  `Theme(data: AgencyTheme.light(runtime.themeForDirection(directionId)))`; review chrome uses the
  agency default theme and never alters the reviewed surface.
- **R7 — Shell content.** T5 implements all five destinations with real read-only content from the
  controller; T6/T7 add the interactive Selection/Comments controls. No placeholder-only UI ships.
- **R8 — Fixtures.** Extend `test/support/runtime_fixtures.dart` to allow multiple patterns per
  direction (needed for screen-registry tests) without changing existing defaults.
- **R9 — Persistence.** C.1 persistence is in-memory only (no file I/O, browser storage, or backend).
  Review state is never written to the runtime bundle or `refinement-notes.yaml`.
- **R10 — No unnecessary churn.** `prototype_registry.dart` / `prototype_shell.dart` are modified only
  if a test proves it necessary.

## Task table

| Task | Scope | Status | Commit |
|------|-------|--------|--------|
| 1 | Review-state model + deterministic validation | PENDING | — |
| 2 | Persistence abstraction + controller | PENDING | — |
| 3 | Governed screen registry + comparison host | PENDING | — |
| 4 | Deterministic review entry point | PENDING | — |
| 5 | Review shell + Overview/Directions/Screens | PENDING | — |
| 6 | Overall selection + per-screen mix | PENDING | — |
| 7 | Comments + review-round controls | PENDING | — |
| 8 | Architecture regressions + full verification + PR | PENDING | — |

## Progress log

- 2026-09-16 — Pre-flight complete. Ledger initialized. No tasks started.
