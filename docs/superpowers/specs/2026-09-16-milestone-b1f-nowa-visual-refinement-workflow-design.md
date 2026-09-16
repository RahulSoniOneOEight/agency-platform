# Milestone B.1F — Nowa-Compatible Visual Refinement Workflow

## Purpose

Define a governed operating workflow for using Nowa as an optional visual Flutter workbench between OpenCode-generated Flutter and client review, without creating a second source of truth or weakening the Design Contract / B.1E token and theme authority.

B.1F is intentionally a lightweight workflow milestone rather than a large software subsystem.

## Position in the Delivery Flow

```text
Client input
  ↓
Layer 4 / Direction Engine
  ↓
B.1B Runtime Bundle
  ↓
B.1D Design Contract ↔ Flutter bindings
  ↓
B.1E Token + Theme Contract
  ↓
OpenCode-generated Flutter
  ↓
Nowa visual refinement (optional)
  ↓
OpenCode reconciliation
  ↓
GitHub commit + CI
  ↓
Client-ready Flutter Web
  ↓
Flutter Review Mode (later milestone)
```

## Core Role

Nowa is a **Visual Flutter Workbench**.

It may accelerate:

- spacing and layout refinement;
- responsive tuning;
- typography presentation;
- visual hierarchy;
- component composition;
- section ordering;
- card/image proportions;
- direction-level visual differentiation;
- workshop-time visual changes;
- last-mile prototype polish.

Nowa does not own:

- product/UX strategy;
- Direction Engine decisions;
- canonical component/pattern IDs;
- Design Contract authority;
- token/theme precedence;
- client review/approval state;
- production authorization;
- API/data architecture;
- workflow state.

## Source-of-Truth Rule

GitHub remains the only persistent source of truth.

No retained decision may exist only inside Nowa.

```text
Nowa edit
  ↓
Flutter/config diff
  ↓
OpenCode reconciliation
  ↓
GitHub commit
  ↓
CI validation
```

Any Nowa-only state that cannot be represented as ordinary repository code/config is non-authoritative and must not be required to reproduce the prototype.

## Same-Codebase Rule

Nowa must operate on the same Flutter repository/project used by OpenCode and CI.

B.1F must not introduce:

- a parallel prototype app;
- duplicated A/B/C Flutter codebases;
- exported throwaway code as the primary review artifact;
- a Nowa-specific design system that diverges from `design-contract/`.

## Refinement Classification

Every retained Nowa change must be classified during reconciliation.

Allowed classifications:

1. `semantic_token`
   - Existing B.1E semantic token already governs the visual decision.
   - Action: change the appropriate theme/token/client/direction override rather than leave an arbitrary widget literal.

2. `client_override`
   - Intentional and client-specific visual decision.
   - Action: represent it in an approved client-level semantic/config boundary where supported.

3. `direction_override`
   - Intentional visual difference between experience directions.
   - Action: keep it within approved direction-level semantic overrides.

4. `reusable_candidate`
   - Potentially valuable across multiple clients or patterns.
   - Action: propose promotion into B.1E semantic tokens, the Design Contract, shared Flutter UI, or a reusable preset.

5. `implementation_detail`
   - Legitimate local Flutter implementation detail that does not represent reusable/client semantic intent.
   - Action: keep in Flutter code, document only when material.

6. `reject`
   - Change bypasses architecture, duplicates an existing contract, introduces unsupported one-off styling, or cannot be justified.
   - Action: revert or replace with governed implementation.

## Classification Decision Flow

```text
Nowa change
   ↓
Does an existing semantic token govern it?
   ├─ yes → semantic_token
   └─ no
       ↓
Is it intentionally client-specific?
   ├─ yes → client_override
   └─ no
       ↓
Is it direction-specific?
   ├─ yes → direction_override
   └─ no
       ↓
Is it reusable across clients/patterns?
   ├─ yes → reusable_candidate
   └─ no
       ↓
Is it a justified implementation detail?
   ├─ yes → implementation_detail
   └─ no → reject
```

## B.1E Protection Rules

B.1F must preserve the Token + Theme Contract.

Examples:

- spacing change → semantic spacing token where applicable;
- radius change → semantic radius token;
- brand color change → client brand override;
- density change → canonical `compact | normal | spacious` semantics;
- motion timing change → semantic motion token;
- typography change → semantic typography/theme configuration;
- component variant behavior → Design Contract / shared Flutter component change.

Nowa must not become a path for silently introducing duplicate hard-coded styling that conflicts with governed values.

## B.1D Protection Rules

B.1F must preserve canonical component/pattern IDs and governed Flutter bindings.

Nowa may visually rearrange or configure components, but must not invent a second naming/identity layer for components or patterns.

If a visual refinement implies a new reusable component variant, OpenCode should propose a Design Contract change rather than encode an unnamed permanent variant only in client Flutter code.

## Workshop Mode

The intended agency workshop loop is:

```text
Client requests visual change
  ↓
Operator refines in Nowa
  ↓
Preview immediately
  ↓
Client accepts / rejects
  ↓
If accepted: OpenCode reconciles the diff
  ↓
Governed token/config/component/code representation
  ↓
Tests + CI
  ↓
Commit
```

Nowa can therefore be used for fast live exploration, but only reconciled/committed changes become authoritative.

## Refinement Notes

B.1F may introduce a lightweight, optional refinement note under the client prototype directory to make reconciliation explicit.

Recommended path:

`client-projects/<client>/prototype/refinement-notes.yaml`

Recommended shape:

```yaml
version: 1
changes:
  - id: home-hero-height
    screen: home
    subject: hero
    change: reduce hero height
    classification: client_override
    status: reconciled
    target: theme.spacing.section

  - id: compact-card-spacing
    component: commerce.product-card
    change: tighter compact spacing
    classification: reusable_candidate
    status: proposed
    target: design-contract
```

This file is not required to render the prototype and must not become runtime authority. Its purpose is to record material visual decisions that need reconciliation or promotion.

Allowed statuses:

- `observed`
- `accepted`
- `reconciled`
- `proposed`
- `rejected`

## OpenCode Reconciliation Responsibilities

After a Nowa refinement session, OpenCode should:

1. inspect the Git diff;
2. identify visual changes;
3. classify each material change;
4. replace arbitrary literals with existing semantic tokens/configuration where appropriate;
5. promote reusable candidates only through normal governed contract changes;
6. ensure client-specific changes do not leak into agency-wide defaults;
7. run B.1D/B.1E validation;
8. run Flutter analyze/tests/build as appropriate;
9. commit only the reconciled result.

## Validation Strategy

B.1F does not require a complex Nowa API integration.

Repository support should remain lightweight. Validation may cover:

- refinement-note schema if the note file is introduced;
- allowed classification/status enums;
- referenced canonical component/pattern IDs where supplied;
- duplicate refinement IDs;
- deterministic validation error ordering;
- prohibition on treating refinement notes as runtime input;
- documentation or validation checks that preserve B.1D/B.1E authority.

B.1F should not attempt to prove that every Flutter style literal originated in Nowa or automatically infer the full semantic meaning of arbitrary diffs.

## Git / Branch Workflow

Recommended refinement session:

```text
feature/client prototype branch
  ↓
OpenCode baseline commit
  ↓
Nowa edits same working tree
  ↓
OpenCode reviews git diff
  ↓
reconciliation commit(s)
  ↓
existing CI
```

Do not commit directly from a visual workbench without reconciliation when the changes affect governed semantics.

## CI Boundary

Existing B.1D and B.1E checks remain authoritative.

A reconciled Nowa change must continue to pass:

- repository validation;
- Flutter binding freshness;
- resolved-theme freshness;
- relevant Python validation tests;
- Flutter analyze;
- Flutter tests;
- Flutter Web build where the prototype is client-facing.

## Documentation

Add an operator-facing guide explaining:

- when to use Nowa;
- what it is allowed to change;
- how to open/work on the same Flutter project;
- how to hand control back to OpenCode;
- how to classify changes;
- how to reconcile changes into B.1D/B.1E contracts;
- how to handle workshop changes;
- what must never remain Nowa-only.

## Non-Goals

B.1F does not:

- build Flutter Review Mode;
- integrate BugDrop;
- add client approval flows;
- implement screenshot automation;
- implement Visual AI QA;
- replace OpenCode as implementation orchestrator;
- replace GitHub as source of truth;
- expose Nowa as production runtime dependency;
- build a custom visual editor;
- create a bidirectional Nowa API unless future evidence shows a clear need;
- automatically convert every arbitrary Flutter visual diff into semantic tokens.

## Success Criteria

B.1F is complete when:

1. Nowa's role is formally defined as optional visual Flutter workbench.
2. The same Flutter codebase is used by OpenCode, Nowa, CI, and later client review.
3. GitHub remains the only persistent source of truth.
4. No Nowa-only state is required to reproduce or build the prototype.
5. A documented reconciliation classification exists for material visual changes.
6. B.1D canonical component/pattern authority is preserved.
7. B.1E semantic token/theme authority is preserved.
8. Client-specific visual decisions remain client-specific.
9. Reusable visual learnings have a governed promotion path.
10. Optional refinement notes, if implemented, are explicitly non-runtime metadata and validated deterministically.
11. OpenCode has a repeatable post-Nowa reconciliation checklist.
12. Existing repository + Flutter CI remains green.
13. The resulting Flutter Web prototype is ready to feed into the next milestone: Flutter Review Mode.

## Next Milestone

After B.1F, build Flutter Review Mode for:

- direction comparison;
- screen comparison;
- select/mix;
- comments;
- review rounds;
- approval contract generation.
