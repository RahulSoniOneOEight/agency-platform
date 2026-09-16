# Milestone C.1 — Flutter Review Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a client-facing Review Mode inside the existing Flutter prototype app so reviewers can inspect real runtime directions, record one overall direction choice, record per-screen direction mixes, capture general/screen comments, advance review rounds, and preserve those decisions behind a replaceable persistence abstraction without mutating runtime/design/theme contracts.

**Architecture:** Keep one Flutter application with two entry modes: prototype and review. Review Mode consumes the existing `PrototypeRuntime`, `PrototypeRegistry`, direction renderers, B.1E resolved themes, and B.1F-reconciled Flutter output; it adds a dedicated review-state model, repository interface, in-memory implementation, responsive review shell, and a comparison host that reuses existing screen rendering. Review state is deliberately separate from runtime bundles and from `approved-experience.yaml`.

**Tech Stack:** Flutter/Dart, existing `agency_flutter_ui`, existing `PrototypeRuntime` / `PrototypeRegistry`, Flutter widget tests, existing Python repository validation and CI.

**Spec:** `docs/superpowers/specs/2026-09-16-milestone-c1-flutter-review-mode-design.md`

## Global Constraints

- Review Mode must live inside the existing Flutter prototype app; do not create a second app or React portal.
- Preferred entry contract is `/review?client=<client-id>`; if Flutter web path handling requires an equivalent deterministic contract, the client ID must remain explicit and hidden local state must not be required.
- B.1B runtime bundle is read-only input. Review decisions must never be written into runtime bundle files.
- B.1D canonical pattern/component IDs and Flutter bindings remain authoritative.
- B.1E resolved client/direction themes remain authoritative for reviewed client screens.
- B.1F refinement notes remain non-runtime metadata and must not be consumed by Review Mode.
- `selected_direction` is nullable until explicitly chosen; never silently persist Direction A or the first listed direction as a client selection.
- `review_round` starts at `1` and must never be `< 1`.
- C.1 statuses are exactly `in_review`, `needs_revision`, and `ready_for_final_review`.
- Comment scopes are exactly `general` and `screen`.
- Approval artifact generation, BugDrop, GitHub issue creation, screenshot automation, Visual AI QA, permanent backend selection, and workflow hardening are out of scope.
- Validation that returns multiple findings must produce deterministic, stable-sorted results.
- Keep implementation small and extensible for C.2–C.5; do not duplicate prototype screen implementations.

---

## File Structure

Create a focused review subsystem under `apps/prototype_app/lib/review/`:

- `review_state.dart` — immutable review-state and comment models, parse/serialize helpers, copy/update helpers.
- `review_state_validator.dart` — runtime-aware deterministic validation.
- `review_repository.dart` — persistence abstraction.
- `memory_review_repository.dart` — C.1 replaceable in-memory implementation.
- `review_controller.dart` — state mutation boundary for selection, mix, comments, round/status.
- `review_route.dart` — review entry detection/parsing from `Uri`.
- `review_shell.dart` — responsive review navigation and top-level composition.
- `review_overview.dart` — client/review metadata summary.
- `review_directions.dart` — direction browsing and overall direction selection.
- `review_screens.dart` — screen selector plus shared comparison host.
- `review_selection.dart` — overall choice + per-screen mix editor.
- `review_comments.dart` — general/screen comment capture and display.
- `review_screen_registry.dart` — governed mapping from review screen IDs to existing pattern/screen render targets.
- `review_comparison_host.dart` — renders an existing prototype screen/pattern for a requested direction without duplicating implementation.

Modify:

- `apps/prototype_app/lib/main.dart` — detect review entry and load the same runtime bundle.
- `apps/prototype_app/lib/prototype_app.dart` — expose/reuse common runtime-backed rendering where needed; preserve normal prototype behavior.
- `apps/prototype_app/lib/screens/prototype_shell.dart` — only if needed to extract a reusable rendering host; do not redesign normal prototype navigation.
- `apps/prototype_app/lib/registry/prototype_registry.dart` — expose stable screen/pattern labels/building support if required, without introducing review-only aliases.

Tests under `apps/prototype_app/test/review/` mirror the subsystem and remain separate from existing prototype/runtime tests.

---

### Task 1: Canonical Review State Model + Deterministic Validation

**Files:**
- Create: `apps/prototype_app/lib/review/review_state.dart`
- Create: `apps/prototype_app/lib/review/review_state_validator.dart`
- Create: `apps/prototype_app/test/review/review_state_test.dart`
- Create: `apps/prototype_app/test/review/review_state_validator_test.dart`

**Interfaces:**
- Consumes: `PrototypeRuntime.clientId`, `PrototypeRuntime.directions`, and later `ReviewScreenRegistry.screenIds`.
- Produces:
  - `enum ReviewStatus { inReview, needsRevision, readyForFinalReview }`
  - `enum ReviewCommentScope { general, screen }`
  - `final class ReviewComment`
  - `final class ReviewState`
  - `List<String> validateReviewState(ReviewState state, PrototypeRuntime runtime, {required Set<String> screenIds})`
  - deterministic `toJson()` / `fromJson()` on review models.

- [ ] **Step 1: Write failing model tests**

Create tests that require exact parsing/serialization behavior:

```dart
final state = ReviewState.fromJson({
  'version': 1,
  'client_id': 'prototype-demo',
  'review_round': 1,
  'status': 'in_review',
  'selected_direction': null,
  'screen_selections': {'home': 'A'},
  'comments': [
    {
      'id': 'review-001',
      'scope': 'general',
      'text': 'Prefer the quieter visual hierarchy.',
    }
  ],
});
expect(state.toJson(), {
  'version': 1,
  'client_id': 'prototype-demo',
  'review_round': 1,
  'status': 'in_review',
  'selected_direction': null,
  'screen_selections': {'home': 'A'},
  'comments': [
    {
      'id': 'review-001',
      'scope': 'general',
      'text': 'Prefer the quieter visual hierarchy.',
    }
  ],
});
```

Also assert stable key ordering for `screen_selections` and stable comment order as provided.

- [ ] **Step 2: Run focused tests and confirm failure**

Run:

```bash
cd apps/prototype_app
flutter test test/review/review_state_test.dart
```

Expected: failure because review-state types do not exist.

- [ ] **Step 3: Implement minimal immutable models**

Implement `ReviewState` with these exact fields:

```dart
final int version;
final String clientId;
final int reviewRound;
final ReviewStatus status;
final String? selectedDirection;
final Map<String, String> screenSelections;
final List<ReviewComment> comments;
```

Implement `ReviewComment` with:

```dart
final String id;
final ReviewCommentScope scope;
final String text;
final String? screen;
final String? direction;
```

Use explicit string mapping helpers:

```dart
String reviewStatusToWire(ReviewStatus value) => switch (value) {
  ReviewStatus.inReview => 'in_review',
  ReviewStatus.needsRevision => 'needs_revision',
  ReviewStatus.readyForFinalReview => 'ready_for_final_review',
};
```

Reject unknown enum wire values with `FormatException`.

- [ ] **Step 4: Write failing validator tests**

Cover all required C.1 validation errors in one deterministic list test:

```dart
expect(
  validateReviewState(invalidState, runtime, screenIds: {'home', 'search'}),
  equals([
    'duplicate comment id: c1',
    'invalid review round: 0',
    'screen comment c2 missing screen',
    'selected direction Z is not present in runtime directions',
    'unknown screen id: unknown',
  ]),
);
```

Include tests for client mismatch, unsupported version, invalid status parsing, mix direction not present, and unknown comment scope parsing.

- [ ] **Step 5: Implement deterministic validator**

Return `sorted(set(errors))` equivalent in Dart:

```dart
final unique = errors.toSet().toList()..sort();
return unique;
```

Never mutate runtime or state during validation.

- [ ] **Step 6: Run focused tests**

```bash
flutter test test/review/review_state_test.dart test/review/review_state_validator_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/prototype_app/lib/review/review_state.dart \
        apps/prototype_app/lib/review/review_state_validator.dart \
        apps/prototype_app/test/review/review_state_test.dart \
        apps/prototype_app/test/review/review_state_validator_test.dart
git commit -m "feat(review): add canonical review state model"
```

---

### Task 2: Persistence Abstraction + Review Controller

**Files:**
- Create: `apps/prototype_app/lib/review/review_repository.dart`
- Create: `apps/prototype_app/lib/review/memory_review_repository.dart`
- Create: `apps/prototype_app/lib/review/review_controller.dart`
- Create: `apps/prototype_app/test/review/review_repository_test.dart`
- Create: `apps/prototype_app/test/review/review_controller_test.dart`

**Interfaces:**
- Consumes: `ReviewState` from Task 1.
- Produces:

```dart
abstract interface class ReviewRepository {
  Future<ReviewState?> load(String clientId);
  Future<void> save(ReviewState state);
}
```

```dart
final class ReviewController extends ChangeNotifier {
  ReviewState get state;
  Future<void> selectDirection(String? directionId);
  Future<void> selectScreenDirection(String screenId, String directionId);
  Future<void> addComment(ReviewComment comment);
  Future<void> updateComment(ReviewComment comment);
  Future<void> setStatus(ReviewStatus status);
  Future<void> advanceRound();
}
```

- [ ] **Step 1: Write failing repository tests**

Require copy-safe in-memory persistence:

```dart
final repo = MemoryReviewRepository();
await repo.save(state);
expect(await repo.load('prototype-demo'), state);
expect(await repo.load('missing'), isNull);
```

- [ ] **Step 2: Implement repository abstraction and in-memory repository**

Store by `clientId`. Do not introduce file I/O, browser storage, Supabase, or runtime-bundle mutation in C.1.

- [ ] **Step 3: Write failing controller tests**

Cover:
- overall selection update;
- no implicit initial selection;
- per-screen mix update;
- add comment;
- update comment by ID;
- duplicate add rejected with `StateError`;
- review round increments exactly by one;
- state saves after each successful mutation.

Example:

```dart
await controller.selectScreenDirection('search', 'B');
expect(controller.state.screenSelections['search'], 'B');
expect((await repo.load('prototype-demo'))!.screenSelections['search'], 'B');
```

- [ ] **Step 4: Implement controller mutation boundary**

Every public mutation must create a new `ReviewState`, persist it, then notify listeners. Keep runtime validation out of the controller; UI wires only runtime-valid choices.

- [ ] **Step 5: Run focused tests**

```bash
flutter test test/review/review_repository_test.dart test/review/review_controller_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/review/review_repository.dart \
        apps/prototype_app/lib/review/memory_review_repository.dart \
        apps/prototype_app/lib/review/review_controller.dart \
        apps/prototype_app/test/review/review_repository_test.dart \
        apps/prototype_app/test/review/review_controller_test.dart
git commit -m "feat(review): add review persistence boundary"
```

---

### Task 3: Governed Review Screen Registry + Reusable Comparison Host

**Files:**
- Create: `apps/prototype_app/lib/review/review_screen_registry.dart`
- Create: `apps/prototype_app/lib/review/review_comparison_host.dart`
- Modify: `apps/prototype_app/lib/registry/prototype_registry.dart`
- Modify: `apps/prototype_app/lib/screens/prototype_shell.dart` only if extraction is required
- Create: `apps/prototype_app/test/review/review_screen_registry_test.dart`
- Create: `apps/prototype_app/test/review/review_comparison_host_test.dart`

**Interfaces:**
- Consumes: existing `PrototypeDirection.patterns`, `PrototypeRegistry.buildPattern`, `PrototypeRegistry.labelFor`, `FixtureRepository`.
- Produces:

```dart
final class ReviewScreenRegistry {
  static Set<String> screenIdsFor(PrototypeRuntime runtime);
  static String labelFor(String screenId);
}
```

```dart
class ReviewComparisonHost extends StatelessWidget {
  const ReviewComparisonHost({
    required this.runtime,
    required this.fixtures,
    required this.directionId,
    required this.screenId,
    super.key,
  });
}
```

- [ ] **Step 1: Write failing registry tests**

Require that screen IDs are derived from existing governed runtime direction pattern IDs, not from a new review alias table.

```dart
expect(
  ReviewScreenRegistry.screenIdsFor(runtime),
  containsAll(<String>{'commerce.home', 'commerce.search'}),
);
```

Use whatever actual canonical pattern IDs exist in the test runtime fixture; do not invent new aliases such as `home_v2`.

- [ ] **Step 2: Implement registry as a thin governed adapter**

`screenIdsFor` should union canonical pattern IDs from actual runtime directions and return a deterministic set/list ordering for UI use. `labelFor` delegates to `PrototypeRegistry.labelFor`.

- [ ] **Step 3: Write failing comparison-host widget test**

Pump one screen under Direction A and then Direction B; assert both use `PrototypeRegistry.buildPattern` output and direction-specific theme selection rather than duplicated widgets.

- [ ] **Step 4: Implement comparison host**

Resolve `directionId` from `runtime.directions`; build the requested existing pattern with `PrototypeRegistry.buildPattern`. Wrap only the reviewed client surface in:

```dart
Theme(
  data: AgencyTheme.light(runtime.themeForDirection(direction.id)),
  child: ...,
)
```

Do not let review chrome alter the reviewed client surface theme.

- [ ] **Step 5: Run focused tests**

```bash
flutter test test/review/review_screen_registry_test.dart test/review/review_comparison_host_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/review/review_screen_registry.dart \
        apps/prototype_app/lib/review/review_comparison_host.dart \
        apps/prototype_app/lib/registry/prototype_registry.dart \
        apps/prototype_app/lib/screens/prototype_shell.dart \
        apps/prototype_app/test/review/review_screen_registry_test.dart \
        apps/prototype_app/test/review/review_comparison_host_test.dart
git commit -m "feat(review): reuse governed prototype screens for comparison"
```

If `prototype_shell.dart` does not need modification, omit it from `git add`.

---

### Task 4: Deterministic Review Entry Route + Bootstrap Integration

**Files:**
- Create: `apps/prototype_app/lib/review/review_route.dart`
- Modify: `apps/prototype_app/lib/main.dart`
- Modify: `apps/prototype_app/lib/prototype_app.dart`
- Create: `apps/prototype_app/test/review/review_route_test.dart`
- Create: `apps/prototype_app/test/review/review_entry_test.dart`
- Modify: `apps/prototype_app/test/prototype_app_test.dart`

**Interfaces:**
- Consumes: `Uri.base`, existing `RuntimeLoader.loadClient`, Task 2 repository/controller, Task 3 screen registry.
- Produces:

```dart
final class ReviewRouteRequest {
  final bool isReviewMode;
  final String? clientId;
}

ReviewRouteRequest parseReviewRoute(Uri uri)
```

- [ ] **Step 1: Write failing route parser tests**

Cover:

```dart
expect(
  parseReviewRoute(Uri.parse('https://example.test/review?client=prototype-demo')),
  ReviewRouteRequest(isReviewMode: true, clientId: 'prototype-demo'),
);
```

Also test normal prototype URLs and review URL missing client ID.

- [ ] **Step 2: Implement deterministic route parser**

Treat `uri.path == '/review'` as Review Mode. A review route without `client` must be rejected with an explicit runtime error path; do not substitute `kDefaultClientId` for Review Mode. Preserve existing convenience default only for normal prototype mode.

- [ ] **Step 3: Write failing bootstrap widget tests**

Inject or expose a testable bootstrap constructor accepting a `Uri` and runtime loader callback if needed. Assert:
- review mode loads the requested client;
- normal prototype mode still loads as before;
- review route missing client shows governed error;
- explicit unknown client remains an error.

- [ ] **Step 4: Integrate bootstrap**

Refactor `PrototypeBootstrap` minimally so both modes share one runtime load. After load:
- normal mode -> `PrototypeApp`;
- review mode -> `ReviewShell` (created in Task 5; until then use a temporary compile-safe constructor only if Task 5 is implemented in the same commit sequence; do not ship a placeholder UI).

If task ordering requires compilation before Task 5, introduce a small `reviewAppBuilder` injection used only by tests and wire the real `ReviewShell` in Task 5.

- [ ] **Step 5: Preserve prototype regression behavior**

Update existing prototype tests to verify explicit invalid `?direction=` still never falls back to A and normal prototype startup remains unchanged.

- [ ] **Step 6: Run focused tests**

```bash
flutter test test/review/review_route_test.dart test/review/review_entry_test.dart test/prototype_app_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/prototype_app/lib/review/review_route.dart \
        apps/prototype_app/lib/main.dart \
        apps/prototype_app/lib/prototype_app.dart \
        apps/prototype_app/test/review/review_route_test.dart \
        apps/prototype_app/test/review/review_entry_test.dart \
        apps/prototype_app/test/prototype_app_test.dart
git commit -m "feat(review): add deterministic review entry mode"
```

---

### Task 5: Review Shell + Overview/Directions/Screens Navigation

**Files:**
- Create: `apps/prototype_app/lib/review/review_shell.dart`
- Create: `apps/prototype_app/lib/review/review_overview.dart`
- Create: `apps/prototype_app/lib/review/review_directions.dart`
- Create: `apps/prototype_app/lib/review/review_screens.dart`
- Modify: `apps/prototype_app/lib/main.dart`
- Create: `apps/prototype_app/test/review/review_shell_test.dart`

**Interfaces:**
- Consumes: `PrototypeRuntime`, `FixtureRepository`, `ReviewController`, `ReviewScreenRegistry`, `ReviewComparisonHost`.
- Produces: responsive shell with destinations exactly `Overview`, `Directions`, `Screens`, `Selection`, `Comments`.

- [ ] **Step 1: Write failing shell test**

Pump `ReviewShell` with the reference runtime and assert all five destinations are reachable without losing current `ReviewController.state`.

- [ ] **Step 2: Implement shell navigation**

Use `NavigationRail` at wide widths and `NavigationBar`/equivalent at compact widths. Keep destination index local UI state only; review decisions stay in `ReviewController`.

- [ ] **Step 3: Implement Overview**

Render:
- `runtime.clientId`;
- current review round;
- current status;
- selected direction or `Not selected`;
- number of mixed screens;
- comment count.

- [ ] **Step 4: Implement Directions screen**

Display actual runtime directions only. Use runtime direction ID/name/strategic goal and a selector that updates a local preview direction but does not persist `selected_direction` unless the explicit `Select this direction` action is pressed.

This distinction is mandatory:

```text
previewed direction != selected_direction
```

- [ ] **Step 5: Implement Screens screen**

List `ReviewScreenRegistry.screenIdsFor(runtime)`, allow one screen and one preview direction to be chosen, and render through `ReviewComparisonHost`.

- [ ] **Step 6: Wire real ReviewShell from bootstrap**

Create initial C.1 state only when repository has no saved state:

```dart
ReviewState(
  version: 1,
  clientId: runtime.clientId,
  reviewRound: 1,
  status: ReviewStatus.inReview,
  selectedDirection: null,
  screenSelections: const {},
  comments: const [],
)
```

Do not preselect `runtime.defaultDirection` into review state.

- [ ] **Step 7: Run widget tests**

```bash
flutter test test/review/review_shell_test.dart test/review/review_entry_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add apps/prototype_app/lib/review/review_shell.dart \
        apps/prototype_app/lib/review/review_overview.dart \
        apps/prototype_app/lib/review/review_directions.dart \
        apps/prototype_app/lib/review/review_screens.dart \
        apps/prototype_app/lib/main.dart \
        apps/prototype_app/test/review/review_shell_test.dart
git commit -m "feat(review): add review navigation and comparison shell"
```

---

### Task 6: Selection + Per-Screen Mix UI

**Files:**
- Create: `apps/prototype_app/lib/review/review_selection.dart`
- Modify: `apps/prototype_app/lib/review/review_shell.dart`
- Create: `apps/prototype_app/test/review/review_selection_test.dart`

**Interfaces:**
- Consumes: `ReviewController.selectDirection`, `ReviewController.selectScreenDirection`, actual runtime direction IDs, `ReviewScreenRegistry.screenIdsFor`.
- Produces: Selection screen that edits review state only.

- [ ] **Step 1: Write failing selection tests**

Cover:
- no selected overall direction initially;
- selecting Direction B sets `selectedDirection == 'B'`;
- runtime default direction shown in preview does not count as selection;
- choosing `search -> C` updates only `screenSelections['search']`;
- no unknown direction IDs appear as options.

- [ ] **Step 2: Implement overall selection control**

Use `RadioListTile`, `SegmentedButton`, or equivalent but include explicit `No selection yet` state. Do not initialize from first runtime direction.

- [ ] **Step 3: Implement per-screen mix controls**

For each governed screen ID, display a direction chooser sourced from `runtime.allowedDirections` / actual runtime direction keys. Persist through controller only.

- [ ] **Step 4: Add clear/reset behavior for overall selection if practical**

Support returning `selectedDirection` to `null`; do not clear screen mix automatically.

- [ ] **Step 5: Run focused test**

```bash
flutter test test/review/review_selection_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/review/review_selection.dart \
        apps/prototype_app/lib/review/review_shell.dart \
        apps/prototype_app/test/review/review_selection_test.dart
git commit -m "feat(review): add direction selection and screen mix"
```

---

### Task 7: Comments + Review-Round Controls

**Files:**
- Create: `apps/prototype_app/lib/review/review_comments.dart`
- Modify: `apps/prototype_app/lib/review/review_overview.dart`
- Modify: `apps/prototype_app/lib/review/review_shell.dart`
- Create: `apps/prototype_app/test/review/review_comments_test.dart`
- Create: `apps/prototype_app/test/review/review_round_test.dart`

**Interfaces:**
- Consumes: Task 2 controller comment and round APIs, actual direction IDs, governed screen IDs.
- Produces: general/screen comment capture and deterministic review-round advancement.

- [ ] **Step 1: Write failing comment tests**

Cover:
- add general comment;
- add screen comment with required screen;
- optional direction on either scope;
- generated comment IDs are unique and stable within one controller session;
- blank comment text is rejected at UI boundary;
- screen comment cannot save without screen selection.

- [ ] **Step 2: Implement comment form and list**

General comment form fields:
- text required;
- optional direction.

Screen comment form fields:
- screen required;
- text required;
- optional direction.

Use canonical runtime/screen registry values for selectors.

- [ ] **Step 3: Write failing review-round test**

Assert:

```dart
expect(controller.state.reviewRound, 1);
await controller.advanceRound();
expect(controller.state.reviewRound, 2);
```

and that current selections/comments remain intact after the round advances.

- [ ] **Step 4: Add explicit round advancement UI**

Place in Overview or review chrome with an explicit confirmation affordance. C.1 semantics are exactly `round + 1`; do not create workflow transition logic or approval states.

- [ ] **Step 5: Add status control for C.1 statuses**

Allow only the three C.1 statuses. This updates review state through controller and is not an approval action.

- [ ] **Step 6: Run focused tests**

```bash
flutter test test/review/review_comments_test.dart test/review/review_round_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/prototype_app/lib/review/review_comments.dart \
        apps/prototype_app/lib/review/review_overview.dart \
        apps/prototype_app/lib/review/review_shell.dart \
        apps/prototype_app/test/review/review_comments_test.dart \
        apps/prototype_app/test/review/review_round_test.dart
git commit -m "feat(review): add comments and review rounds"
```

---

### Task 8: Architecture Regression Coverage + Full Verification + PR

**Files:**
- Create: `apps/prototype_app/test/review/review_architecture_test.dart`
- Modify: `apps/prototype_app/test/prototype_app_test.dart` if final regression assertions are needed
- Modify: `docs/` only if operator documentation needs a concise C.1 review entry note
- Do not create approval-generation code.

**Interfaces:**
- Consumes: complete C.1 implementation.
- Produces: regression proof that C.1 is an additive review layer over existing governed prototype/runtime architecture.

- [ ] **Step 1: Add architecture regression tests**

Tests must prove:

1. normal `PrototypeApp` still renders without Review Mode;
2. Review State is not present in runtime bundle JSON fixtures;
3. review actions do not mutate `PrototypeRuntime` data;
4. `refinement-notes.yaml` is not loaded by the Dart review subsystem;
5. `approved-experience.yaml` is not written/generated by C.1;
6. reviewed client screen uses `runtime.themeForDirection(directionId)`;
7. review screen IDs come from canonical runtime pattern IDs / existing registry;
8. no silent overall direction selection occurs.

- [ ] **Step 2: Run all focused C.1 tests**

```bash
cd apps/prototype_app
flutter test test/review
```

Expected: PASS.

- [ ] **Step 3: Run full Flutter prototype tests**

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 4: Run full repository Python validation**

From repository root:

```bash
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 -m tooling.prototype.validate_prototype
```

If a module path differs on the branch, use the canonical equivalent already used by CI and record the exact command in the SDD ledger.

- [ ] **Step 5: Verify B.1D/B.1E generated artifacts remain fresh**

```bash
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
py -3.12 -m tooling.design_contract.generate_resolved_themes --check
```

Expected: both fresh.

- [ ] **Step 6: Run Flutter analyze/tests for all three packages**

```bash
cd apps/prototype_app && flutter analyze && flutter test
cd ../../packages/agency_flutter_ui && flutter analyze && flutter test
cd ../../apps/widgetbook && flutter analyze && flutter test
```

Expected: no analyze issues; all tests pass.

- [ ] **Step 7: Build Flutter Web**

```bash
cd apps/prototype_app
flutter build web
```

Expected: successful `build/web` output.

- [ ] **Step 8: Run final whole-branch review**

Reviewer must explicitly verify:
- one Flutter app only;
- runtime bundle remains read-only;
- no parallel review theme changes evaluated client screens;
- no review-only component aliases;
- no `refinement-notes.yaml` runtime use;
- no approval artifact generation;
- no first-direction/A silent selection;
- comparison host reuses existing prototype renderer;
- persistence abstraction is replaceable and UI does not own storage implementation;
- comments/mix/round data survive navigation within the controller session;
- no accidental production/backend scope creep.

- [ ] **Step 9: Fix review findings and re-run affected checks**

Use the standard SDD fix/re-review loop. Do not waive load-bearing findings.

- [ ] **Step 10: Commit final regression/docs changes**

```bash
git add apps/prototype_app/test/review \
        apps/prototype_app/test/prototype_app_test.dart \
        docs
git commit -m "test(review): lock C1 architecture boundaries"
```

Only stage files actually changed.

- [ ] **Step 11: Push and open PR**

```bash
git push -u origin milestone-c1-flutter-review-mode
gh pr create \
  --base main \
  --head milestone-c1-flutter-review-mode \
  --title "Milestone C.1: add Flutter Review Mode" \
  --body-file <prepared-pr-body-file>
```

PR body must include:
- all 8 task statuses;
- exact verification commands/results;
- explicit note that approval generation, BugDrop, screenshots, Visual AI, permanent backend are not included;
- final whole-branch reviewer result;
- any rulings/deviations.

Do not merge the PR.

---

## Self-Review Checklist

Before execution begins, confirm the plan covers every binding C.1 requirement:

- Review Mode inside same Flutter app — Tasks 4–5.
- Deterministic explicit client review entry — Task 4.
- Review state schema/status/round/selection/mix/comments — Tasks 1, 6, 7.
- Runtime-aware validation — Task 1.
- Persistence abstraction — Task 2.
- Existing renderer reuse / comparison framework — Task 3.
- Overview/Directions/Screens/Selection/Comments navigation — Tasks 5–7.
- No silent Direction A selection — Tasks 1, 5, 6, 8.
- Client resolved theme preserved — Tasks 3, 8.
- Runtime bundle read-only — Tasks 4, 8.
- B.1D/B.1E/B.1F authority preserved — Tasks 3, 8.
- Normal prototype mode preserved — Tasks 4, 8.
- Approval generation excluded — Task 8.
- Full CI/verification — Task 8.

No implementation task should introduce C.2–C.7 functionality beyond the interfaces C.1 needs.
