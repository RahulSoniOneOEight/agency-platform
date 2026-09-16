# Review Refinement — OpenCode Execution Contract

> C.7 (`RefinementBatch`) handoff between the reviewer-governed review system and OpenCode.
> The review system is authoritative for scope, classification, and feedback lifecycle;
> OpenCode is an execution actor only.

## Purpose

A reviewer creates a refinement batch from eligible `open` feedback, confirms its change
classification, and marks it `ready`. At that moment the batch scope and classification are
**frozen**. OpenCode receives the frozen batch, implements the change, runs the required
validation, and returns a structured result. The review coordinator alone decides whether the
result is acceptable and whether linked feedback becomes `addressed`.

## Frozen batch fields OpenCode receives

The coordinator hands OpenCode the canonical JSON of a `ready` (or `in_progress`) batch
(`apps/prototype_app/lib/review/refinement_batch.dart` → `RefinementBatch.toJson`). OpenCode must
treat every field as read-only:

```yaml
id: batch-007
client_id: prototype-demo
review_round: 2
status: ready                 # ready | in_progress
feedback_ids: [feedback-021, feedback-022]   # frozen
intended_scope:
  screens: [commerce.home]
  sections: [home.product-grid]              # frozen
change_classification:
  proposed_by: opencode
  proposed: implementation_only
  confirmed_by: reviewer-123
  confirmed: implementation_only             # frozen, reviewer-authoritative
execution:
  agent: null
  model: null
  commit_sha: null
  files_changed: []
validation:
  status: pending
  checks: []
evidence: []
created_at: 2026-09-17T10:00:00.000Z
updated_at: 2026-09-17T10:00:00.000Z
history: [...]                               # append-only audit trail
```

### Authority rules

OpenCode **may**:

- execute a reviewer-created `ready` batch;
- modify code only within `intended_scope`;
- run targeted/full validation;
- record `commit_sha`, `files_changed`, checks, and `evidence`.

OpenCode **must never**:

- resolve feedback;
- reopen feedback on behalf of a reviewer (the only exception is the system-failure
  `reopenAddressedForRegression` path, which records a cause/evidence/batch id);
- change blocking classification;
- alter the reviewer-confirmed `change_classification`;
- expand `feedback_ids` or `intended_scope`;
- edit immutable `ApprovalSnapshot` history;
- auto-create approval;
- auto-create a batch (batches are reviewer-created only);
- mutate runtime bundles / B.1D / B.1E artifacts as review state.

## Result fields OpenCode must return

OpenCode returns exactly one `RefinementExecutionResult`
(`apps/prototype_app/lib/review/refinement_execution_result.dart`):

```yaml
status: passed                # passed | failed
commit_sha: abc123
files_changed: [lib/review/refinement_batch.dart]
checks:
  - name: flutter test test/review
    passed: true
    details: all green
  - name: flutter analyze
    passed: true
    details: no issues
evidence: [review-home-round-2]   # screenshot/evidence refs
notes: implemented within frozen scope
```

| Field | Required | Semantics |
|-------|----------|-----------|
| `status` | yes | `passed` only when the required validation actually succeeded. |
| `commit_sha` | yes | Non-empty commit identifier for the executed change. |
| `files_changed` | yes (may be empty) | Deterministically sorted, unique paths. |
| `checks` | yes | Each check has `name`, `passed`, and `details`. |
| `evidence` | yes (may be empty) | Stable screenshot/evidence references. |
| `notes` | no | Free-form operator note; non-blank when present. |

The coordinator maps the result onto the batch via `recordBatchValidation`:

- `passed` + at least one passed check ⇒ batch `ready_for_review`; linked `open` feedback moves to
  `addressed` with an `addressed` event carrying the `batchId`.
- `failed` ⇒ batch `validation_failed`; linked feedback stays `open`.
- A visual feedback batch reaching `ready_for_review` additionally requires non-empty `evidence`.

## Required validation evidence

A batch reaching `ready_for_review` must have a deterministic validation record including at least:

- targeted tests for the affected review/Flutter code;
- repository/domain validation relevant to the changed files;
- `flutter analyze` for the affected Flutter package/app when Flutter code changes;
- a screenshot/evidence reference when the feedback was visual and reproduction is available;
- full canonical checks when the batch is classified `contract_impacting` or touches shared
  architecture.

C.7 does not implement D.1 automated screenshot capture or D.2 Visual AI scoring; screenshots are
consumed only as manually/provider-created evidence references.

## Transactional guarantees

`recordBatchValidation` validates the batch transition before any write, persists the authoritative
batch **first**, and only then moves linked feedback to `addressed`. A batch persistence failure can
therefore never produce a false `addressed` transition.
