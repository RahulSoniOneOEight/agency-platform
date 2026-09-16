# Milestone C.2 — Compare Directions + Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the C.1 `Directions` and `Screens` review destinations into a neutral,
client-ready comparison experience: compare real runtime directions and the same governed screen
across directions, with explicit per-direction screen availability, responsive side-by-side /
focused modes, restored-selection preview seeding, and no ranking — all reusing the existing C.1
renderer and state contracts.

**Architecture:** Stay inside the existing Flutter prototype app and the C.1 `lib/review/`
subsystem. Add a governed availability adapter, a neutral direction summary card, a shared
responsive comparison layout, and two comparison surfaces wired into `review_shell.dart`. Reuse
`ReviewComparisonHost` / `PrototypeRegistry` / `PrototypeRuntime` / `ReviewController` unchanged.

**Tech Stack:** Flutter/Dart, existing `agency_flutter_ui`, existing C.1 review subsystem, Flutter
widget tests, existing Python repository validation and CI.

**Spec:** `docs/superpowers/specs/2026-09-16-milestone-c2-compare-directions-screens-design.md`

## Global Constraints

- One Flutter app; no second app, portal, registry, runtime bundle, or theme system.
- B.1B runtime bundle is read-only input.
- B.1D canonical pattern/component IDs and bindings remain authoritative.
- B.1E direction-resolved themes remain authoritative for evaluated panels.
- B.1F refinement notes remain non-runtime and are not consumed.
- C.1 `ReviewState` contract stays compatible; no new persisted state in C.2.
- `selected_direction` stays nullable until explicitly selected; never silently select Direction A.
- Availability is explicit per `(screen, direction)` pair; never render or substitute a screen a
  direction does not declare.
- Direction comparison is neutral: no score, rank, "best", "recommended", "winner".
- Preview/display state never mutates decision state.
- Do not duplicate screen implementations; reuse `ReviewComparisonHost` → `PrototypeRegistry`.
- No approval generation, BugDrop, GitHub issues, screenshots, Visual AI, permanent backend.
- Deterministic ordering everywhere (directions = `runtime.allowedDirections`; screens = sorted).

---

## File Structure

Create under `apps/prototype_app/lib/review/`:

- `review_screen_availability.dart` — governed availability adapter (delegates to
  `ReviewScreenRegistry`; no second registry).
- `review_direction_summary.dart` — neutral single-direction metadata card.
- `review_comparison_layout.dart` — responsive side-by-side vs focused/switcher primitive.
- `review_direction_comparison.dart` — Directions comparison surface.
- `review_screen_comparison.dart` — Screens comparison surface.
- `review_preview.dart` — preview/decision separation helper (`resolvePreviewDirection`).

Modify:

- `apps/prototype_app/lib/review/review_shell.dart` — wire the two surfaces into `Directions` and
  `Screens`.

Remove (superseded, avoid duplicate implementations):

- `apps/prototype_app/lib/review/review_directions.dart`
- `apps/prototype_app/lib/review/review_screens.dart`

Tests under `apps/prototype_app/test/review/`:

- `review_screen_availability_test.dart`
- `review_direction_summary_test.dart`
- `review_comparison_layout_test.dart`
- `review_direction_comparison_test.dart`
- `review_screen_comparison_test.dart`
- `review_preview_test.dart`
- `review_reference_client_test.dart`
- `review_comparison_architecture_test.dart`
- migrate `review_shell_test.dart` assertions to the new surfaces.

---

### Task 1: Direction comparison model + metadata presentation

**Files:**
- Create: `apps/prototype_app/lib/review/review_direction_summary.dart`
- Create: `apps/prototype_app/test/review/review_direction_summary_test.dart`

**Interfaces:**
- Consumes: `PrototypeDirection` (runtime object), `AgencyDensity`.
- Produces:
  - `class ReviewDirectionSummary extends StatelessWidget` rendering a neutral card for one
    `PrototypeDirection` (id, name, strategic goal, primary journey, discovery model,
    merchandising model, transaction model, canonical density, governed patterns/components).
  - `static Key cardKey(String directionId)` and
    `static Key selectButtonKey(String directionId)`.
  - An explicit `onSelect` callback (nullable) so selection stays at the call site.

- [ ] **Step 1: Write failing tests** — pump one `PrototypeDirection` from a test runtime and assert
  every runtime metadata field renders, that the label comes from the direction object (not a
  constant), and that no ranking vocabulary (`best|recommend|winner|rank|score`) is rendered.
- [ ] **Step 2: Run focused test, confirm failure** — `flutter test test/review/review_direction_summary_test.dart`.
- [ ] **Step 3: Implement `ReviewDirectionSummary`** reading fields directly from the passed
  `PrototypeDirection`; no hard-coded direction metadata. Include an optional explicit
  `Select this direction` action wired to `onSelect`.
- [ ] **Step 4: Run focused test, confirm pass.**
- [ ] **Step 5: Commit** — `feat(review): add neutral direction summary card`.

---

### Task 2: Screen availability contract/helper

**Files:**
- Create: `apps/prototype_app/lib/review/review_screen_availability.dart`
- Create: `apps/prototype_app/test/review/review_screen_availability_test.dart`

**Interfaces:**
- Consumes: `PrototypeRuntime`, `PrototypeDirection.patterns`, `ReviewScreenRegistry`.
- Produces:

```dart
abstract final class ReviewScreenAvailability {
  static List<String> orderedDirections(PrototypeRuntime runtime);
  static List<String> screens(PrototypeRuntime runtime); // sorted union, delegated
  static bool isSupported(PrototypeRuntime runtime, String directionId, String screenId);
  static String labelFor(String screenId); // delegates to ReviewScreenRegistry
}
```

- [ ] **Step 1: Write failing tests** — deterministic direction order equals
  `runtime.allowedDirections`; `screens` equals `ReviewScreenRegistry.screenIdsFor` sorted;
  `isSupported` true only when `direction.patterns` contains the screen; unknown direction/screen
  behave deterministically; `labelFor` delegates.
- [ ] **Step 2: Run focused test, confirm failure.**
- [ ] **Step 3: Implement the adapter** by delegating to `ReviewScreenRegistry` and reading
  `direction.patterns`. Do not create a second registry or alias table.
- [ ] **Step 4: Run focused test, confirm pass.**
- [ ] **Step 5: Commit** — `feat(review): add governed screen availability adapter`.

---

### Task 3: Responsive comparison layout

**Files:**
- Create: `apps/prototype_app/lib/review/review_comparison_layout.dart`
- Create: `apps/prototype_app/test/review/review_comparison_layout_test.dart`

**Interfaces:**
- Produces:

```dart
class ReviewComparisonPanel {
  const ReviewComparisonPanel({required this.id, required this.label, required this.child});
  final String id;
  final String label;
  final Widget child;
}

class ReviewComparisonLayout extends StatefulWidget {
  const ReviewComparisonLayout({
    required this.panels,
    required this.activeIndex,
    required this.onActiveIndexChanged,
    this.breakpoint = 900,
    this.allowModeToggle = false,
    super.key,
  });
}
```

- [ ] **Step 1: Write failing tests** — wide viewport renders all panels side by side (each
  `child` present); compact viewport renders the switcher + only the active `child`; the same
  `child` widgets are used in both modes (no forked rendering); the optional focus toggle on wide
  switches to the focused layout; `onActiveIndexChanged` fires from the switcher.
- [ ] **Step 2: Run focused test, confirm failure.**
- [ ] **Step 3: Implement the primitive** using `LayoutBuilder`; side-by-side = `Row` of expanded
  panels; focused/compact = switcher (`SegmentedButton`) + active panel. No business logic inside.
- [ ] **Step 4: Run focused test, confirm pass.**
- [ ] **Step 5: Commit** — `feat(review): add responsive comparison layout`.

---

### Task 4: Direction comparison surface

**Files:**
- Create: `apps/prototype_app/lib/review/review_direction_comparison.dart`
- Create: `apps/prototype_app/test/review/review_direction_comparison_test.dart`

**Interfaces:**
- Consumes: `ReviewComparisonLayout`, `ReviewDirectionSummary`, `ReviewController`,
  `runtime.allowedDirections`.
- Produces: `class ReviewDirectionComparison extends StatefulWidget` (Directions destination).

- [ ] **Step 1: Write failing tests** — renders the actual runtime directions in runtime order
  (2 and 3 directions); wide shows side-by-side summaries; compact shows switcher + one summary;
  no ranking vocabulary rendered; previewing a direction does not change `selectedDirection`;
  explicit `Select this direction` routes through `ReviewController.selectDirection`.
- [ ] **Step 2: Run focused test, confirm failure.**
- [ ] **Step 3: Implement the surface** from runtime direction objects only; local preview state;
  explicit select action only.
- [ ] **Step 4: Run focused test, confirm pass.**
- [ ] **Step 5: Commit** — `feat(review): add neutral direction comparison surface`.

---

### Task 5: Screen comparison surface (same screen across directions)

**Files:**
- Create: `apps/prototype_app/lib/review/review_screen_comparison.dart`
- Create: `apps/prototype_app/test/review/review_screen_comparison_test.dart`

**Interfaces:**
- Consumes: `ReviewScreenAvailability`, `ReviewComparisonLayout`, `ReviewComparisonHost`,
  `FixtureRepository`, `PrototypeRuntime`.
- Produces: `class ReviewScreenComparison extends StatefulWidget` (Screens destination) with a
  persistent screen selector and per-direction panels.

- [ ] **Step 1: Write failing tests** — selecting a governed screen renders that screen across
  supported directions through `ReviewComparisonHost`; an unsupported `(screen, direction)` pair
  shows the neutral unavailable state (`This screen is not part of Direction <ID>`) and does not
  render a client screen; no substitution; wide side-by-side vs compact switcher; direction theme
  applied per panel; viewing a screen does not change any selection state.
- [ ] **Step 2: Run focused test, confirm failure.**
- [ ] **Step 3: Implement the surface** reusing `ReviewComparisonHost`; availability check before
  building any client panel; no duplicated screen code.
- [ ] **Step 4: Run focused test, confirm pass.**
- [ ] **Step 5: Wire both surfaces into `review_shell.dart`**, remove superseded
  `review_directions.dart` / `review_screens.dart`, and update `review_shell_test.dart`
  assertions.
- [ ] **Step 6: Run focused + shell tests, confirm pass.**
- [ ] **Step 7: Commit** — `feat(review): add screen comparison and wire C.2 surfaces`.

---

### Task 6: Restored selection seeds preview (display vs decision separation)

**Files:**
- Create: `apps/prototype_app/lib/review/review_preview.dart`
- Create: `apps/prototype_app/test/review/review_preview_test.dart`
- Modify: `apps/prototype_app/lib/review/review_direction_comparison.dart`
- Modify: `apps/prototype_app/lib/review/review_screen_comparison.dart`
- Modify: `apps/prototype_app/test/review/review_direction_comparison_test.dart`
- Modify: `apps/prototype_app/test/review/review_screen_comparison_test.dart`

**Interfaces:**
- Produces: `String resolvePreviewDirection(PrototypeRuntime runtime, ReviewState state)` returning
  `state.selectedDirection ?? runtime.defaultDirection`.

- [ ] **Step 1: Write failing tests** — restored `selectedDirection` seeds the initial preview in
  both surfaces; runtime default used only when no selection exists; changing the preview does not
  mutate `selected_direction`; no silent Direction A.
- [ ] **Step 2: Run focused tests, confirm failure.**
- [ ] **Step 3: Implement `resolvePreviewDirection` and use it in both surfaces' preview
  initialization.**
- [ ] **Step 4: Run focused tests, confirm pass.**
- [ ] **Step 5: Commit** — `fix(review): seed comparison preview from restored selection`.

---

### Task 7: Reference-client + architecture regression tests

**Files:**
- Create: `apps/prototype_app/test/review/review_reference_client_test.dart`
- Create: `apps/prototype_app/test/review/review_comparison_architecture_test.dart`

- [ ] **Step 1: Write reference-client tests** reading the committed generated bundle
  `apps/prototype_app/assets/generated/prototype-demo.json`, asserting: direction order
  `['a','b','c']`; availability (`commerce.search` declared only by `a`; `commerce.home` only by
  `c`; `b`/`c` unavailable for `search`); direction themes differ in density / section spacing /
  card radius (one shared brand primary); a widget render proving a supported panel uses the
  direction-resolved theme and an unsupported pair shows the unavailable state. Avoid rendering
  `commerce.home`/`commerce.plp` with the reference theme (pre-existing shared `ProductCard`
  overflow, out of scope).
- [ ] **Step 2: Write architecture tests** proving: comparison uses
  `ReviewComparisonHost`/`PrototypeRegistry` (no duplicate screen implementation); runtime objects
  are not mutated; C.1 `ReviewState` JSON contract keys unchanged; no approval artifact
  generation; neutrality (no ranking vocabulary rendered).
- [ ] **Step 3: Run focused tests, confirm pass.**
- [ ] **Step 4: Commit** — `test(review): lock C.2 comparison boundaries and reference client`.

---

### Task 8: Full verification + final review + PR

- [ ] **Step 1:** `cd apps/prototype_app && flutter test test/review`
- [ ] **Step 2:** `flutter test`
- [ ] **Step 3:** `flutter analyze`
- [ ] **Step 4:** `packages/agency_flutter_ui` and `apps/widgetbook`: `flutter analyze` + `flutter test`.
- [ ] **Step 5:** `flutter build web` (prototype_app).
- [ ] **Step 6:** repository Python validation + knowledge/workflow/prototype validators.
- [ ] **Step 7:** B.1D/B.1E freshness `--check`.
- [ ] **Step 8:** final independent whole-branch review against `git diff main...HEAD`; fix findings.
- [ ] **Step 9:** push branch and open PR against `main` (do not merge).

---

## Self-Review Checklist

- Directions comparison neutral and runtime-driven — Tasks 1, 4, 7.
- Screen comparison across directions via existing host — Tasks 2, 5, 7.
- Explicit availability, no substitution — Tasks 2, 5, 7.
- Responsive side-by-side / focused — Task 3, 4, 5.
- Restored selection seeds preview; display ≠ decision — Task 6.
- No new persisted state — all tasks.
- B.1B/D/E/F + C.1 authority preserved — Tasks 5, 7.
- Reference client covered — Task 7.
- No ranking / no scope creep — Tasks 1, 4, 7.
