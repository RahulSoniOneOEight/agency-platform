# C.4–C.5 Client Review & Approval Design

## Purpose

C.4 and C.5 extend the C.3 Select + Mix decision workspace into a governed review-and-approval system. C.4 adds structured feedback, review rounds, blocking rules, lifecycle history, and explicit reviewer-controlled round closure. C.5 generates immutable, append-only approval snapshots only when the reviewed experience is eligible.

This design preserves the authority boundaries established through C.3: ReviewState is the live review decision authority; runtime/B.1D/B.1E remain product implementation authorities; approval is a separate frozen record, not a mutation of runtime or ReviewState.

## Position in the Flow

```text
C.3 Select + Mix
  ↓
C.4 Structured Review + Review Rounds
  ↓
C.5 Approval Contract
  ↓
C.6 Visual Feedback
  ↓
C.7 OpenCode Refinement
```

C.6/C.7 may feed additional review cycles before final approval. Approval must never bypass unresolved blocking feedback.

## Core Architecture

Use separate records with clear authority:

```text
ReviewState
  → current decisions + active review status/round

FeedbackRecord
  → stable feedback identity + lifecycle/history authority

ApprovalSnapshot
  → immutable approved experience authority
```

A thin `ReviewCoordinator` enforces cross-domain workflow rules. Repositories persist records but do not own cross-domain eligibility logic.

## ReviewState Responsibilities

ReviewState remains the live mutable review record and continues to hold:

- client identity;
- current review round;
- review status;
- C.3 decision tree (overall → screen → section);
- references to feedback relevant to the current review.

ReviewState must not contain:

- immutable approval history;
- OpenCode refinement execution history;
- provider-specific visual-feedback payloads beyond stable references.

## Unified Feedback Model

C.4 evolves comments into stable `FeedbackRecord` entities.

Each record contains at minimum:

```yaml
id: feedback-001
scope: section
text: "Increase spacing above this section"
status: open
blocking: true
created_round: 2
resolved_round: null
target:
  screen: commerce.home
  section: home.product-grid
history: []
```

### Supported scopes

```text
general
screen
section
decision
visual_annotation
```

Target fields must be valid for the selected scope. For example, a section-scoped item must identify a governed screen and section. A visual annotation may optionally identify a governed section but may instead target a free-form visual region.

## Feedback Lifecycle

Canonical lifecycle:

```text
open
→ addressed
→ resolved

resolved
→ reopened/open
```

Rules:

- `open`: requires work or review attention.
- `addressed`: implementation/refinement is complete and ready for reviewer re-check.
- `resolved`: reviewer accepts the outcome.
- reopening preserves the same feedback identity.
- history is append-only; current status remains directly queryable.

Only the reviewer may:

- resolve feedback;
- reopen feedback;
- change blocking/non-blocking classification.

OpenCode/refinement tooling may move an item `open → addressed` only after successful validation under C.7.

## Feedback History

Each feedback item stores append-only lifecycle events, e.g.:

```yaml
history:
  - event: created
    actor: reviewer-123
    round: 2
    at: 2026-09-17T10:00:00Z
  - event: addressed
    actor: opencode
    batch_id: batch-007
    at: 2026-09-17T11:15:00Z
  - event: reopened
    actor: reviewer-123
    at: 2026-09-17T11:40:00Z
  - event: resolved
    actor: reviewer-123
    round: 2
    at: 2026-09-17T12:00:00Z
```

Historical events are never rewritten or deleted.

## Blocking vs Non-Blocking Feedback

Each feedback record has:

```text
blocking: true | false
```

Rules:

- blocking feedback must be resolved before approval;
- non-blocking feedback may remain open at approval time;
- reviewer authority is required to change `blocking`;
- OpenCode cannot downgrade a blocking item;
- default for new reviewer feedback should be blocking unless explicitly classified otherwise.

Unresolved non-blocking feedback is carried into the approval snapshot and later production backlog rather than discarded.

## Review Round Lifecycle

Review rounds are explicit and reviewer-controlled.

```text
Round N starts
  ↓
feedback created/classified
  ↓
refinement happens
  ↓
feedback addressed
  ↓
reviewer resolves or reopens
  ↓
all blocking feedback resolved?
  ├─ no  → continue Round N
  └─ yes → eligible to close round
  ↓
reviewer explicitly closes round
  ↓
ready_for_final_review
```

Review status transitions:

```text
in_review
→ needs_revision
→ in_review
→ ready_for_final_review
```

Rules:

- blocking open feedback that requires implementation moves the review toward `needs_revision`;
- reviewer re-check of addressed work occurs under `in_review`;
- `ready_for_final_review` is never set merely because the last blocking item became resolved; the reviewer must explicitly close the round;
- new substantive feedback after readiness creates/advances to a new review round and returns status to `in_review` or `needs_revision`;
- prior feedback/history remains intact across rounds.

Each feedback item records `created_round` and optional `resolved_round`.

## Reviewer and Approver Roles

Reviewer and approver are distinct roles even when the same person performs both.

Reviewer authority:

- create/classify feedback;
- set blocking/non-blocking;
- resolve/reopen feedback;
- close/advance review rounds;
- confirm change classification from C.7.

Approver authority:

- issue final experience approval after eligibility gates pass.

Approval records both identities separately:

```yaml
reviewed_by:
  id: reviewer-123
  name: Rahul
approved_by:
  id: reviewer-123
  name: Rahul
```

The same person may occupy both roles.

## Approval Eligibility

Approval creation is permitted only when all gates pass:

```text
ReviewState.status == ready_for_final_review
AND
all blocking feedback == resolved
AND
no unresolved refinement dependency blocks approval
AND
C.3 decision tree validates
AND
reviewer identity recorded
AND
approver identity recorded
AND
source commit SHA available
AND
review-state hash available
```

Any failed gate returns a typed domain error and causes no partial persistence.

## Approval Snapshot

C.5 creates an immutable `ApprovalSnapshot` representing the reviewed experience at a point in time.

Conceptual shape:

```yaml
approval_version: 1
client_id: prototype-demo
review_round: 3
approved_at: 2026-09-17T12:30:00Z
reviewed_by:
  id: reviewer-123
  name: Rahul
approved_by:
  id: approver-123
  name: Rahul
selected_direction: a
screens:
  commerce.home:
    direction: b
    sections:
      home.product-grid: c
theme_preset: null
unresolved_non_blocking:
  - feedback-021
source_commit_sha: abc123
review_state_hash: sha256:...
supersedes: null
```

The exact file schema should follow repository conventions while preserving these semantics.

## Append-Only Approval History

Approvals are append-only and immutable.

```text
approval-v1
→ later contract-impacting change
→ new review round
→ approval-v2
```

Rules:

- approval versions are monotonic;
- an existing version cannot be overwritten;
- retrying creation with an already-used version fails with `ApprovalVersionConflict`;
- previous approvals remain historically valid;
- once a newer approval exists, prior snapshots may reference `superseded_by` metadata, but the prior snapshot itself must not be mutated if immutability would be violated; supersession may be represented in a separate index/manifest if needed.

## Contract-Impacting vs Implementation-Only Changes

After approval, changes are classified as:

```text
contract_impacting
implementation_only
```

Rules:

- OpenCode may propose a classification;
- reviewer confirmation is authoritative;
- uncertainty defaults to `contract_impacting`;
- contract-impacting changes require a new review round and new approval version;
- implementation-only changes do not require re-approval if they do not alter the approved experience contract.

The classification and reviewer confirmation are auditable records.

## Persistence Boundaries

Use separate repository abstractions:

```text
ReviewRepository      → ReviewState
FeedbackRepository    → FeedbackRecord
ApprovalRepository    → ApprovalSnapshot
```

Initial storage may be file-backed:

```text
client-projects/<client>/review/
  review-state.json
  feedback/
    feedback-001.json
  approvals/
    approval-v1.yaml
```

A lightweight operational index may list active/current IDs but is not authoritative over the records themselves.

Repository APIs must expose domain operations, not arbitrary map mutation.

## ReviewCoordinator

Cross-domain rules live in a thin coordinator:

```text
Review UI / API
   ↓
ReviewCoordinator
   ├─ ReviewRepository
   ├─ FeedbackRepository
   └─ ApprovalRepository
```

Examples:

- creating blocking feedback updates review status as required;
- resolving feedback recalculates round eligibility;
- closing a round enforces eligibility before setting readiness;
- creating approval performs all approval gates atomically.

`ReviewController` should remain focused on interactive ReviewState mutation and should not become the C.4–C.5 orchestration engine.

## Typed Domain Errors

Use typed machine-readable errors for stable behavior, e.g.:

```text
InvalidFeedbackTransition
InvalidFeedbackTarget
BlockingFeedbackUnresolved
ReviewRoundNotClosable
ApprovalNotEligible
ApprovalVersionConflict
ContractImpactRequiresNewRound
UnauthorizedReviewAction
```

UI copy may map these to human-friendly messages.

Invalid operations are transactional:

```text
invalid operation
→ no partial persistence
→ no lifecycle event written
→ no status mutation
→ deterministic typed error
```

## Validation Invariants

Feedback invariants:

- legal lifecycle transition;
- target matches scope;
- governed screen/section IDs exist where required;
- blocking changes are reviewer-only;
- append-only history is internally consistent;
- resolved feedback retains historical events.

Review-round invariants:

- round numbers are monotonic positive integers;
- readiness requires explicit reviewer close;
- prior-round feedback/history remains accessible;
- unresolved blocking feedback prevents readiness.

Approval invariants:

- immutable after creation;
- monotonic version;
- exact client/review-round identity;
- valid C.3 decision tree;
- no unresolved blocking feedback;
- unresolved non-blocking IDs explicitly carried forward;
- source commit and review-state hash required;
- reviewer/approver identities recorded separately.

## Testing

### Domain tests

Cover:

- feedback creation for each scope;
- legal and illegal status transitions;
- reviewer-only blocking changes;
- resolve/reopen behavior;
- append-only history;
- round eligibility with blocking/non-blocking items;
- explicit close-round behavior;
- cross-round history preservation.

### Repository tests

Cover:

- stable serialization;
- immutable approval creation;
- duplicate approval version rejection;
- deterministic reads/writes;
- no accidental overwrite of completed/immutable records.

### Coordinator tests

Cover:

- blocking feedback drives review status;
- invalid operations produce no partial writes;
- closing a round is rejected when blockers remain;
- approval is rejected when any eligibility gate fails;
- non-blocking unresolved feedback is carried into approval;
- reviewer and approver may be same identity while stored separately;
- contract-impacting change requires re-review.

### End-to-end C.4–C.5 test

```text
C.3 decision tree
→ create blocking feedback
→ mark addressed
→ reviewer resolves
→ close round
→ status ready_for_final_review
→ create approval-v1
→ create later contract-impacting change
→ new round
→ create approval-v2
```

## Non-Goals

C.4–C.5 do not implement:

- visual screenshot capture/annotation provider integration;
- OpenCode refinement execution;
- automatic comment resolution;
- automatic approval;
- arbitrary component-level mixing beyond C.3;
- production deployment;
- Visual AI QA;
- generic event sourcing.

## Success Criteria

C.4–C.5 are complete when:

1. feedback has stable identity, unified scopes, lifecycle, blocking rules, and append-only history;
2. review rounds are explicit, preserved, and reviewer-controlled;
3. blocking feedback reliably gates readiness and approval;
4. reviewer and approver roles are recorded separately;
5. approval snapshots are immutable, append-only, traceable, and versioned;
6. unresolved non-blocking feedback is preserved in approval/backlog context;
7. contract-impacting changes require re-review while implementation-only changes do not;
8. all cross-domain operations are transactional and covered by tests.
