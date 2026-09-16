# Milestone C.3 — Select + Mix Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve Review Mode into a governed draft decision workspace with overall → screen → section inheritance, ReviewState v2 migration, strict section compatibility, deterministic normalization, and live mixed Flutter preview.

**Architecture:** Extend the existing C.1/C.2 ReviewState/ReviewController path rather than creating a parallel composition system. Review decisions remain separate from the read-only runtime bundle; section identity is a thin governed adapter over B.1D; mixed preview is ephemeral and delegates to existing Flutter widgets/renderers with base-direction theming plus nested source-direction theming for explicit section overrides.

**Tech Stack:** Flutter/Dart, existing `prototype_app` review/runtime/registry code, `agency_flutter_ui`, generated B.1D bindings, B.1E resolved themes, Python repository validators, Flutter widget/unit tests.

**Spec:** `docs/superpowers/specs/2026-09-16-milestone-c3-select-mix-refinement-design.md`

## Global Constraints

- Work only on `milestone-c3-select-mix-refinement` until the PR is opened.
- C.2 merge `fc5bcc2ec17a49e01a2a5e21d883e0efc52e3ce7` is the required baseline.
- B.1B runtime bundle remains read-only; never persist a synthetic mixed runtime.
- B.1D remains canonical for pattern/component identity and Flutter bindings.
- B.1E remains canonical for resolved client/direction themes.
- B.1F refinement notes remain non-runtime.
- C.2 comparison surfaces remain neutral and viewing them must never mutate decisions.
- Canonical ReviewState persisted version becomes `2`; valid version-1 state must migrate in memory where unambiguous.
- Persist only explicit non-redundant overrides.
- Invalid mutations must have zero persistence and zero listener-notification side effects.
- Section overrides require both availability and render-contract compatibility.
- No approval generation, `approved-experience.yaml`, BugDrop, screenshot automation, Visual AI QA, permanent backend, component-level arbitrary mixing, or second review app.
- Do not commit the existing untracked `pubspec.lock` files.
- Use TDD and a fresh independent reviewer gate after every task.

## File Structure

The implementation should keep responsibilities focused:

- `apps/prototype_app/lib/review/review_state.dart` — ReviewState v2 wire contract and v1 migration.
- `apps/prototype_app/lib/review/review_screen_decision.dart` — immutable screen decision value object (`direction` + section overrides).
- `apps/prototype_app/lib/review/review_state_validator.dart` — runtime-aware validation of v2 canonical state.
- `apps/prototype_app/lib/review/review_section_registry.dart` — thin governed review-section adapter over existing B.1D/runtime identities.
- `apps/prototype_app/lib/review/review_section_compatibility.dart` — deterministic availability/compatibility checks and reasons.
- `apps/prototype_app/lib/review/review_decision_normalizer.dart` — one canonical inheritance/normalization path.
- `apps/prototype_app/lib/review/review_controller.dart` — mutation boundary and auto-persistence.
- `apps/prototype_app/lib/review/review_mixed_preview.dart` — ephemeral mixed-preview composition.
- `apps/prototype_app/lib/review/review_selection.dart` — Select + Mix client workspace.
- `apps/prototype_app/lib/review/review_shell.dart` — only wiring changes needed to supply fixtures/runtime to Selection.
- `packages/agency_flutter_ui/...` — modify only where a governed reusable section boundary must be exposed; do not duplicate business widgets.
- `apps/prototype_app/test/review/...` — focused tests for migration, registry, compatibility, normalization, controller, selection UX, mixed preview, architecture, and the reference client.

---

### Task 1: ReviewState v2 + deterministic v1 migration

**Files:**
- Create: `apps/prototype_app/lib/review/review_screen_decision.dart`
- Modify: `apps/prototype_app/lib/review/review_state.dart`
- Modify: `apps/prototype_app/lib/review/review_state_validator.dart`
- Modify: `apps/prototype_app/test/review/review_state_test.dart`
- Modify: `apps/prototype_app/test/review/review_state_validator_test.dart`
- Create: `apps/prototype_app/test/review/review_state_migration_test.dart`

**Interfaces:**
- Produce immutable `ReviewScreenDecision` with `String? direction`, `Map<String,String> sections`, `fromJson`, `toJson`, equality/hashCode.
- Change `ReviewState.screenSelections` to `Map<String, ReviewScreenDecision>`.
- `ReviewState.currentVersion == 2`.
- `ReviewState.fromJson` accepts canonical v2 and valid legacy v1 `screen -> direction` entries; returned object is always in-memory v2.
- `toJson()` always emits canonical v2 and deterministic key ordering.

- [ ] **Step 1: Write failing migration/model tests**

Add tests equivalent to:

```dart
test('migrates version 1 screen direction map to v2 decisions', () {
  final state = ReviewState.fromJson({
    'version': 1,
    'client_id': 'prototype-demo',
    'review_round': 2,
    'status': 'in_review',
    'selected_direction': 'a',
    'screen_selections': {'commerce.home': 'b'},
    'comments': [],
  });

  expect(state.version, ReviewState.currentVersion);
  expect(state.screenSelections['commerce.home']!.direction, 'b');
  expect(state.screenSelections['commerce.home']!.sections, isEmpty);
  expect(state.toJson()['version'], 2);
});
```

Also test canonical v2 round-trip, malformed mixed legacy values rejected, comments/status/round preserved, sorted screen/section serialization, and collection immutability.

- [ ] **Step 2: Run focused tests and confirm intended failure**

Run from `apps/prototype_app`:

```bash
flutter test test/review/review_state_test.dart test/review/review_state_migration_test.dart test/review/review_state_validator_test.dart
```

Expected: FAIL because v2 decision types/migration do not yet exist.

- [ ] **Step 3: Implement the immutable decision object and v2 parser/serializer**

Use a value-object shape equivalent to:

```dart
final class ReviewScreenDecision {
  ReviewScreenDecision({String? direction, Map<String, String> sections = const {}})
      : direction = direction,
        sections = Map<String, String>.unmodifiable(sections);

  final String? direction;
  final Map<String, String> sections;
}
```

Parsing rules:
- `version == 1`: every screen value must be a non-empty String; migrate to `ReviewScreenDecision(direction: value)`.
- `version == 2`: every screen value must be a map; `direction` optional/null/String; `sections` required map or canonical empty map according to the approved spec.
- Any other persisted version fails deterministically.
- Returned state uses `version: 2` after migration.

- [ ] **Step 4: Update validator for the new shape without section compatibility yet**

At this task, validate client/version/round/status/comments, screen IDs, explicit screen directions, and section source direction IDs structurally. Section registry/compatibility validation lands in Task 2.

- [ ] **Step 5: Run focused tests**

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/review/review_screen_decision.dart apps/prototype_app/lib/review/review_state.dart apps/prototype_app/lib/review/review_state_validator.dart apps/prototype_app/test/review/review_state_test.dart apps/prototype_app/test/review/review_state_validator_test.dart apps/prototype_app/test/review/review_state_migration_test.dart
git commit -m "feat(review): migrate review state to hierarchical v2 decisions"
```

---

### Task 2: Governed section registry + compatibility contract

**Files:**
- Create: `apps/prototype_app/lib/review/review_section_registry.dart`
- Create: `apps/prototype_app/lib/review/review_section_compatibility.dart`
- Modify if needed: `apps/prototype_app/lib/registry/prototype_registry.dart`
- Modify only if required to expose an existing reusable section boundary: focused files under `packages/agency_flutter_ui/lib/`
- Create: `apps/prototype_app/test/review/review_section_registry_test.dart`
- Create: `apps/prototype_app/test/review/review_section_compatibility_test.dart`
- Modify: `apps/prototype_app/test/review/review_reference_client_test.dart`

**Interfaces:**
- Produce `ReviewSectionDefinition` with stable `id`, governed `screenId`, `label`, B.1D-backed component/pattern identity, slot/render-contract key.
- Produce `ReviewSectionRegistry.sectionsForScreen(screenId)` and `definition(sectionId)`.
- Produce a compatibility result with `allowed` and deterministic human-readable `reason`.

- [ ] **Step 1: Inspect actual B.1D metadata before writing the registry table**

Use the existing design-contract pattern/component files and generated Flutter bindings as authority. The first governed C.3 section set must map only to components/slots that the current Flutter implementation can render independently. Do not implement speculative `hero`/`recommendations` sections if no governed implementation exists.

Record the exact chosen reference-client section IDs and underlying B.1D IDs in the SDD ledger as a ruling.

- [ ] **Step 2: Write failing registry/compatibility tests**

Tests must prove:
- section IDs are stable and unique;
- each section belongs to exactly one governed screen;
- the underlying component/pattern ID exists in the B.1D generated bindings/registry path;
- availability requires the source direction to expose both the screen and required governed component(s);
- incompatible slot/render-contract returns a stable reason;
- no second independent alias/identity registry is introduced.

Example expectation:

```dart
final result = ReviewSectionCompatibility.evaluate(
  runtime: runtime,
  screenId: 'commerce.plp',
  sectionId: section.id,
  sourceDirectionId: 'a',
  baseDirectionId: 'c',
);
expect(result.allowed, isTrue);
```

- [ ] **Step 3: Run tests and confirm failure**

```bash
flutter test test/review/review_section_registry_test.dart test/review/review_section_compatibility_test.dart test/review/review_reference_client_test.dart
```

- [ ] **Step 4: Implement the thin registry and compatibility evaluator**

Rules:
- registry contains reviewable composition boundaries only;
- every definition points back to existing B.1D-governed identity;
- availability derives from actual runtime direction patterns/components;
- compatibility compares the same section identity, slot/render-contract key, and any required component/variant constraints;
- unsupported choices return `allowed: false` with reasons such as `Not present in Direction B` or `Not compatible with this screen layout`.

- [ ] **Step 5: Run focused tests and commit**

```bash
git add apps/prototype_app/lib/review/review_section_registry.dart apps/prototype_app/lib/review/review_section_compatibility.dart apps/prototype_app/lib/registry/prototype_registry.dart packages/agency_flutter_ui apps/prototype_app/test/review/review_section_registry_test.dart apps/prototype_app/test/review/review_section_compatibility_test.dart apps/prototype_app/test/review/review_reference_client_test.dart
git commit -m "feat(review): add governed section compatibility contract"
```

Only include `packages/agency_flutter_ui` files that were actually required; do not stage unrelated files or lockfiles.

---

### Task 3: Canonical decision normalizer

**Files:**
- Create: `apps/prototype_app/lib/review/review_decision_normalizer.dart`
- Create: `apps/prototype_app/test/review/review_decision_normalizer_test.dart`
- Modify: `apps/prototype_app/lib/review/review_state_validator.dart`
- Modify: `apps/prototype_app/test/review/review_state_validator_test.dart`

**Interfaces:**
- Produce a pure normalizer taking `ReviewState`, `PrototypeRuntime`, governed screens/sections and returning a canonical ReviewState v2 or deterministic validation failure.
- Provide helpers to resolve effective screen and section direction.

- [ ] **Step 1: Write failing normalization tests**

Cover:
- explicit screen direction equal to overall is removed;
- section override equal to effective screen is removed;
- empty screen decisions are removed;
- changing parent screen direction removes newly redundant child override;
- overall change revalidates inherited screens;
- stale unavailable/incompatible section override is removed only when caused by a successful parent mutation, while a directly requested invalid section choice is rejected;
- unrelated valid decisions and comments survive unchanged;
- output serialization is deterministic.

- [ ] **Step 2: Run tests and confirm failure**

```bash
flutter test test/review/review_decision_normalizer_test.dart test/review/review_state_validator_test.dart
```

- [ ] **Step 3: Implement pure resolution/normalization functions**

Interfaces should be equivalent to:

```dart
String? effectiveScreenDirection(ReviewState state, String screenId);
String? effectiveSectionDirection(ReviewState state, String screenId, String sectionId);
ReviewState normalizeReviewDecisions(ReviewState state, PrototypeRuntime runtime);
```

Normalization must never mutate the input object or runtime.

- [ ] **Step 4: Extend validator to canonical v2 semantic rules**

Reject persisted v2 states containing redundant screen/section overrides, unknown section IDs, wrong-screen section IDs, unavailable/incompatible sources, or empty screen objects.

- [ ] **Step 5: Run tests and commit**

```bash
git add apps/prototype_app/lib/review/review_decision_normalizer.dart apps/prototype_app/lib/review/review_state_validator.dart apps/prototype_app/test/review/review_decision_normalizer_test.dart apps/prototype_app/test/review/review_state_validator_test.dart
git commit -m "feat(review): normalize hierarchical review decisions"
```

---

### Task 4: ReviewController hierarchical mutation boundary

**Files:**
- Modify: `apps/prototype_app/lib/review/review_controller.dart`
- Modify: `apps/prototype_app/test/review/review_controller_test.dart`
- Modify: `apps/prototype_app/test/review/review_repository_test.dart` only if needed for v2 persisted objects.

**Interfaces:**
- Controller must know enough runtime/governed context to normalize before save.
- Add explicit mutations for set/clear screen override, set/clear section override, reset screen mix, and overall selection with dependent normalization.
- Preserve existing comments/status/round API.

- [ ] **Step 1: Write failing controller tests**

Cover:
- select overall direction auto-persists normalized state;
- `setScreenDirection(screenId, directionId)` and `clearScreenDirection(screenId)`;
- `setSectionDirection(screenId, sectionId, directionId)` and `clearSectionDirection(...)`;
- `resetScreenMix(screenId)` removes screen direction + all section overrides;
- redundant choices are normalized away;
- invalid direct section choice throws/returns deterministic failure;
- rejected mutation leaves controller state identical, repository unchanged, listener count unchanged;
- parent change may successfully prune stale child overrides;
- v1 loaded state becomes v2 and next mutation saves v2.

- [ ] **Step 2: Run focused controller tests and confirm failure**

```bash
flutter test test/review/review_controller_test.dart test/review/review_repository_test.dart
```

- [ ] **Step 3: Refactor mutations through one transactional helper**

Use a pattern equivalent to:

```dart
Future<void> _apply(ReviewState candidate) async {
  final normalized = normalizeReviewDecisions(candidate, runtime);
  final errors = validate(normalized);
  if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  await _repository.save(normalized);
  _state = normalized;
  notifyListeners();
}
```

Important: repository save must occur before adopting/notifying if a save failure could otherwise leave UI state ahead of persistence. Preserve the established zero-side-effect failure contract.

- [ ] **Step 4: Run tests and commit**

```bash
git add apps/prototype_app/lib/review/review_controller.dart apps/prototype_app/test/review/review_controller_test.dart apps/prototype_app/test/review/review_repository_test.dart
git commit -m "feat(review): add transactional screen and section mix mutations"
```

---

### Task 5: Mixed preview composition + scoped source themes

**Files:**
- Create: `apps/prototype_app/lib/review/review_mixed_preview.dart`
- Modify as narrowly required: `apps/prototype_app/lib/registry/prototype_registry.dart`
- Modify as narrowly required: relevant `packages/agency_flutter_ui/lib/patterns/*.dart` or reusable component files
- Create: `apps/prototype_app/test/review/review_mixed_preview_test.dart`
- Modify: `apps/prototype_app/test/review/review_comparison_architecture_test.dart`

**Interfaces:**
- Produce a mixed preview renderer that takes runtime, fixtures, screen ID and normalized ReviewState.
- Base shell/layout comes from the effective screen direction.
- Explicit section override is rendered using that source direction's existing governed widget plus `runtime.themeForDirection(sourceDirectionId)` scoped only around the section.

- [ ] **Step 1: Write failing rendering tests**

Tests must prove:
- no screen override → base uses overall direction;
- explicit screen override chooses that base screen direction;
- inherited section remains under base theme;
- overridden section receives source-direction theme tokens/density/radius without changing sibling/base theme;
- same existing business widget/component is reused, not copied into Review Mode;
- runtime direction definitions/bundle objects are unchanged before/after render;
- an unavailable/incompatible override cannot reach the renderer.

- [ ] **Step 2: Run tests and confirm failure**

```bash
flutter test test/review/review_mixed_preview_test.dart test/review/review_comparison_architecture_test.dart
```

- [ ] **Step 3: Expose the smallest reusable section-render boundary needed**

Prefer extracting existing section-body builders/widgets from current patterns instead of copying their implementation. The review renderer may orchestrate existing widgets but must not become a second business-widget library.

- [ ] **Step 4: Implement `ReviewMixedPreview`**

The widget must remain derived/ephemeral; it must not save state or create a generated runtime asset.

- [ ] **Step 5: Run tests and commit**

```bash
git add apps/prototype_app/lib/review/review_mixed_preview.dart apps/prototype_app/lib/registry/prototype_registry.dart packages/agency_flutter_ui apps/prototype_app/test/review/review_mixed_preview_test.dart apps/prototype_app/test/review/review_comparison_architecture_test.dart
git commit -m "feat(review): render governed mixed screen previews"
```

Again, stage only actually modified shared-UI files.

---

### Task 6: Select + Mix client workspace

**Files:**
- Modify: `apps/prototype_app/lib/review/review_selection.dart`
- Modify: `apps/prototype_app/lib/review/review_shell.dart`
- Modify: `apps/prototype_app/test/review/review_selection_test.dart`
- Modify: `apps/prototype_app/test/review/review_shell_test.dart`
- Create if useful to keep files focused: `apps/prototype_app/lib/review/review_screen_mix_editor.dart`
- Create if useful: `apps/prototype_app/lib/review/review_section_mix_editor.dart`

**Interfaces:**
- Selection becomes the primary decision workspace: overall selection → screen inherit/override → section inherit/override → effective summary → live mixed preview.
- UI calls only ReviewController mutations.

- [ ] **Step 1: Write failing widget tests**

Cover:
- no overall decision remains possible; no silent A selection;
- screen shows `Inherit from overall (X)` when overall exists;
- section shows `Inherit from <Screen> (X)`;
- unavailable/incompatible direction options remain visible but disabled with reason;
- explicit screen/section mutation updates persisted state and preview immediately;
- clearing override removes it from canonical persisted state;
- effective-result summary distinguishes inherited vs explicit values;
- `Reset screen mix` requires confirmation and removes screen + section overrides;
- compact and wide layouts do not overflow;
- navigating/comparing elsewhere does not mutate the saved mix.

- [ ] **Step 2: Run tests and confirm failure**

```bash
flutter test test/review/review_selection_test.dart test/review/review_shell_test.dart
```

- [ ] **Step 3: Implement focused editor widgets and live preview**

Do not read/write serialized maps in widgets. Derive effective values through normalizer helpers/controller state, and invoke controller methods for mutations.

- [ ] **Step 4: Run focused tests and commit**

```bash
git add apps/prototype_app/lib/review/review_selection.dart apps/prototype_app/lib/review/review_shell.dart apps/prototype_app/lib/review/review_screen_mix_editor.dart apps/prototype_app/lib/review/review_section_mix_editor.dart apps/prototype_app/test/review/review_selection_test.dart apps/prototype_app/test/review/review_shell_test.dart
git commit -m "feat(review): add screen and section mix decision workspace"
```

If optional split files were not created, omit them from staging.

---

### Task 7: Reference-client + architecture regressions

**Files:**
- Modify: `apps/prototype_app/test/review/review_reference_client_test.dart`
- Modify: `apps/prototype_app/test/review/review_architecture_test.dart`
- Modify: `apps/prototype_app/test/review/review_comparison_architecture_test.dart`
- Create: `apps/prototype_app/test/review/review_mix_architecture_test.dart`
- Modify generated/reference fixtures only if the approved spec's smallest governed metadata addition is genuinely required and repository validators permit it.

**Interfaces:**
- No new runtime interfaces; this task pins architectural guarantees.

- [ ] **Step 1: Add real `prototype-demo` decision/mix regression tests**

Load `apps/prototype_app/assets/generated/prototype-demo.json` through the existing runtime loader/test path and prove at least one real compatible section mix across actual directions, plus at least one unavailable/incompatible choice.

- [ ] **Step 2: Add source/behavior architecture guards**

Assert:
- runtime/generated bundle bytes are unaffected by ReviewState/mix operations;
- no synthetic mixed runtime output exists;
- B.1D canonical IDs/bindings remain the identity source;
- B.1E theme resolver remains the theme source;
- B.1F refinement notes remain absent from runtime mix logic;
- C.2 comparison code has no decision mutation side effects;
- no approval artifact generation or terminal approval state was added;
- no duplicate full screen implementation exists in `lib/review`;
- no arbitrary component-level mix API was introduced.

- [ ] **Step 3: Run the whole review suite**

```bash
flutter test test/review
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/prototype_app/test/review
git commit -m "test(review): pin C3 mix architecture and reference client"
```

---

### Task 8: Full verification, final independent review, and PR

**Files:**
- Create/update: `docs/superpowers/ledgers/2026-09-16-milestone-c3-select-mix-refinement-ledger.md`
- Update plan/spec only to correct factual inaccuracies discovered during implementation; never rewrite approved scope silently.

- [ ] **Step 1: Run focused C.3 tests**

From `apps/prototype_app`:

```bash
flutter test test/review
flutter test
flutter analyze
flutter build web
```

- [ ] **Step 2: Verify shared Flutter packages**

```bash
cd packages/agency_flutter_ui
flutter analyze
flutter test
cd ../../apps/widgetbook
flutter analyze
flutter test
```

- [ ] **Step 3: Run repository validation from repository root**

```bash
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
```

Run the repository's current canonical workflow/prototype validator commands exactly as defined on main, then:

```bash
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
py -3.12 -m tooling.design_contract.generate_resolved_themes --check
```

- [ ] **Step 4: Inspect working tree before staging**

```bash
git status --short
git diff --check
git diff main...HEAD --stat
```

The existing untracked `pubspec.lock` files must remain uncommitted unless a separately approved lockfile-policy change exists.

- [ ] **Step 5: Dispatch final whole-branch reviewer over `git diff main...HEAD`**

Reviewer must explicitly check:
- v1→v2 migration is deterministic and unambiguous;
- minimal override persistence/inheritance semantics are correct;
- normalization cannot leave redundant/stale state;
- rejected mutations have zero side effects;
- section IDs map back to B.1D authority rather than a parallel design taxonomy;
- compatibility is deterministic and non-ranking;
- base-shell/source-section theme isolation is correct;
- no duplicate business/screen implementations;
- mixed preview is ephemeral and runtime is read-only;
- C.2 comparison remains neutral/display-only;
- no C.4/C.5/BugDrop/screenshot/Visual-AI/backend scope creep;
- behavior-focused tests cover reference client and responsive UI.

Fix any blocker/major finding and re-run affected tests plus final review.

- [ ] **Step 6: Push and open PR against main; do not merge**

```bash
git push -u origin milestone-c3-select-mix-refinement
gh pr create --base main --head milestone-c3-select-mix-refinement --title "Milestone C.3: refine select and mix decisions" --body-file <prepared-pr-body>
```

PR body must include task status, commits, reviewer findings/fixes, rulings/deviations, exact verification results, final branch SHA, deferred items, and explicit statement that C.3 does not generate an approval artifact.

## Self-Review Checklist

Before execution handoff, the plan has been checked against the approved C.3 spec:

- ReviewState v2 + v1 migration: Task 1.
- Governed section IDs + availability/compatibility: Task 2.
- Inheritance/minimal persistence/parent normalization: Task 3.
- Auto-persisted transactional decisions/reset/inherit: Task 4.
- Base shell + source-theme section composition: Task 5.
- Select → screen mix → section mix → live preview UX: Task 6.
- Reference client + B.1B/B.1D/B.1E/B.1F/C.2 regressions: Task 7.
- Full CI-equivalent verification + final review + PR: Task 8.
- Approval, backend, component-level arbitrary mixing, BugDrop, screenshots, Visual AI remain excluded.
