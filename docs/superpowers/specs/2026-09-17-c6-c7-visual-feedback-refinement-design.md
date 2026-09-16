# C.6–C.7 Visual Feedback & Refinement Design

## Purpose

C.6 and C.7 extend the review system with provider-neutral visual evidence and a governed OpenCode refinement loop. C.6 normalizes screenshot annotations into the same unified feedback model created in C.4. C.7 executes reviewer-created refinement batches, records validation evidence, and may move feedback from `open` to `addressed`, but never to `resolved`.

The system must remain auditable and must not allow agentic refinement to bypass reviewer authority, approval gates, C.3 design authority, or runtime/B.1D/B.1E implementation authority.

## Core Architecture

Use the shared authority model:

```text
ReviewState
  → current decisions + active review state

FeedbackRecord
  → stable feedback identity + lifecycle/history authority

RefinementBatch
  → execution/audit authority for OpenCode changes

ApprovalSnapshot
  → immutable approval authority
```

C.6 adds provider-neutral visual attachments to FeedbackRecord. C.7 adds RefinementBatch and cross-domain orchestration through ReviewCoordinator.

## Visual Feedback Model

Visual feedback is not a second comment system. It uses the same `FeedbackRecord` model with:

```text
scope: visual_annotation
```

A visual item may target:

- a whole governed screen;
- a governed section;
- a free-form annotated region.

The feedback record remains authoritative. The screenshot/annotation is evidence/context.

## Normalized Visual Attachment

Conceptual payload:

```yaml
visual_attachment:
  screenshot_ref: review-home-round-2
  viewport:
    width: 1440
    height: 1200
  context:
    client_id: prototype-demo
    review_round: 2
    screen: commerce.home
    effective_direction: b
    source_commit_sha: abc123
  annotation:
    x: 0.42
    y: 0.31
    width: 0.18
    height: 0.12
  provider:
    name: bugdrop
    external_ref: provider-item-123
```

Coordinates are normalized to `0..1` so annotations remain meaningful across image transport/storage implementations.

Rules:

- screenshot reference is immutable once attached;
- coordinates must remain within valid normalized bounds;
- section reference is optional for free-form annotation;
- screenshot context should include enough information to reproduce the reviewed surface where available;
- provider-specific metadata is isolated under provider metadata and must not leak into core lifecycle semantics.

## Provider-Agnostic Adapter

Define a small provider boundary conceptually equivalent to:

```text
VisualFeedbackProvider
  ingest/capture provider annotation
  ↓
  normalize payload
  ↓
  return provider-neutral visual attachment
```

BugDrop is the first adapter, not an architectural dependency.

Provider implementations must not:

- change feedback status;
- classify blocking/non-blocking;
- resolve/reopen feedback;
- create refinement batches automatically;
- mutate ReviewState decisions;
- mutate approval history.

The adapter may validate provider payloads and return typed ingestion errors.

## Refinement Batch Model

Reviewer-created batches group related feedback for implementation.

Lifecycle:

```text
draft
→ ready
→ in_progress
→ validation_failed | ready_for_review
→ completed
```

Semantics:

- `draft`: reviewer may add/remove feedback and edit intended scope;
- `ready`: batch scope is frozen and eligible for execution;
- `in_progress`: OpenCode is implementing the frozen scope;
- `validation_failed`: required validation failed; feedback does not become addressed;
- `ready_for_review`: implementation and required validation passed; linked eligible feedback may move `open → addressed`;
- `completed`: reviewer has reviewed the batch outcome; individual feedback may be resolved or reopened independently.

## Batch Scope Freezing

At `draft → ready`:

- linked feedback IDs become immutable;
- intended scope becomes immutable;
- reviewer-confirmed change classification becomes immutable for that batch;
- newly discovered feedback must enter a different batch.

OpenCode must never expand a ready/in-progress batch scope silently.

## Batch Record

A refinement batch records at minimum:

```yaml
id: batch-007
review_round: 2
status: ready
feedback_ids:
  - feedback-021
  - feedback-022
intended_scope:
  screens:
    - commerce.home
  sections:
    - home.product-grid
change_classification:
  proposed_by: opencode
  proposed: implementation_only
  confirmed_by: reviewer-123
  confirmed: implementation_only
execution:
  agent: opencode
  model: deepseek-v4-pro
  commit_sha: null
  files_changed: []
validation:
  status: pending
  checks: []
evidence: []
```

Exact schema should follow repository conventions while preserving these semantics.

## Change Classification

Every refinement batch is classified as:

```text
implementation_only
contract_impacting
```

Rules:

- OpenCode may propose a classification;
- reviewer confirmation is authoritative;
- uncertainty defaults to `contract_impacting`;
- once the batch becomes `ready`, confirmed classification is frozen;
- contract-impacting changes trigger the C.5 re-review/re-approval rule;
- implementation-only changes may proceed without new approval if the approved experience contract is unchanged.

## OpenCode Authority

OpenCode may:

- execute a reviewer-created ready batch;
- modify code within frozen scope;
- run targeted/full validation;
- record files changed, commit SHA, checks, and evidence;
- move eligible linked feedback from `open` to `addressed` only when batch validation reaches `ready_for_review`.

OpenCode must never:

- resolve feedback;
- reopen feedback on behalf of a reviewer except via system failure semantics described below;
- change blocking classification;
- alter reviewer-confirmed change classification;
- expand frozen batch scope;
- edit immutable ApprovalSnapshot history;
- auto-create approval;
- mutate runtime bundles as review state.

## Feedback Transition After Refinement

Successful path:

```text
open feedback
  ↓
ready batch
  ↓
in_progress
  ↓
validation passes
  ↓
ready_for_review
  ↓
linked feedback open → addressed
  ↓
reviewer resolves or reopens
  ↓
batch completed
```

Validation failure path:

```text
in_progress
  ↓
validation_failed
  ↓
feedback remains open
```

If an already-addressed item becomes invalidated by a later regression, the system records an append-only reopen event and returns it to open. This must be deterministic and must identify the batch/evidence that caused the regression finding.

## ReviewCoordinator Responsibilities

Extend the thin coordinator to enforce cross-domain rules:

```text
Review UI / OpenCode adapter
  ↓
ReviewCoordinator
  ├─ ReviewRepository
  ├─ FeedbackRepository
  ├─ RefinementBatchRepository
  └─ ApprovalRepository
```

Examples:

- create a batch only from eligible feedback;
- freeze batch scope at ready;
- reject execution of draft/completed batches;
- require validation evidence before ready_for_review;
- mark linked feedback addressed only after successful batch validation;
- prevent OpenCode from resolving feedback;
- surface contract-impacting batches to review-round/re-approval logic;
- keep operations transactional across repositories.

## Persistence Boundaries

Use a dedicated repository:

```text
RefinementBatchRepository → RefinementBatch
```

Initial storage may be file-backed:

```text
client-projects/<client>/review/
  refinement-batches/
    batch-001.json
    batch-002.json
```

Visual attachments are referenced by FeedbackRecord; provider/source files may live elsewhere but must have stable immutable references.

Completed batches are effectively frozen. Historical execution evidence must not be silently rewritten.

A lightweight review index may list batch IDs but is not authoritative over batch records.

## Typed Domain Errors

Use stable machine-readable errors such as:

```text
InvalidVisualAnnotation
UnsupportedVisualProviderPayload
BatchScopeFrozen
BatchNotReady
BatchAlreadyCompleted
InvalidBatchTransition
BatchValidationRequired
BatchValidationFailed
UnauthorizedFeedbackResolution
UnauthorizedBlockingChange
ContractClassificationUnconfirmed
ContractImpactRequiresNewRound
```

Invalid operations are transactional:

```text
failure
→ no partial record mutation
→ no false addressed transition
→ no lifecycle history event unless the failure itself is intentionally recorded as batch validation evidence
```

## Validation Invariants

Visual evidence:

- normalized coordinates are within 0..1;
- positive width/height where region dimensions are present;
- screenshot_ref is stable and non-empty;
- target screen/section is valid when supplied;
- provider metadata cannot drive lifecycle decisions directly.

Refinement batch:

- legal status transition;
- feedback IDs exist and are eligible;
- scope is mutable only in draft;
- confirmed change classification exists before ready;
- execution may begin only from ready;
- ready_for_review requires successful validation evidence;
- feedback status transition to addressed is derived from successful batch state;
- completed batch cannot be reopened/edited in place.

## Required Validation Evidence

The exact checks depend on scope, but a batch reaching `ready_for_review` must have a deterministic validation record including at least:

- targeted tests for affected review/Flutter code;
- repository/domain validation relevant to changed files;
- `flutter analyze` for affected Flutter package/app when Flutter code changes;
- screenshot/evidence reference when the feedback was visual and reproduction is available;
- full canonical checks when the batch is classified contract-impacting or touches shared architecture.

C.7 does not itself implement D.1 automated screenshot capture or D.2 Visual AI scoring. It may consume manually/provider-created screenshots as evidence.

## Reviewer Workflow

Reviewer flow:

```text
open feedback
→ select related items
→ create draft batch
→ confirm intended scope
→ review proposed change classification
→ confirm classification
→ mark batch ready
→ hand to OpenCode
→ inspect ready_for_review result
→ resolve/reopen individual feedback
→ complete batch
```

Batch completion does not imply every linked item is resolved; reviewer may reopen some while resolving others.

## End-to-End C.6–C.7 Scenario

```text
C.3 mixed experience
→ reviewer creates visual_annotation feedback
→ BugDrop adapter normalizes screenshot/region evidence
→ reviewer creates batch from related feedback
→ reviewer confirms implementation_only / contract_impacting
→ batch ready (scope frozen)
→ OpenCode implements
→ targeted tests/validation/evidence recorded
→ ready_for_review
→ feedback becomes addressed
→ reviewer resolves or reopens
→ batch completed
→ C.4 round eligibility recalculated
→ C.5 approval proceeds only if blocking conditions are satisfied
```

## Testing

### Visual provider tests

Cover:

- BugDrop-style payload normalization;
- provider-neutral attachment output;
- normalized coordinate validation;
- screen/section target validation;
- immutable screenshot reference;
- malformed provider payload typed errors;
- no provider-triggered lifecycle changes.

### Refinement batch domain tests

Cover:

- draft add/remove feedback;
- scope freeze at ready;
- illegal scope mutation after ready;
- lifecycle transition matrix;
- classification confirmation and freeze;
- execution only from ready;
- validation_failed leaves feedback open;
- ready_for_review requires validation evidence;
- completed batch frozen.

### Coordinator tests

Cover:

- only reviewer-created batches are executable;
- OpenCode cannot auto-create/expand batch;
- successful validation moves eligible feedback to addressed;
- invalid batch causes no partial feedback mutation;
- OpenCode cannot resolve or downgrade blocking feedback;
- contract-impacting classification triggers re-review requirement;
- implementation-only classification does not trigger re-approval when contract unchanged.

### Integration test

```text
visual feedback
→ normalized attachment
→ reviewer-created frozen batch
→ OpenCode execution
→ validation passes
→ addressed
→ reviewer resolves
→ review round closes
→ approval eligible
```

## Non-Goals

C.6–C.7 do not implement:

- D.1 automated screenshot capture;
- D.2 Visual AI scoring/automatic visual verdicts;
- automatic batch creation;
- automatic feedback resolution;
- automatic blocking downgrade;
- automatic approval;
- generic external issue tracker synchronization;
- production deployment;
- a generic workflow/event-sourcing platform.

## Success Criteria

C.6–C.7 are complete when:

1. visual annotations normalize through a provider-neutral adapter into FeedbackRecord evidence;
2. BugDrop is the first adapter but core models remain provider-agnostic;
3. reviewer-created refinement batches have explicit lifecycle and frozen scope at ready;
4. OpenCode can implement and record validated results without resolving feedback or changing review authority;
5. successful refinement moves feedback only to addressed;
6. reviewer remains sole authority for resolve/reopen/blocking and change-classification confirmation;
7. contract-impacting changes feed correctly into C.4/C.5 re-review rules;
8. all cross-domain operations are transactional, typed-error driven, and covered by tests.
