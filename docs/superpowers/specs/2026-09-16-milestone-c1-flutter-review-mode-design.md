# Milestone C.1 — Flutter Review Mode

## Purpose

Introduce a client-facing review layer inside the existing Flutter prototype so clients and the agency can inspect, compare, select, mix, and comment on experience directions without creating a second application or modifying the canonical design/runtime contracts.

C.1 establishes the review shell, state model, navigation, comparison framework, selection/mix state, comments, review rounds, and persistence boundary. Final approval contract generation remains a later milestone.

## Position in the Delivery Flow

```text
Client input
  ↓
Direction Engine
  ↓
B.1B Runtime Bundle
  ↓
B.1D Design Contract ↔ Flutter bindings
  ↓
B.1E Token + Theme Contract
  ↓
B.1F Nowa-compatible refinement
  ↓
Flutter prototype
  ↓
C.1 Review Mode
  ↓
review rounds / select / mix / comments
  ↓
later C.5 Approval Contract
  ↓
approved-experience.yaml
```

## Core Architecture Rule

Review Mode lives inside the same Flutter application used for the prototype.

```text
same Flutter app
   ├─ Prototype Mode
   └─ Review Mode
```

C.1 must not create:

- a second review application;
- duplicated A/B/C Flutter codebases;
- a React review portal;
- an alternate runtime bundle;
- an alternate Design Contract;
- an approval source of truth separate from the later approved-experience contract.

## Entry Point

Review Mode should be addressable independently from normal prototype navigation.

Preferred web route/query form:

```text
/review?client=<client-id>
```

If the current Flutter routing model does not support a literal `/review` route cleanly, an equivalent deterministic URL contract may be used, but the client ID must be explicit and review mode must not depend on hidden local state.

Direction selection during review should use the same runtime bundle and the actual client directions already produced by B.1B.

## Review Navigation

C.1 introduces the following review destinations:

1. Overview
2. Directions
3. Screens
4. Selection
5. Comments

A responsive navigation shell may present these as tabs, rail, drawer, or another platform-appropriate pattern, but all review sections must be directly reachable and must preserve current review state.

## Review State Model

Review state is separate from the runtime bundle and separate from `approved-experience.yaml`.

Recommended canonical shape:

```yaml
version: 1
client_id: prototype-demo
review_round: 1
status: in_review
selected_direction: B
screen_selections:
  home: A
  search: B
  product_detail: A
  trade_dashboard: C
comments:
  - id: review-001
    scope: general
    text: Prefer direction A visual style but B search experience.
  - id: review-002
    scope: screen
    screen: home
    direction: A
    text: Reduce hero height.
```

### Required top-level fields

- `version`
- `client_id`
- `review_round`
- `status`
- `selected_direction`
- `screen_selections`
- `comments`

### Statuses for C.1

C.1 should support only review lifecycle values needed before approval, such as:

- `in_review`
- `needs_revision`
- `ready_for_final_review`

Approval-specific terminal states remain out of scope for C.1.

## Direction Selection

A reviewer may select one preferred overall direction.

The selected value must:

- correspond to a real direction in the loaded runtime bundle;
- be nullable until the reviewer chooses one;
- never silently default to direction A merely because A is listed first.

The default review display may use the runtime bundle's declared `default_direction`, but that display default is not equivalent to client selection.

## Screen-Level Mix

Review Mode must support per-screen direction selection.

Example:

```yaml
screen_selections:
  home: A
  search: B
  product_detail: A
  trade_dashboard: C
```

This is review-state metadata only. It must not rewrite the runtime direction definitions.

The screen identifiers should come from a governed/known prototype screen registry rather than arbitrary free-form keys where the existing architecture provides such a registry.

## Comments

C.1 supports lightweight comments without introducing the later BugDrop/GitHub feedback integration.

Required scopes:

- `general`
- `screen`

A comment record should contain:

- unique `id`;
- `scope`;
- `text`;
- optional `screen` where scope is `screen`;
- optional `direction` when comment concerns a specific direction;
- optional stable metadata needed for future review rounds.

Comments must be stored as review state and must not mutate runtime/design contracts.

## Review Rounds

C.1 introduces an integer `review_round` starting at `1`.

Review rounds provide continuity for later iterative client review:

```text
Round 1
  ↓
refinement
  ↓
Round 2
  ↓
refinement
  ↓
Final Review
```

C.1 must establish the state field and deterministic increment/update semantics. Full workflow hardening and approval transitions remain later work.

## Comparison Framework

C.1 should create the reusable framework needed for later richer C.2 comparison features.

### Direction comparison

Users should be able to switch or compare actual client directions using the same runtime-backed screens.

### Screen comparison

The architecture must support comparing the same screen across directions, even if C.1 starts with a simple side-by-side or switcher implementation.

The comparison system must reuse existing prototype rendering rather than duplicate screen implementations.

## State Persistence Boundary

C.1 must define a persistence abstraction but should avoid coupling the milestone to a full backend platform decision.

Recommended interface responsibilities:

- load review state by client;
- save review state;
- update selection;
- update per-screen mix;
- add/update comments;
- advance review round.

A lightweight in-memory/local/test implementation is acceptable for C.1 if the interface is explicit and replaceable by a persistent backend in a later milestone.

The review UI should not directly own storage implementation details.

## Runtime Contract Protection

The B.1B runtime bundle remains read-only input to Review Mode.

Review Mode may consume:

- `client_id`;
- `default_direction`;
- actual `directions`;
- fixtures;
- resolved `theme` / `direction_themes`;
- resources;
- review metadata already intended for display constraints.

Review Mode must not rewrite runtime bundle files as a way to persist review decisions.

## B.1D Protection

Canonical pattern/component IDs and Flutter bindings remain governed by B.1D.

Review Mode must reuse the existing Flutter registry/bindings and must not create review-only component identity aliases.

## B.1E Protection

Review Mode must render using the same resolved token/theme system as the prototype.

It must not introduce a parallel review theme that changes the client experience under evaluation. Review chrome may use agency/review semantics, but the reviewed client screen itself must use the same client/direction resolved theme as normal prototype mode.

## B.1F Protection

Review Mode evaluates the reconciled Flutter output after any Nowa refinement.

It must not consume `refinement-notes.yaml` as runtime authority and must not require Nowa-specific state.

## Review UI Responsibilities

C.1 should provide:

- review-mode app shell;
- current client identity;
- current review round/status;
- direction selector/navigation;
- screen selector/navigation;
- overall direction selection control;
- per-screen mix control;
- comment capture/display;
- comparison host capable of rendering the selected client/direction/screen;
- clear exit/back-to-prototype path where appropriate.

## Review UI Non-Responsibilities

C.1 does not:

- generate final approval artifacts;
- create BugDrop tickets;
- create GitHub issues;
- run screenshot automation;
- run Visual AI QA;
- perform production authorization;
- mutate Design Contract or token/theme source files;
- decide which direction is "best" autonomously.

## Validation

Validation should reject or govern at minimum:

1. unsupported review-state version;
2. client ID mismatch between review state and loaded runtime bundle;
3. selected direction not present in runtime directions;
4. screen mix direction not present in runtime directions;
5. duplicate comment IDs;
6. unknown comment scope;
7. screen-scoped comment missing screen ID;
8. invalid review round (`< 1`);
9. unknown review status;
10. invalid/unknown screen identifiers where a governed screen registry is available;
11. persisted state that cannot be deterministically serialized/deserialized.

Errors should be deterministic and stable-sorted where validation returns multiple findings.

## Testing

### Dart / Flutter model tests

Cover at minimum:

- valid review-state parsing;
- invalid version/status/round;
- selected direction validation;
- mixed screen selection validation;
- comment validation;
- deterministic serialization;
- persistence interface behavior;
- review round advancement.

### Flutter widget tests

Cover at minimum:

- review entry point loads the requested client;
- navigation between review sections;
- actual runtime directions are displayed;
- selecting an overall direction updates review state;
- selecting a screen-specific direction updates mix state;
- adding a general comment;
- adding a screen comment;
- switching reviewed direction preserves state;
- client screen rendering still uses the client's resolved theme;
- no silent selection of direction A.

### Regression tests

Cover at minimum:

- normal prototype mode still works;
- B.1D Flutter binding tests remain green;
- B.1E resolved-theme tests remain green;
- B.1F refinement notes remain non-runtime;
- runtime bundle generation remains unchanged by review state;
- approval artifact generation is not introduced accidentally in C.1.

## Reference Client

Use `client-projects/examples/prototype-demo` as the C.1 reference client unless the implementation review identifies a stronger existing canonical fixture.

The reference client should be sufficient to exercise:

- multiple directions;
- multiple known screens;
- one overall selection;
- a mixed screen selection;
- general and screen comments;
- at least one review-round transition.

## CI / Verification

Before merge, verify at minimum:

- focused C.1 Dart/Flutter tests;
- full repository Python validation;
- B.1D binding freshness;
- B.1E resolved-theme freshness;
- Flutter analyze for prototype app, shared UI package, Widgetbook;
- Flutter tests for all three packages;
- Flutter Web build;
- final whole-branch review.

## Non-Goals

C.1 does not:

- implement the final Approval Contract;
- write `approved-experience.yaml` from review state;
- integrate BugDrop;
- create GitHub issues from feedback;
- implement screenshot automation;
- implement Visual AI QA;
- implement workflow hardening;
- choose Supabase or another permanent backend if a persistence abstraction is sufficient;
- replace the existing prototype app;
- create a separate web/admin review application.

## Success Criteria

C.1 is complete when:

1. Review Mode exists inside the same Flutter app as the prototype.
2. A deterministic review entry point can load a specific client.
3. Actual runtime directions are available to the review UI.
4. Review state is explicitly modeled and validated.
5. One overall direction can be selected without silent defaults.
6. Per-screen direction mixing can be recorded.
7. General and screen comments can be recorded.
8. Review rounds are represented and can advance deterministically.
9. A persistence interface separates review UI from storage implementation.
10. Review screens reuse the existing prototype renderer rather than duplicate client screens.
11. B.1B runtime data remains read-only.
12. B.1D/B.1E/B.1F authority remains intact.
13. Normal prototype mode remains functional.
14. Repository and Flutter CI remain green.
15. The result provides the foundation for C.2–C.5 comparison, selection refinement, review rounds, and final approval.

## Next Milestones

After C.1:

```text
C.2 — Compare Directions + Screens
C.3 — Select + Mix refinement
C.4 — Comments + Review Rounds
C.5 — Approval Contract
C.6 — BugDrop / GitHub visual feedback
C.7 — OpenCode refinement loop
```
