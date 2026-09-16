# Milestone C.3 — Select + Mix Refinement

## Purpose

Milestone C.3 evolves Review Mode from comparison into a governed client decision workspace. Reviewers can choose an overall direction, override individual screens, override governed sections inside those screens, and preview the resulting mixed experience without mutating the runtime bundle, Design Contract, token/theme system, or production approval contract.

C.3 establishes a hierarchical decision model, canonical section identifiers, strict section availability/compatibility rules, deterministic normalization, backward-compatible review-state migration, auto-persisted draft decisions, and a mixed preview that reuses the existing Flutter rendering path.

C.3 does not finalize approval. The output is a valid, normalized draft decision tree suitable for later C.4 review-round workflow and C.5 approval-contract generation.

## Position in the Delivery Flow

```text
B.1B runtime bundle
  ↓
B.1D governed patterns/components
  ↓
B.1E resolved direction themes
  ↓
B.1F reconciled Flutter
  ↓
C.1 Review Mode + review state
  ↓
C.2 Compare Directions + Screens
  ↓
C.3 Select + Mix Refinement
  ↓
C.4 Comments + Review Rounds
  ↓
C.5 Approval Contract
```

## Core Architecture

C.3 extends the existing C.1/C.2 Review Mode architecture rather than introducing a parallel composition system.

```text
ReviewState
   ↓
ReviewController
   ↓
ReviewSectionRegistry
   ↓
SectionCompatibility
   ↓
Decision Normalizer
   ↓
Mixed Preview Composer
   ↓
existing PrototypeRegistry / governed Flutter renderer
```

Authority remains layered:

- B.1B runtime bundle is read-only source data.
- B.1D remains canonical for pattern/component identity and Flutter bindings.
- B.1E remains canonical for semantic tokens and resolved direction themes.
- B.1F refinement notes remain optional non-runtime metadata.
- C.1 ReviewState/ReviewController/ReviewRepository remain the decision/persistence boundary.
- C.2 comparison remains neutral and separate from client decision mutations.

C.3 must not write or derive a synthetic runtime bundle.

## Decision Hierarchy

C.3 introduces one consistent inheritance tree:

```text
overall selected_direction
        ↓
screen override (optional)
        ↓
section override (optional)
```

The effective direction for any level is resolved from the closest explicit override, otherwise inherited from its parent.

### Example

```yaml
version: 2
client_id: prototype-demo
review_round: 1
status: in_review
selected_direction: A
screen_selections:
  home:
    direction: B
    sections:
      home.hero: C
      home.recommendations: A
  search:
    sections:
      search.results-grid: B
comments: []
```

Interpretation:

```text
Overall → A

Home → B
  Hero → C
  Recommendations → A
  All other Home sections → B

Search → inherits A
  Results grid → B
  All other Search sections → A
```

## Review State Versioning and Migration

C.3 changes the persisted shape of `screen_selections`, so the canonical persisted ReviewState version becomes `2`.

### Version 1 legacy shape

```yaml
screen_selections:
  home: A
  search: B
```

### Version 2 canonical shape

```yaml
screen_selections:
  home:
    direction: A
    sections: {}
  search:
    direction: B
    sections: {}
```

The parser should accept valid C.1/C.2 version-1 state where practical and convert it into the in-memory v2 model. The next save serializes only the canonical v2 representation.

No ambiguous or malformed legacy value should be silently coerced.

## Minimal Persistence Rules

Persist only explicit, meaningful overrides.

Rules:

1. If a screen direction equals the inherited overall direction, omit the screen `direction` override.
2. If a section direction equals the effective screen direction, omit the section override.
3. If a screen has no explicit direction and no section overrides, omit the screen entry entirely.
4. Inherited values are computed, not duplicated in persistence.

Example:

```yaml
selected_direction: A
screen_selections:
  home:
    direction: A
    sections:
      home.hero: A
```

normalizes to:

```yaml
selected_direction: A
screen_selections: {}
```

## Screen-Level Inheritance

A screen may explicitly override the overall direction or inherit it.

The UI must expose a clear option such as:

```text
Inherit from overall (A)
Direction A
Direction B
Direction C
```

Choosing `Inherit from overall` removes the screen's explicit `direction` field from persisted state.

If clearing/changing the screen direction changes the effective screen base, all section overrides for that screen must be normalized and revalidated.

## Section-Level Inheritance

Each reviewable section may explicitly override the effective screen direction or inherit it.

The UI must expose a clear option such as:

```text
Inherit from Home (B)
Direction A
Direction B
Direction C
```

Choosing `Inherit from screen` removes that section ID from the persisted `sections` map.

No redundant section override equal to the effective screen direction may remain persisted.

## Governed Canonical Section IDs

C.3 uses governed stable section IDs rather than free-form names or widget-tree-derived identities.

Examples:

```text
home.hero
home.category-strip
home.product-grid
home.recommendations
search.search-header
search.filters
search.results-grid
```

The canonical section IDs are provided through a thin `ReviewSectionRegistry` adapter over existing B.1D-governed pattern/component identity.

The section registry is not a second Design Contract. Its purpose is only to define client-reviewable composition boundaries and labels.

A registry entry may expose metadata equivalent to:

```yaml
id: home.hero
screen: home
label: Hero
source_pattern: commerce.home
source_component: commerce.hero
slot: hero
```

The exact implementation should follow the repository's current B.1D binding/registry model and avoid duplicating identity authority.

## ReviewSectionRegistry Responsibilities

The registry should answer:

- which governed sections are reviewable for a screen;
- stable section ID;
- display label;
- underlying B.1D identity/binding metadata needed for validation;
- whether a direction exposes the section;
- compatibility metadata required for safe mixing.

It must not:

- render UI;
- define a parallel component library;
- invent arbitrary section IDs at runtime;
- override B.1D canonical identity.

## Section Availability

A section override may reference a source direction only if that direction actually exposes the canonical section for the selected screen.

```text
section exists in source direction?
   no → unavailable for mixing
   yes → continue to compatibility validation
```

The UI should visibly disable unavailable choices with a short reason such as:

```text
Not present in Direction C
```

Do not hide unsupported choices when showing the reason is useful to the reviewer.

Do not silently substitute another section.

## Section Compatibility

Simple existence is not sufficient. C.3 must ensure the source section is safe to insert into the base-screen composition.

Compatibility should use existing B.1D metadata where possible and cover at minimum:

- same governed review-section identity;
- compatible slot/composition boundary;
- compatible render contract / expected fixture or data shape;
- any variant/state constraints required by the current Flutter renderer.

Conceptually:

```text
section exists?
  ↓ yes
same governed section identity / compatible slot?
  ↓ yes
render contract compatible?
  ↓ yes
allow override
```

Otherwise the choice is disabled with a neutral reason such as:

```text
Not compatible with this screen layout
```

C.3 must not use compatibility as a scoring/ranking mechanism.

## Mixed Preview Composition

The base screen remains the structural/layout authority.

```text
effective screen direction
        ↓
base screen shell/layout
        ↓
for each governed section:
  inherited → render base section
  overridden → render source-direction section
```

Example:

```text
Home shell → Direction B
Hero → Direction C
Category strip → Direction B
Product grid → Direction B
Recommendations → Direction A
```

The mixed preview is ephemeral derived rendering only. It must not persist a generated runtime or rewrite direction definitions.

## Rendering Boundary

`ReviewSectionRegistry` and compatibility logic provide metadata and validation only.

The actual Flutter screen/section rendering should delegate to the existing governed renderer wherever possible:

```text
ReviewSectionRegistry
  ≠ renderer

MixedPreviewComposer
  ≠ new business-widget library

PrototypeRegistry / existing governed Flutter widgets
  = renderer authority
```

C.3 must not duplicate full screen implementations for each mix.

## Theme Behavior

Theme behavior follows source authority.

```text
base screen shell + inherited sections
→ effective screen direction theme

overridden section
→ source direction's resolved theme
```

For example:

```yaml
home:
  direction: A
  sections:
    home.hero: B
    home.recommendations: C
```

renders:

- Home shell/layout under A's resolved direction theme;
- Hero under B's resolved direction theme;
- Recommendations under C's resolved direction theme;
- all inherited sections under A's resolved direction theme.

Nested theming must be scoped so the source section receives the intended B.1E-resolved theme without contaminating sibling/base sections.

Review chrome remains separate and may use agency/review styling.

## Decision Normalization

Every decision mutation must flow through one canonical normalization path.

```text
user decision
   ↓
validate client/screen/direction/section
   ↓
resolve effective inheritance
   ↓
validate availability
   ↓
validate compatibility
   ↓
remove redundant overrides
   ↓
remove/reject stale invalid overrides
   ↓
validate full ReviewState v2
   ↓
persist
   ↓
notify UI
```

### Core invariant

Every persisted override must be:

```text
explicit + valid + non-redundant + render-compatible
```

## Parent-Change Normalization

When an overall or screen direction changes, dependent section decisions must be re-evaluated.

### Screen parent change example

Before:

```text
home.direction = A
home.hero = B
home.recommendations = C
```

Change:

```text
home.direction → B
```

After normalization:

```text
home.hero override removed
because Hero now inherits B

home.recommendations = C
retained only if C still exposes and is compatible with that section
```

### Overall direction change

When `selected_direction` changes:

- screens that inherit overall immediately resolve to the new direction;
- explicit screen overrides remain if valid;
- section overrides are re-evaluated against each screen's new effective base;
- newly redundant section overrides are removed;
- invalid/incompatible section overrides are rejected or removed according to the mutation semantics;
- unrelated valid decisions remain intact.

## Mutation Failure Semantics

Invalid mutations must not partially change review state.

```text
invalid requested decision
→ no repository save
→ no listener notification
→ current state unchanged
→ deterministic error returned/surfaced
```

This preserves the C.1 controller safety contract.

Where a parent change legitimately invalidates an existing child override, normalization may remove that now-stale child override as part of the successful parent mutation. This behavior must be deterministic and covered by tests.

## Auto-Persisted Draft Decisions

C.3 uses immediate draft persistence through the existing ReviewController/ReviewRepository boundary.

```text
client changes decision
   ↓
validate + normalize
   ↓
persist ReviewState
   ↓
notify
   ↓
UI reflects persisted draft
```

No separate Save button is required.

This is still draft review state, not final approval.

## Select + Mix UX

The existing Selection destination becomes the primary client decision workspace.

Recommended flow:

```text
Compare directions/screens
   ↓
Select overall direction
   ↓
Mix screens
   ↓
Mix sections
   ↓
Preview mixed result
```

### Screen decision presentation

Example:

```text
Home
  Screen direction
    ○ Inherit from overall (A)
    ○ Direction A
    ○ Direction B
    ○ Direction C

  Sections
    Hero
      ○ Inherit from Home (B)
      ○ Direction A
      ○ Direction B
      ○ Direction C
```

Unavailable or incompatible choices must remain visibly disabled with explanatory copy rather than being silently accepted.

### Effective result summary

The UI should make inherited and explicit decisions understandable, for example:

```text
Overall: A

Home
Base: B
Hero: C
Category strip: B (Inherited)
Product grid: B (Inherited)
Recommendations: A
```

The client should not need to read YAML to understand the resulting composition.

## Live Mixed Preview

The Selection workspace should provide a live mixed preview using the normalized current review state.

A valid decision updates the preview immediately after persistence.

Preview/navigation state is not the same as decision state:

- viewing another direction must not change `selected_direction`;
- viewing another screen must not write a mix decision;
- only explicit selection/mix controls mutate ReviewState.

## Reset Behavior

C.3 should provide screen-level reset with confirmation.

`Reset screen mix` should remove:

- explicit screen direction override;
- all section overrides for that screen.

After reset, the screen inherits the overall selected direction.

A global reset of all review decisions is not required for C.3.

## ReviewState / Controller Responsibilities

C.3 extends the existing C.1 ReviewState/ReviewController rather than adding a second decision model.

ReviewController should own mutations equivalent to:

- select overall direction;
- set/clear screen direction override;
- set/clear section direction override;
- reset screen mix;
- normalize dependent overrides after parent changes;
- validate before save;
- persist through ReviewRepository.

The UI must not mutate serialized maps directly.

## Persistence Boundary

C.3 retains the existing persistence abstraction.

The in-memory repository remains sufficient for this milestone unless the existing codebase already has a stronger lightweight implementation.

No permanent backend choice is introduced.

## Validation Requirements

Validation must reject or govern at minimum:

1. unsupported ReviewState version;
2. client/runtime mismatch;
3. invalid overall selected direction;
4. unknown screen ID;
5. unknown explicit screen direction;
6. unknown section ID;
7. section not belonging to the named screen;
8. unknown section source direction;
9. source direction does not expose section;
10. incompatible section source/render contract;
11. redundant explicit screen override in canonical persisted state;
12. redundant section override in canonical persisted state;
13. empty screen decision object in canonical persisted state;
14. duplicate/invalid comments according to existing C.1 rules;
15. invalid review round/status according to existing C.1 rules;
16. persisted state that cannot round-trip deterministically.

Validation findings should remain deterministic and stable-sorted where multiple errors are returned.

## Backward Compatibility

C.3 should preserve current C.1/C.2 review behavior where not superseded by the new hierarchical mix model.

At minimum:

- existing v1 states can be parsed/migrated when valid;
- comments and review rounds survive migration;
- C.2 comparison remains neutral and does not mutate decision state;
- selected direction remains nullable until an explicit overall decision is made;
- normal Prototype Mode remains unaffected.

## Reference Client

Use `client-projects/examples/prototype-demo` as the primary reference client.

The reference-client tests should exercise real direction/screen/section availability and at least one valid section mix across directions.

Where the current reference client does not expose enough cross-direction section compatibility, add the smallest governed fixture metadata needed for a meaningful test without inventing production-only shortcuts.

## Testing

### Model / migration tests

Cover at minimum:

- valid v1 parse/migration;
- canonical v2 parse;
- deterministic v2 serialization;
- comments/round/status preserved across migration;
- malformed legacy values rejected;
- minimal storage normalization.

### Controller / normalizer tests

Cover at minimum:

- overall direction selection;
- screen override set;
- screen inherit/clear;
- section override set;
- section inherit/clear;
- screen reset;
- redundant screen override removed;
- redundant section override removed;
- parent screen change removes newly redundant section overrides;
- overall change revalidates inherited screens;
- invalid/incompatible section mutation rejected;
- rejected mutation causes no persistence or notification;
- unrelated valid decisions survive normalization.

### Registry / compatibility tests

Cover at minimum:

- stable canonical section IDs;
- section belongs to governed screen;
- availability per direction;
- unavailable section direction rejected;
- compatible source allowed;
- incompatible source rejected with deterministic reason;
- no second independent identity registry.

### Widget / UX tests

Cover at minimum:

- Selection screen shows overall selection;
- screen shows `Inherit from overall`;
- section shows `Inherit from screen`;
- effective inherited values are visible;
- unavailable/incompatible direction option disabled with reason;
- valid section override immediately updates persisted state and preview;
- clearing override restores inheritance;
- reset screen mix requires confirmation;
- compact and wide layouts remain usable;
- comparison preview/navigation changes do not mutate decisions.

### Mixed rendering/theme tests

Cover at minimum:

- base screen shell uses effective screen direction;
- inherited section uses effective screen theme;
- overridden section uses source direction resolved theme;
- sibling sections are not contaminated by nested source theme;
- existing PrototypeRegistry/governed Flutter rendering path remains authoritative;
- no duplicated full-screen implementations.

### Architecture regressions

Cover at minimum:

- runtime bundle unchanged by review decisions;
- no synthetic runtime artifact written;
- B.1D binding freshness remains green;
- B.1E resolved-theme freshness remains green;
- B.1F refinement notes remain non-runtime;
- C.2 direction/screen comparison remains neutral;
- no approval artifact generation;
- no BugDrop/GitHub feedback integration;
- no screenshot automation;
- no Visual AI QA;
- no permanent backend dependency;
- normal prototype mode remains functional.

## Error Handling

User-visible decision errors should be concise and actionable, for example:

- `Direction C does not include Hero.`
- `Direction B's Hero is not compatible with this Home layout.`
- `This screen inherits Direction A; no explicit override is stored.`

Internal validation may retain deterministic technical detail needed for tests/debugging.

Do not silently repair arbitrary malformed persisted state. Migration and normalization should only perform explicitly specified deterministic transformations.

## Non-Goals

C.3 does not:

- generate `approved-experience.yaml`;
- finalize approval;
- implement component-level arbitrary mixing;
- create a synthetic runtime bundle;
- modify B.1D canonical IDs;
- modify B.1E source theme contracts as part of review decisions;
- consume B.1F refinement notes as authority;
- implement BugDrop;
- create GitHub issues from comments;
- add screenshot automation;
- add Visual AI QA;
- choose or integrate a permanent review backend;
- implement production authorization;
- implement workflow hardening;
- automatically score, rank, or recommend directions.

## Success Criteria

C.3 is complete when:

1. ReviewState v2 models overall → screen → section decisions.
2. Valid C.1/C.2 v1 review state can migrate deterministically.
3. Only explicit non-redundant overrides are persisted.
4. Screens can inherit overall direction or explicitly override it.
5. Sections can inherit screen direction or explicitly override it.
6. Canonical governed section IDs are stable and backed by B.1D identity.
7. Section source directions are checked for existence and render compatibility.
8. Invalid mix decisions cannot be partially persisted.
9. Parent changes normalize dependent overrides deterministically.
10. Selection decisions auto-persist through ReviewController/ReviewRepository.
11. The Selection workspace clearly communicates inherited vs explicit choices.
12. A live mixed preview renders the base screen plus source-direction section overrides.
13. Base and overridden sections use their correct B.1E-resolved direction themes.
14. Existing governed Flutter rendering is reused rather than duplicated.
15. C.2 comparison remains neutral and separate from decision mutations.
16. Runtime data remains read-only and no synthetic runtime is written.
17. No approval artifact is generated.
18. Repository and Flutter CI remain green.

## Deferred After C.3

```text
C.4 — Comments + Review Rounds refinement
C.5 — Approval Contract / approved-experience.yaml
C.6 — BugDrop / GitHub visual feedback
C.7 — OpenCode refinement loop
D.1 — Screenshot Automation
D.2 — Visual AI QA
D.3 — Widgetbook + Golden expansion
Workflow Hardening
Production Authorization / Productionization
```
