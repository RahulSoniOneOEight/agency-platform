# Milestone C.2 — Compare Directions + Screens

## Purpose

Turn the C.1 comparison framework into a client-ready, **neutral** comparison experience inside the
existing Flutter Review Mode. A reviewer must be able to compare the real client directions and the
same governed screen across directions, understand meaningful differences, and switch between
side-by-side and focused inspection — all using the exact runtime-backed client experience and the
direction-resolved themes.

C.2 helps the client decide. It never decides for them: no scoring, no ranking, no recommendation,
no inferred preference.

## Position in the Delivery Flow

```text
Direction Engine
  ↓
B.1B Runtime Bundle (read-only)
  ↓
B.1D Design Contract ↔ Flutter bindings (authoritative IDs)
  ↓
B.1E Token + Theme Contract (authoritative resolved themes)
  ↓
B.1F Nowa-compatible refinement (non-runtime notes)
  ↓
Flutter prototype
  ↓
C.1 Review Mode (ReviewState / ReviewController / ReviewRepository)
  ↓
C.2 Compare Directions + Screens      ← this milestone
  ↓
later C.3 Select + Mix refinement
  ↓
later C.5 Approval Contract
```

## Core Architecture Rule

Review Mode remains **one Flutter application** with two entry modes. C.2 does not create:

- a second review application, React comparison portal, or duplicate A/B/C trees;
- a second screen registry, runtime bundle, or theme system;
- duplicate direction-specific screen implementations;
- screenshot- or image-based comparison as the primary mechanism;
- automatic scoring, ranking, or direction selection.

C.2 upgrades the **content** of the existing C.1 `Directions` and `Screens` destinations. The five
destinations (`Overview`, `Directions`, `Screens`, `Selection`, `Comments`) and the C.1
`ReviewState` / `ReviewController` / `ReviewRepository` contracts are unchanged.

## Scope

Two first-class comparison surfaces:

1. **Directions comparison** — neutral, metadata-driven comparison of the actual runtime directions.
2. **Screen comparison** — the same governed screen rendered across directions with explicit
   availability handling.

## 1. Directions Comparison

### Purpose

Help a reviewer understand the strategic and experiential difference between the actual client
directions.

### Content

Every field comes from the runtime `PrototypeDirection` object (no copied or hard-coded metadata):

- `id` and `name`;
- `strategicGoal`;
- `primaryJourney`;
- `discoveryModel`;
- `merchandisingModel`;
- `transactionModel`;
- `canonicalDensity`;
- governed `patterns` and `components` where useful (as neutral chips/lists).

### Neutrality (hard requirement)

The comparison must not:

- score or rank directions;
- label one direction as best / recommended / winner;
- infer client preference from viewing behaviour;
- order directions by any derived quality signal.

Deterministic order is the runtime's declared order (`runtime.allowedDirections`), which is
validated to match `runtime.directions`. No sorting by heuristic.

### Responsive behaviour

- **Wide:** all direction panels side by side.
- **Compact:** one active direction panel plus an explicit direction switcher.

## 2. Screen Comparison

### Purpose

Compare the **same** governed screen across directions.

```text
Search
  A | B | C

Home
  A | B | C
```

### Rendering contract

Each supported panel renders exactly:

```text
runtime
  + selected direction (PrototypeDirection)
  + governed screen ID (canonical pattern ID)
  + runtime.themeForDirection(directionId)
```

through the existing C.1 path: `ReviewComparisonHost` → `PrototypeRegistry.buildPattern` wrapped in
`Theme(data: AgencyTheme.light(runtime.themeForDirection(directionId)))`. No screen code is
duplicated.

### Availability rule (resolves the C.1 unioned-screen finding)

For each `(screen, direction)` pair, availability is **explicit**:

- **SUPPORTED** — `direction.patterns` contains the canonical screen ID → render the real screen.
- **UNAVAILABLE** — the direction does not declare the screen → render a neutral governed state:
  `This screen is not part of Direction <ID>`.

Rules:

- never render a screen under a direction that does not declare it;
- never silently substitute another screen;
- never fall back to the runtime default direction for a missing pair.

The union of governed screens (from `ReviewScreenRegistry.screenIdsFor`) still defines which screens
the reviewer may pick; availability is evaluated per direction.

## Comparison Modes

Both surfaces share one responsive primitive:

| Mode | When | Layout |
|------|------|--------|
| Side-by-side | wide viewport (per-surface breakpoint) | all panels in a row |
| Focused / switcher | compact viewport, or explicit focus toggle on wide | one active panel + direction switcher |

Rules:

- responsive by viewport width; never force three tiny columns on a phone;
- the **same panel widgets** are used in both modes — only arrangement changes;
- on wide screens the screen-comparison surface offers an explicit side-by-side ↔ focused toggle.

## Preview State vs Decision State

C.1 finding addressed: a restored `selectedDirection` should sensibly seed the initial preview.

Rules:

- the initial preview/display direction is `controller.state.selectedDirection ?? runtime.defaultDirection`;
- once the reviewer explicitly changes the preview, the local preview wins for that session;
- the runtime default is used **only** when no persisted selection exists;
- preview changes never write `selected_direction`;
- selecting a client preference still requires the explicit Selection control / explicit action.

Display state and decision state stay separate.

## Review State

C.2 adds **no new persisted state**.

- `ReviewState` is unchanged; the C.1 contract (`version`, `client_id`, `review_round`, `status`,
  `selected_direction` nullable, `screen_selections`, `comments`) remains compatible.
- Active comparison screen/direction is ephemeral UI state (local to the comparison widgets).
- No temporary navigation state is written into `ReviewState`.

## Component Architecture

Create focused components under `apps/prototype_app/lib/review/`:

| File | Responsibility |
|------|----------------|
| `review_screen_availability.dart` | Governed availability adapter: deterministic direction order, governed screen list, `isSupported(direction, screen)`, stable labels. Delegates to `ReviewScreenRegistry`; does **not** define a second registry. |
| `review_direction_summary.dart` | One direction's neutral metadata card (`ReviewDirectionSummary`), rendered from a `PrototypeDirection`. |
| `review_direction_comparison.dart` | Directions destination: builds neutral direction panels + explicit select action. |
| `review_comparison_layout.dart` | Responsive primitive (`ReviewComparisonLayout` + `ReviewComparisonPanel`): side-by-side vs focused/switcher; shared panel widgets. |
| `review_screen_comparison.dart` | Screens destination: screen selector, per-direction panels via `ReviewComparisonHost`, unavailable state. |

Modify:

- `apps/prototype_app/lib/review/review_shell.dart` — wire the two new surfaces into the `Directions`
  and `Screens` destinations.

Supersede/remove (avoid duplicate implementations):

- `review_directions.dart` and `review_screens.dart` (their behaviour is replaced by the new
  comparison surfaces). Their tests are migrated.

## Visual Design

Client-ready consulting review surface:

- clear hierarchy: surface header → persistent comparison context → panels;
- consistent panel/card styling with visible direction identity (id + name);
- readable, compact metadata (no overwhelming walls of text);
- persistent comparison context (screen selector / direction context) that does not scroll away;
- strict theme isolation: review chrome uses agency/review styling; **inside each client panel the
  exact direction-resolved theme is applied**, and review theme values must not leak into the
  evaluated surface.

## Selection Integration

- Direction comparison may expose an explicit `Select this direction` action per direction.
- If present, it calls the existing `ReviewController.selectDirection` path and is explicit.
- Viewing/previewing a direction never changes `selected_direction`.
- Screen comparison exposes no selection action; viewing screen B never assigns screen selection B.
- Comparison and decision remain separate concepts.

## Comments Integration

Out of scope for C.2. The C.1 `Comments` destination and comment state are unchanged. No new
comment architecture, BugDrop, GitHub issues, screenshots, or Visual AI.

## Authority Protection

- **B.1B** — runtime bundle remains read-only; comparison reads only.
- **B.1D** — canonical pattern/component IDs and bindings remain authoritative; comparison uses
  `PrototypeRegistry` / `ReviewScreenRegistry`; no review-only aliases.
- **B.1E** — direction-resolved themes remain authoritative for evaluated panels.
- **B.1F** — refinement notes remain non-runtime and are not consumed.
- **C.1** — `ReviewState`, `ReviewController`, `ReviewRepository`, and the governed screen registry
  remain authoritative; `selected_direction` stays nullable until explicitly selected; no silent
  Direction A.

## Validation / Guards

- Availability is derived from `direction.patterns` only; unknown/unsupported pairs never render a
  client screen.
- Comparison direction order equals `runtime.allowedDirections`.
- No ranking/recommendation vocabulary is rendered.
- No new persisted state, no file I/O, no approval artifact generation.

## Testing

### Model / unit tests

- deterministic direction ordering equals `runtime.allowedDirections` (2 and 3 directions);
- screen availability per direction (`isSupported`);
- governed screen list is the sorted union (delegated to `ReviewScreenRegistry`);
- unavailable pair reported explicitly (no substitution);
- restored `selectedDirection` seeds the initial preview;
- preview changes do not mutate `selected_direction`;
- runtime default used only when no selection exists.

### Widget tests

- Directions destination renders actual runtime directions and their runtime metadata;
- wide direction comparison shows side-by-side panels;
- compact direction switcher shows one active panel;
- screen comparison renders the same screen across directions via `ReviewComparisonHost`;
- unavailable direction/screen pair shows the neutral unavailable state;
- client panel uses the direction-resolved theme (`AgencyTheme.light(runtime.themeForDirection(id))`);
- selection is unchanged when switching preview;
- explicit `Select this direction` still routes through `ReviewController`;
- review state survives navigation between comparison surfaces.

### Architecture / regression tests

- no duplicate screen implementation; comparison uses `PrototypeRegistry` / `ReviewComparisonHost`;
- B.1B runtime data remains untouched (instance identity);
- B.1D canonical IDs remain authoritative;
- B.1E direction themes remain authoritative;
- B.1F notes remain non-runtime;
- C.1 `ReviewState` contract remains compatible;
- no approval artifact generation;
- **reference client:** the actual generated bundle
  (`apps/prototype_app/assets/generated/prototype-demo.json`) yields the expected direction order,
  per-direction screen availability (`commerce.search` is declared only by `a`; `commerce.home`
  only by `c`; `b`/`c` show the neutral unavailable state for `search`), and direction-resolved
  themes that differ in density / section spacing / card radius (the reference bundle shares one
  brand primary across directions).

## Reference Client

`client-projects/examples/prototype-demo`, consumed through its committed generated bundle
`apps/prototype_app/assets/generated/prototype-demo.json`.

## CI / Verification

- focused C.2 Dart/Flutter tests;
- full `apps/prototype_app` tests + `flutter analyze`;
- `packages/agency_flutter_ui` and `apps/widgetbook` analyze/tests;
- `flutter build web` for `apps/prototype_app`;
- repository Python validation, knowledge/workflow/prototype validators;
- B.1D bindings and B.1E resolved-themes freshness (`--check`);
- final independent whole-branch review against `git diff main...HEAD`.

## Non-Goals

C.2 does not implement:

- approval contract / `approved-experience.yaml` generation;
- automatic direction scoring/ranking/recommendation;
- BugDrop, GitHub issues, screenshot automation, Visual AI QA;
- a permanent backend or new persistence;
- a second registry/theme/runtime/app;
- C.3 selection refinement, C.4 comment/round workflow, C.5 approval.

## Success Criteria

1. Directions comparison shows real runtime directions with real runtime metadata, neutrally.
2. Screen comparison renders the same governed screen across directions via the existing host.
3. Unsupported `(screen, direction)` pairs show a neutral unavailable state and never render a
   substituted screen.
4. Wide viewports show side-by-side panels; compact viewports show a switcher + one active panel.
5. Restored `selectedDirection` seeds the initial preview; runtime default is used only without a
   selection.
6. Preview/viewing never mutates `selected_direction`; explicit selection still uses
   `ReviewController`.
7. No new persisted state; C.1 `ReviewState` stays compatible.
8. B.1B/D/E/F and C.1 authority remain intact.
9. Reference-client availability and theme behaviour are covered by regression tests.
10. Repository and Flutter CI remain green.

## Design Decisions & Alternatives (brainstorming record)

| Decision | Chosen | Rejected alternative | Why |
|----------|--------|----------------------|-----|
| Surface placement | Upgrade existing `Directions`/`Screens` destinations | Add new tabs | Keeps C.1 navigation contract; avoids destination sprawl. |
| Screen identity | Reuse `ReviewScreenRegistry` union | New C.2 registry | One governed registry; avoids drift. |
| Availability source | `direction.patterns` | Render any screen for any direction | Prevents false rendering; resolves C.1 finding. |
| Unavailable UX | Neutral message, no substitution | Fallback to another direction/screen | Neutrality and truthfulness. |
| Preview state | Ephemeral local UI state | Persist active comparison in `ReviewState` | Keeps decision state clean. |
| Restored selection seeding | Derive preview as `selected ?? default` until user previews | One-way `initState` seed only | Works with async load; keeps display/decision separate. |
| Layout | One responsive primitive, shared panel widgets | Separate mobile/desktop widgets | No forked rendering logic. |
| Mode switch | Responsive + explicit focus toggle on wide | Manual-only or auto-only | Satisfies "switch between side-by-side and focused where useful". |
| Selection in comparison | Explicit per-direction `Select this direction` | Auto-select on view | Explicit only; no silent selection. |
| Comments in comparison | Out of scope | Contextual comment capture | Avoid C.4 scope creep. |
| Ranking | None | Score/rank metadata | Comparison must not decide. |

## Next Milestones

```text
C.3 — Select + Mix refinement
C.4 — Comments + Review Rounds
C.5 — Approval Contract
C.6 — BugDrop / GitHub visual feedback
C.7 — OpenCode refinement loop
```
