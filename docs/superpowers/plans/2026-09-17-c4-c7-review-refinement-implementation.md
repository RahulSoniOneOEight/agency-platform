# C.4–C.7 Review, Approval, Visual Feedback & Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete client-review loop from structured feedback and review rounds through immutable approval, provider-neutral visual annotation, and reviewer-governed OpenCode refinement.

**Architecture:** Extend the existing C.3 Review Mode without creating a parallel review system. `ReviewState` remains live decision authority; `FeedbackRecord` owns feedback/history; `RefinementBatch` owns change execution/audit; `ApprovalSnapshot` owns immutable approval. A thin `ReviewCoordinator` enforces cross-domain rules transactionally.

**Tech Stack:** Flutter/Dart, existing `prototype_app` Review Mode, existing C.3 decision/section registries, repository abstractions, JSON/YAML file-backed adapters where persisted artifacts are required, Python repository validators, GitHub/OpenCode workflow.

**Specs:**
- `docs/superpowers/specs/2026-09-17-c4-c5-client-review-approval-design.md`
- `docs/superpowers/specs/2026-09-17-c6-c7-visual-feedback-refinement-design.md`

## Global Constraints

- Preserve C.3 `overall → screen → section` decision authority and normalization.
- Do not create a second comment/feedback system for visual annotations.
- Feedback lifecycle is `open → addressed → resolved`, with `resolved → open` only through reviewer reopen.
- Reviewer alone may resolve/reopen feedback, change blocking state, close/advance rounds, and confirm change classification.
- OpenCode may mark feedback `addressed` only after a refinement batch reaches `ready_for_review` with required validation evidence.
- Approver is distinct from reviewer in the data model, even when the same person occupies both roles.
- Blocking feedback must be resolved before final approval; unresolved non-blocking feedback must be carried into approval/backlog context.
- Approval snapshots are append-only and immutable; no overwrite-in-place.
- Contract-impacting changes require a new review round and approval version; implementation-only changes do not when the approved experience contract is unchanged.
- BugDrop is an adapter/provider, not a core model dependency.
- No D.1 automated screenshot capture, D.2 Visual AI scoring, production deployment, generic event sourcing, automatic batch creation, automatic resolution, or automatic approval.
- Do not commit the intentionally untracked `pubspec.lock` files unless lockfile policy is explicitly changed outside this milestone.

## Three-Cycle Execution Map

| Cycle | Scope | Exit condition |
|---|---|---|
| **Cycle 1 — Review Lifecycle Core** | C.4 feedback domain, repositories, `ReviewCoordinator`, reviewer UI, review-round gating | Structured feedback/round flow works end-to-end and is independently testable |
| **Cycle 2 — Approval + Visual Evidence** | C.5 immutable approval snapshots + C.6 provider-neutral visual attachments/BugDrop adapter | Eligible review can create immutable approval; visual annotations enter the same feedback model |
| **Cycle 3 — Refinement + Integration Hardening** | C.7 refinement batches/OpenCode contract + cross-milestone integration, full verification, PR | Complete `feedback → refine → addressed → resolve → approve` flow verified and PR opened |

---

# Cycle 1 — Review Lifecycle Core (C.4)

## Task 1: Unified Feedback Domain + Repositories

**Files:**
- Create: `apps/prototype_app/lib/review/feedback_record.dart`
- Create: `apps/prototype_app/lib/review/feedback_repository.dart`
- Create: `apps/prototype_app/lib/review/memory_feedback_repository.dart`
- Modify: `apps/prototype_app/lib/review/review_state.dart`
- Modify: `apps/prototype_app/lib/review/review_state_validator.dart`
- Test: `apps/prototype_app/test/review/feedback_record_test.dart`
- Test: `apps/prototype_app/test/review/feedback_repository_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_state_test.dart`

**Interfaces:**

```dart
enum FeedbackStatus { open, addressed, resolved }
enum FeedbackScope { general, screen, section, decision, visualAnnotation }

enum FeedbackEventType { created, addressed, reopened, resolved, blockingChanged }

final class FeedbackTarget {
  const FeedbackTarget({this.screen, this.section, this.direction});
  final String? screen;
  final String? section;
  final String? direction;
}

final class FeedbackEvent {
  const FeedbackEvent({
    required this.type,
    required this.actorId,
    required this.at,
    this.round,
    this.batchId,
  });
  final FeedbackEventType type;
  final String actorId;
  final DateTime at;
  final int? round;
  final String? batchId;
}

final class FeedbackRecord {
  const FeedbackRecord({
    required this.id,
    required this.scope,
    required this.text,
    required this.status,
    required this.blocking,
    required this.createdRound,
    required this.target,
    required this.history,
    this.resolvedRound,
    this.visualAttachment,
  });
}

abstract interface class FeedbackRepository {
  Future<FeedbackRecord?> load(String clientId, String feedbackId);
  Future<List<FeedbackRecord>> list(String clientId);
  Future<void> create(String clientId, FeedbackRecord record);
  Future<void> replace(String clientId, FeedbackRecord expectedCurrent, FeedbackRecord next);
}
```

`ReviewState` should store feedback references only, e.g. `List<String> feedbackIds`, not duplicate feedback records.

- [ ] **Step 1: Write failing model tests** for all scopes, target validation, append-only history, deterministic JSON, `createdRound > 0`, immutable input collections, and illegal malformed payloads.
- [ ] **Step 2: Run focused tests**

```bash
cd apps/prototype_app
flutter test test/review/feedback_record_test.dart test/review/review_state_test.dart
```

Expected: FAIL because the new types/fields do not exist.

- [ ] **Step 3: Implement the domain types and serialization** with stable wire values: `open`, `addressed`, `resolved`, `general`, `screen`, `section`, `decision`, `visual_annotation`.
- [ ] **Step 4: Add ReviewState feedback references** without moving decision data out of ReviewState; preserve C.3 v1/v2 migration behavior and use a backward-compatible default empty `feedback_ids` when absent in legacy v2 state.
- [ ] **Step 5: Implement repository tests** proving duplicate create is rejected and replacement uses expected-current semantics rather than blind overwrite.
- [ ] **Step 6: Implement `MemoryFeedbackRepository`** and keep deterministic ID ordering in `list()`.
- [ ] **Step 7: Run focused tests and existing C.3 review tests**

```bash
flutter test test/review/feedback_record_test.dart test/review/feedback_repository_test.dart test/review/review_state_test.dart test/review/review_state_validator_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit only Cycle-1 Task-1 files**

```bash
git status
git add apps/prototype_app/lib/review/feedback_record.dart apps/prototype_app/lib/review/feedback_repository.dart apps/prototype_app/lib/review/memory_feedback_repository.dart apps/prototype_app/lib/review/review_state.dart apps/prototype_app/lib/review/review_state_validator.dart apps/prototype_app/test/review/feedback_record_test.dart apps/prototype_app/test/review/feedback_repository_test.dart apps/prototype_app/test/review/review_state_test.dart apps/prototype_app/test/review/review_state_validator_test.dart
git commit -m "feat(review): add unified feedback domain"
```

## Task 2: ReviewCoordinator + Round State Machine

**Files:**
- Create: `apps/prototype_app/lib/review/review_domain_error.dart`
- Create: `apps/prototype_app/lib/review/review_actor.dart`
- Create: `apps/prototype_app/lib/review/review_coordinator.dart`
- Modify: `apps/prototype_app/lib/review/review_controller.dart`
- Test: `apps/prototype_app/test/review/review_coordinator_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_controller_test.dart`

**Interfaces:**

```dart
enum ReviewRole { reviewer, approver, agent }

final class ReviewActor {
  const ReviewActor({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final ReviewRole role;
}

sealed class ReviewDomainError implements Exception {}
final class InvalidFeedbackTransition extends ReviewDomainError {}
final class InvalidFeedbackTarget extends ReviewDomainError {}
final class UnauthorizedReviewAction extends ReviewDomainError {}
final class BlockingFeedbackUnresolved extends ReviewDomainError {}
final class ReviewRoundNotClosable extends ReviewDomainError {}

final class ReviewCoordinator {
  Future<FeedbackRecord> createFeedback(...);
  Future<FeedbackRecord> setBlocking(...);
  Future<FeedbackRecord> resolveFeedback(...);
  Future<FeedbackRecord> reopenFeedback(...);
  Future<void> closeCurrentRound(...);
  Future<void> startNextRound(...);
}
```

Cross-domain mutation order must be transactional in behavior: validate complete candidate state first, then persist; if any write fails, do not adopt/notify partial in-memory state. For multi-repository file persistence introduced later, write new immutable records before updating mutable index/state pointer.

- [ ] **Step 1: Write failing transition-matrix tests** covering `open→addressed`, reviewer `addressed→resolved`, reviewer `resolved→open`, illegal `open→resolved` by agent, blocking changes by non-reviewer, and history events.
- [ ] **Step 2: Write failing round tests** proving blockers prevent close, non-blocking open items do not prevent close, last blocker resolution makes a round eligible but does not auto-close, and explicit reviewer close sets `ready_for_final_review`.
- [ ] **Step 3: Run focused tests**

```bash
flutter test test/review/review_coordinator_test.dart test/review/review_controller_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Implement typed domain errors and actor roles.**
- [ ] **Step 5: Implement `ReviewCoordinator` C.4 operations** using `ReviewRepository` + `FeedbackRepository`; keep `ReviewController` responsible only for interactive ReviewState decisions/status/round primitives and route cross-domain operations through coordinator.
- [ ] **Step 6: Implement explicit next-round behavior**: preserve prior feedback/history, increment round monotonically, return status to `in_review`, and never delete feedback IDs.
- [ ] **Step 7: Run focused tests and full review tests**

```bash
flutter test test/review/review_coordinator_test.dart test/review/review_controller_test.dart
flutter test test/review
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git status
git add apps/prototype_app/lib/review/review_domain_error.dart apps/prototype_app/lib/review/review_actor.dart apps/prototype_app/lib/review/review_coordinator.dart apps/prototype_app/lib/review/review_controller.dart apps/prototype_app/test/review/review_coordinator_test.dart apps/prototype_app/test/review/review_controller_test.dart
git commit -m "feat(review): govern feedback and review rounds"
```

## Task 3: Reviewer-Facing Feedback + Round UI

**Files:**
- Modify: `apps/prototype_app/lib/review/review_comments.dart`
- Modify: `apps/prototype_app/lib/review/review_shell.dart`
- Create: `apps/prototype_app/lib/review/review_feedback_panel.dart`
- Test: `apps/prototype_app/test/review/review_feedback_panel_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_comments_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_shell_test.dart`

**Required UI behavior:**
- list feedback by current round with prior-round history accessible;
- create feedback with scope + target + blocking classification;
- show `open / addressed / resolved` status;
- reviewer can resolve/reopen and toggle blocking;
- show `Eligible to close round` only when blockers are resolved;
- explicit `Close review round` action;
- preserve existing review decision/comment UX where not superseded.

- [ ] **Step 1: Write failing widget tests** for blocking labels, status chips, reviewer-only actions, close-round disabled/enabled state, and prior-round visibility.
- [ ] **Step 2: Run tests and confirm failure.**
- [ ] **Step 3: Implement `ReviewFeedbackPanel`** backed by coordinator/repositories; do not mutate raw maps in widgets.
- [ ] **Step 4: Wire the panel into Review Mode** by evolving the existing Comments destination rather than adding a second feedback app.
- [ ] **Step 5: Run widget tests plus `flutter test test/review`.**
- [ ] **Step 6: Commit.**

### Cycle 1 Review Gate

Run:

```bash
cd apps/prototype_app
flutter test test/review
flutter analyze
```

Fresh reviewer must verify:
1. one feedback model only;
2. reviewer authority enforced;
3. open/addressed/resolved history append-only;
4. blockers gate readiness but non-blockers do not;
5. explicit close/advance only;
6. C.3 decisions remain unchanged;
7. no approval or refinement authority leaked into ReviewController.

Fix findings before Cycle 2.

---

# Cycle 2 — Approval + Visual Evidence (C.5 + C.6)

## Task 4: Immutable Approval Domain + Repository

**Files:**
- Create: `apps/prototype_app/lib/review/approval_snapshot.dart`
- Create: `apps/prototype_app/lib/review/approval_repository.dart`
- Create: `apps/prototype_app/lib/review/memory_approval_repository.dart`
- Create: `apps/prototype_app/lib/review/review_state_hash.dart`
- Modify: `apps/prototype_app/lib/review/review_coordinator.dart`
- Test: `apps/prototype_app/test/review/approval_snapshot_test.dart`
- Test: `apps/prototype_app/test/review/approval_repository_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_coordinator_test.dart`

**Interfaces:**

```dart
final class ApprovalSnapshot {
  const ApprovalSnapshot({
    required this.version,
    required this.clientId,
    required this.reviewRound,
    required this.reviewedBy,
    required this.approvedBy,
    required this.approvedAt,
    required this.selectedDirection,
    required this.screenSelections,
    required this.unresolvedNonBlockingFeedbackIds,
    required this.sourceCommitSha,
    required this.reviewStateHash,
    this.themePreset,
    this.supersedes,
  });
}

abstract interface class ApprovalRepository {
  Future<List<ApprovalSnapshot>> list(String clientId);
  Future<void> create(String clientId, ApprovalSnapshot snapshot);
}
```

Add typed errors `ApprovalNotEligible`, `ApprovalVersionConflict`, `ContractImpactRequiresNewRound`.

- [ ] **Step 1: Write failing approval tests** for deterministic snapshot serialization, separate reviewer/approver identities, same-person dual role, non-blocking carry-forward, source commit/hash requirement, and version monotonicity.
- [ ] **Step 2: Write failing coordinator eligibility tests** for unresolved blocking feedback, wrong review status, missing reviewer, missing approver, invalid C.3 decision tree, and duplicate version.
- [ ] **Step 3: Implement canonical review-state hashing** from deterministic ReviewState JSON using SHA-256 over UTF-8 canonical JSON.
- [ ] **Step 4: Implement immutable memory repository** that rejects duplicate versions and does not expose mutation of stored snapshots.
- [ ] **Step 5: Implement coordinator `createApproval(...)`** that revalidates ReviewState/feedback immediately before creation and carries unresolved non-blocking IDs.
- [ ] **Step 6: Run focused tests and commit.**

## Task 5: File-Backed Review Artifacts + Approval YAML

**Files:**
- Create: `apps/prototype_app/lib/review/file_feedback_repository.dart`
- Create: `apps/prototype_app/lib/review/file_refinement_batch_repository.dart` (skeleton interface adapter used fully in Cycle 3)
- Create: `apps/prototype_app/lib/review/file_approval_repository.dart`
- Create: `apps/prototype_app/lib/review/review_index.dart`
- Create: `apps/prototype_app/lib/review/file_review_index_repository.dart`
- Test: `apps/prototype_app/test/review/file_review_repository_test.dart`
- Add/update reference-client review directory under `client-projects/examples/prototype-demo/review/` only through test fixtures or explicit generated artifacts; do not overwrite existing C.3 decision sources.

**Persistence contract:**

```text
client-projects/<client>/review/
  review-state.json
  review-index.json
  feedback/feedback-<id>.json
  refinement-batches/batch-<id>.json
  approvals/approval-v<version>.yaml
```

Approvals must use create-only semantics. `review-index.json` may point to IDs/versions but is not authoritative over record contents.

- [ ] **Step 1: Write failing temporary-directory tests** for deterministic paths, create-only approval, stable feedback file identity, atomic temp-write+rename for mutable index/current state, and index recovery when an immutable record exists but index update fails.
- [ ] **Step 2: Implement adapters** using `dart:io`; no new storage dependency unless repository conventions already provide one.
- [ ] **Step 3: Prove `approval-v1.yaml` cannot be overwritten** and `approval-v2.yaml` can be appended.
- [ ] **Step 4: Run focused tests and commit.**

## Task 6: Provider-Neutral Visual Attachment + BugDrop Adapter

**Files:**
- Create: `apps/prototype_app/lib/review/visual_attachment.dart`
- Create: `apps/prototype_app/lib/review/visual_feedback_provider.dart`
- Create: `apps/prototype_app/lib/review/bugdrop_visual_feedback_provider.dart`
- Modify: `apps/prototype_app/lib/review/feedback_record.dart`
- Modify: `apps/prototype_app/lib/review/review_coordinator.dart`
- Test: `apps/prototype_app/test/review/visual_attachment_test.dart`
- Test: `apps/prototype_app/test/review/bugdrop_visual_feedback_provider_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_coordinator_test.dart`

**Interfaces:**

```dart
final class NormalizedRect {
  const NormalizedRect({required this.x, required this.y, required this.width, required this.height});
}

final class VisualAttachment {
  const VisualAttachment({
    required this.screenshotRef,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.clientId,
    required this.reviewRound,
    required this.screenId,
    required this.effectiveDirection,
    required this.sourceCommitSha,
    required this.annotation,
    required this.providerName,
    required this.externalRef,
    this.sectionId,
  });
}

abstract interface class VisualFeedbackProvider {
  VisualAttachment normalize(Map<String, Object?> payload);
}
```

The BugDrop adapter is an ingestion adapter only. It must not perform lifecycle mutations or require the core domain to import provider-specific types. If no external BugDrop SDK/API contract exists in the repo, implement deterministic payload normalization at the integration boundary without adding a speculative network dependency.

- [ ] **Step 1: Write failing validation tests** for coordinate bounds, positive dimensions, required screenshot ref/context, optional governed section, and malformed payload typed error.
- [ ] **Step 2: Write failing provider-isolation test** proving BugDrop normalization does not mutate feedback/review state.
- [ ] **Step 3: Implement the neutral model and adapter.**
- [ ] **Step 4: Extend feedback creation to accept visual evidence only for `visual_annotation` scope and validate screen/section through existing C.3 registries.**
- [ ] **Step 5: Run focused tests and commit.**

## Task 7: Approval + Visual Feedback UI

**Files:**
- Create: `apps/prototype_app/lib/review/review_approval_panel.dart`
- Modify: `apps/prototype_app/lib/review/review_feedback_panel.dart`
- Modify: `apps/prototype_app/lib/review/review_shell.dart`
- Test: `apps/prototype_app/test/review/review_approval_panel_test.dart`
- Modify/Test: `apps/prototype_app/test/review/review_feedback_panel_test.dart`

**Required behavior:**
- show approval eligibility and exact blocking reasons;
- capture reviewer and approver identities separately;
- allow same person in both roles;
- create approval only through coordinator;
- show existing approval versions read-only;
- show unresolved non-blocking feedback carried forward;
- visual feedback entry accepts normalized/provider-adapted evidence and displays attachment context without giving provider UI authority over lifecycle.

- [ ] **Step 1: Write failing widget tests** for eligibility, disabled approval, immutable approval history, same-person role display, and visual evidence rendering.
- [ ] **Step 2: Implement UI and coordinator wiring.**
- [ ] **Step 3: Run all review tests and commit.**

### Cycle 2 Review Gate

Run:

```bash
cd apps/prototype_app
flutter test test/review
flutter analyze
```

Fresh reviewer must verify:
1. approval immutable/versioned;
2. no approval with unresolved blockers;
3. non-blockers carried forward;
4. reviewer/approver recorded separately;
5. no runtime mutation;
6. BugDrop provider-neutral boundary;
7. no screenshot automation or Visual AI scope creep;
8. approval files are create-only.

Fix findings before Cycle 3.

---

# Cycle 3 — Refinement + Integration Hardening (C.7)

## Task 8: RefinementBatch Domain + Repository

**Files:**
- Create: `apps/prototype_app/lib/review/refinement_batch.dart`
- Create: `apps/prototype_app/lib/review/refinement_batch_repository.dart`
- Create: `apps/prototype_app/lib/review/memory_refinement_batch_repository.dart`
- Complete: `apps/prototype_app/lib/review/file_refinement_batch_repository.dart`
- Modify: `apps/prototype_app/lib/review/review_domain_error.dart`
- Test: `apps/prototype_app/test/review/refinement_batch_test.dart`
- Test: `apps/prototype_app/test/review/refinement_batch_repository_test.dart`

**Interfaces:**

```dart
enum RefinementBatchStatus { draft, ready, inProgress, validationFailed, readyForReview, completed }
enum ChangeClassification { implementationOnly, contractImpacting }

final class ValidationCheck {
  const ValidationCheck({required this.name, required this.passed, required this.details});
}

final class RefinementBatch {
  // Stable id/client/round plus feedbackIds, intended scope,
  // proposed+confirmed classification, execution metadata,
  // validation checks, evidence refs, timestamps.
}

abstract interface class RefinementBatchRepository {
  Future<RefinementBatch?> load(String clientId, String batchId);
  Future<List<RefinementBatch>> list(String clientId);
  Future<void> create(String clientId, RefinementBatch batch);
  Future<void> replace(String clientId, RefinementBatch expectedCurrent, RefinementBatch next);
}
```

- [ ] **Step 1: Write failing lifecycle matrix tests** for `draft→ready→in_progress→validation_failed|ready_for_review→completed` and all illegal transitions.
- [ ] **Step 2: Write failing scope-freeze tests** proving feedback IDs, intended scope, and confirmed classification cannot change after `ready`.
- [ ] **Step 3: Write failing validation-evidence tests** proving `ready_for_review` requires successful checks and visual evidence when visual feedback reproduction is available.
- [ ] **Step 4: Implement domain + repositories and run tests.**
- [ ] **Step 5: Commit.**

## Task 9: C.7 Coordinator Operations + OpenCode Execution Contract

**Files:**
- Modify: `apps/prototype_app/lib/review/review_coordinator.dart`
- Create: `apps/prototype_app/lib/review/refinement_execution_result.dart`
- Create: `docs/review-refinement-opencode-contract.md`
- Test: `apps/prototype_app/test/review/review_refinement_coordinator_test.dart`

**Coordinator operations:**

```dart
Future<RefinementBatch> createDraftBatch(...);
Future<RefinementBatch> updateDraftBatch(...);
Future<RefinementBatch> confirmBatchClassification(...); // reviewer only
Future<RefinementBatch> markBatchReady(...);             // reviewer only
Future<RefinementBatch> startBatch(...);                 // agent/OpenCode
Future<RefinementBatch> recordBatchValidation(...);      // agent/OpenCode
Future<RefinementBatch> completeBatch(...);              // reviewer only
```

Required semantics:
- batch is reviewer-created, never auto-created by OpenCode;
- `ready` freezes scope;
- successful validation to `ready_for_review` moves linked eligible feedback `open→addressed` and appends an `addressed` event with `batchId`;
- validation failure leaves feedback open;
- OpenCode cannot resolve/reopen feedback, change blocking, or change confirmed classification;
- contract-impacting completed/ready-for-review work requires a new review round before subsequent approval if it changes an already approved contract;
- operations validate all candidates before writes; no false addressed transitions on batch persistence failure.

- [ ] **Step 1: Write failing authority tests** for reviewer vs agent permissions.
- [ ] **Step 2: Write failing transactional tests** for repository failure during batch/feedback update.
- [ ] **Step 3: Write failing contract-impact tests** for new-round requirement and implementation-only bypass when approved contract is unchanged.
- [ ] **Step 4: Implement coordinator operations and the OpenCode handoff document** containing exact frozen batch fields OpenCode receives and exact result fields it must return.
- [ ] **Step 5: Run focused tests and commit.**

## Task 10: End-to-End C.4–C.7 Integration + Reference Client

**Files:**
- Create: `apps/prototype_app/test/review/review_c4_c7_end_to_end_test.dart`
- Modify: `apps/prototype_app/test/review/review_reference_client_test.dart`
- Modify: `apps/prototype_app/test/review/review_architecture_test.dart`
- Modify: `apps/prototype_app/test/review/review_comparison_architecture_test.dart` only if required to preserve C.2/C.3 constraints.
- Add/update reference client review fixtures under `client-projects/examples/prototype-demo/review/` only where required for deterministic tests.

**End-to-end test sequence:**

```text
C.3 mixed decision
→ reviewer creates blocking visual feedback
→ BugDrop adapter normalizes evidence
→ reviewer creates draft batch
→ confirms classification
→ marks ready (scope frozen)
→ OpenCode starts
→ validation passes
→ batch ready_for_review
→ feedback addressed
→ reviewer resolves
→ reviewer closes round
→ review ready_for_final_review
→ approver creates approval-v1
→ new contract-impacting feedback/change
→ new review round
→ second refinement
→ approval-v2 supersedes v1 via index metadata without rewriting v1
```

Also prove:
- unresolved non-blocking feedback appears in approval snapshot;
- completed batch remains frozen;
- C.2 comparison remains neutral;
- C.3 selection/mix still persists normally;
- runtime/B.1D/B.1E remain read-only authorities;
- no automatic approval/resolution/batch creation;
- no synthetic runtime generated.

- [ ] **Step 1: Write failing integration test.**
- [ ] **Step 2: Implement only missing integration glue.**
- [ ] **Step 3: Run full review test suite and architecture tests.**
- [ ] **Step 4: Commit.**

## Task 11: Full Verification, Whole-Branch Review, and PR

Run exact canonical checks from repository root/appropriate packages; update commands only if current repository scripts differ and record the exact commands in the SDD ledger.

```bash
cd apps/prototype_app
flutter test test/review
flutter test
flutter analyze
flutter build web

cd ../../packages/agency_flutter_ui
flutter test
flutter analyze

cd ../../apps/widgetbook
flutter test
flutter analyze

cd ../..
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
py -3.12 -m tooling.design_contract.generate_resolved_themes --check
```

Also run current knowledge/workflow/prototype validators using their canonical repository commands.

Whole-branch reviewer must inspect `git diff main...HEAD` and explicitly verify:
1. single unified feedback model;
2. append-only feedback history;
3. reviewer-only blocking/resolve/reopen/classification confirmation;
4. explicit reviewer round closure;
5. immutable append-only approval versions;
6. separate reviewer/approver identity fields;
7. unresolved non-blockers carried forward;
8. provider-neutral visual evidence;
9. normalized annotation bounds;
10. reviewer-created, scope-frozen refinement batches;
11. OpenCode only marks addressed after validation;
12. no auto-resolve/auto-approve/auto-batch;
13. typed transactional failures;
14. contract-impacting changes require re-review;
15. C.3 decision authority unchanged;
16. runtime/B.1D/B.1E authority unchanged;
17. no D.1/D.2/production scope creep;
18. no accidental `pubspec.lock` commits.

After all checks pass:

```bash
git status
git push -u origin milestone-c4-c7-review-refinement
gh pr create --base main --head milestone-c4-c7-review-refinement --title "Milestones C.4-C.7: review, approval and refinement" --body-file <prepared-pr-body>
```

Do **not** merge the PR.

## SDD Review Cadence

To finish in three iterations while preserving review quality:

```text
Cycle 1 implementer
→ Cycle 1 independent reviewer
→ fix findings

Cycle 2 implementer
→ Cycle 2 independent reviewer
→ fix findings

Cycle 3 implementer
→ Cycle 3 independent reviewer
→ fix findings
→ final whole-branch reviewer
→ PR
```

Fresh implementer/reviewer subagents should be used where available. If only `general`/`explore` are available, record the model-routing deviation and continue with fresh general agents. Cross-package or persistence-sensitive work may be implemented directly by the orchestrator only when necessary, followed by fresh independent review.

## Completion Definition

C.4–C.7 are complete only when the reference client can demonstrate:

```text
feedback
→ visual evidence
→ reviewer-created refinement batch
→ OpenCode implementation + validation
→ addressed
→ reviewer resolve/reopen
→ explicit round close
→ immutable approval
→ new contract-impacting change
→ new round
→ next immutable approval version
```

with all canonical tests/validators green and an unmerged PR open against `main`.
