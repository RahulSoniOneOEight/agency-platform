# C.4–C.7 Review + Refinement — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-c4-c7-review-refinement`
- Base: C.3 merged baseline (`d3597c4`, PR #19)
- Spec A (C.4–C.5): `docs/superpowers/specs/2026-09-17-c4-c5-client-review-approval-design.md` (`ed4223d`)
- Spec B (C.6–C.7): `docs/superpowers/specs/2026-09-17-c6-c7-visual-feedback-refinement-design.md` (`ea6c08c`)
- Plan: `docs/superpowers/plans/2026-09-17-c4-c7-review-refinement-implementation.md` (`70513dd`)
- Execution model: exactly 3 large cycles (Cycle 1 = C.4; Cycle 2 = C.5+C.6; Cycle 3 = C.7+integration+PR).
- Mode: TDD, fresh implementer + fresh independent reviewer per cycle, final whole-branch review.
- Started: 2026-09-17

## Resume protocol

1. `git branch --show-current` — confirm `milestone-c4-c7-review-refinement`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first cycle not marked `ACCEPTED`; re-run its focused tests first.

## Preflight consistency scan

### Existing C.3 baseline (authority to preserve)
- `ReviewState` (v2): `version, client_id, review_round, status, selected_direction,
  screen_selections (Map<String,ReviewScreenDecision>), comments (List<ReviewComment>)` — exactly
  7 JSON keys.
- `ReviewController` requires `runtime`; single `_apply` transactional path (normalize → validate →
  save → notify); interactive ReviewState mutations only.
- `ReviewRepository` = `load(clientId) -> ReviewState?` / `save(state)`; `MemoryReviewRepository`.
- C.1–C.3 architecture guards: `review_architecture_test.dart` scans `lib/review` for
  `approved-experience`/`dart:io`/`File(`/`writeAsString`/`writeAsBytes`/`refinement`;
  `review_comparison_architecture_test.dart` pins the exact ReviewState key set and C.2 neutrality.
- `review_comments.dart` hosts the current `ReviewComment` model + Comments destination UI.

### Plan-vs-repository conflicts and resolutions
- **File I/O vs the domain guard.** Plan Tasks 5/9 require `dart:io` file-backed adapters, but the
  C.1/C.3 guard forbids `dart:io`/`File(` anywhere under `lib/review`. → **R1**.
- **ReviewState key contract.** Task 1 adds `feedback_ids`; the guard pins exactly 7 keys. → **R2**.
- **Legacy comments vs unified feedback.** Spec evolves comments into `FeedbackRecord`, but
  `ReviewComment` is part of persisted C.1–C.3 state. → **R3**.
- **Reference-client review fixtures vs Python validation.** Adding files under
  `client-projects/<client>/review/` may affect `validate_repo`. → **R9**.

### Interfaces produced by C.3 that later cycles consume
- `ReviewState`/`ReviewScreenDecision`, `effectiveScreenDirection`/`effectiveSectionDirection`,
  `normalizeReviewDecisions`, `ReviewSectionRegistry`, `ReviewSectionCompatibility`,
  `ReviewScreenAvailability`, `PrototypeRegistry.compositionFor`, `ReviewMixedPreview`,
  `ReviewController` mutations.

## Rulings

- **R1 — Persistence layout.** Domain models, typed errors, and repository *interfaces* live directly
  under `apps/prototype_app/lib/review/` (no file I/O). File-backed adapters (`dart:io`) live under
  `apps/prototype_app/lib/review/persistence/`. The domain no-file-I/O guard is narrowed to exclude
  `persistence/`, while still forbidding any write to runtime bundles or `approved-experience`.
- **R2 — ReviewState key contract.** `ReviewState` gains `feedbackIds` (`feedback_ids`), defaulting
  to empty when absent in legacy v2 state; `comments` is retained for legacy migration. Canonical key
  count becomes 8; the C.2/C.3 exact-key architecture assertion is updated to 8.
- **R3 — Unified feedback, legacy comments retained.** `FeedbackRecord` is the sole *new* feedback
  identity authority; `ReviewComment` is retained only for C.1–C.3 persisted-state compatibility and
  is not used by new feedback flows. The Comments destination evolves into the feedback panel; no
  second feedback/annotation lifecycle is created.
- **R4 — Model-routing deviation.** Only `explore`/`general` subagents are available; fresh `general`
  implementer + reviewer per cycle + final whole-branch reviewer. Cross-package/persistence-sensitive
  work may be implemented directly by the orchestrator with fresh independent review.
- **R5 — Read-only runtime.** No review/refinement/approval code writes runtime bundles or B.1D/B.1E
  artifacts; approval/feedback/batch records are separate artifacts.
- **R6 — Approval artifacts.** `approval-v<version>.yaml` is create-only; supersession is represented
  in a lightweight index, never by rewriting a snapshot.
- **R7 — Classification default.** Uncertainty in change classification defaults to
  `contract_impacting`; reviewer confirmation is authoritative and frozen at `ready`.
- **R8 — No D.1/D.2.** No screenshot automation or Visual AI QA; screenshots are consumed only as
  manually/provider-created evidence references.
- **R9 — Fixtures.** Prefer temp-directory tests for file-backed persistence; add reference-client
  review fixtures only if Python validators permit, otherwise keep them out.

## Cycle table

| Cycle | Scope | Status | Commits |
|-------|-------|--------|---------|
| 1 | C.4 review lifecycle core (Tasks 1–3) | ACCEPTED | `98c5fed` `5bd2a9a` `165d50c` `3dd269c` `288dd30` |
| 2 | C.5 approval + C.6 visual evidence (Tasks 4–7) | ACCEPTED | `763253c` `c2077ed` |
| 3 | C.7 refinement + integration hardening (Tasks 8–11) | ACCEPTED | `6ad1515` `c976c34` |

## Progress log

- 2026-09-17 — Preflight complete. Branch created from C.3 baseline; specs + plan present. R1–R9
  recorded. Untracked `pubspec.lock` files intentionally uncommitted.
- 2026-09-17 — Cycle 1 (C.4) implemented (`98c5fed` unified feedback domain; `5bd2a9a`
  coordinator/rounds; `165d50c` reviewer feedback+round UI). 469 app tests, analyze clean.
  Independent review found 3 majors: readiness bypassable via the Overview status control;
  reopen did not reconcile readiness; `createFeedback` could orphan a record. Fixed in `3dd269c`
  (coordinator-owned readiness, transactional createFeedback validating the candidate first, reopen
  reconciliation, typed errors, addressed-item reopen, legacy label) and `288dd30` (SegmentedButton
  `emptySelectionAllowed` so Overview renders at ready). Re-review blocker resolved. 418 review tests
  green. ACCEPTED.
- 2026-09-17 — Cycle 2 (C.5+C.6) implemented (`763253c` domains; `c2077ed` UI). 565 app tests,
  analyze clean. Immutable append-only `ApprovalSnapshot` + repositories (memory + file create-only),
  canonical SHA-256 `review_state_hash`, eligibility gates, separate reviewer/approver, non-blocking
  carry-forward; provider-neutral `VisualFeedbackProvider` + BugDrop adapter; `visual_attachment`
  scope-gated; approval + visual UI. Independent review: no blockers/majors, ACCEPTED.
  - **R6 amendment (M1):** approval artifacts are stored as `approval-v<version>.json`, not `.yaml`,
    to avoid adding a YAML dependency. Create-only/versioned/append-only semantics are preserved;
    supersession remains index-based. The spec permits repository-convention schemas.
  - **Deferred gate (M2):** Spec A's "no unresolved refinement dependency blocks approval" gate is
    intentionally unimplemented until C.7 batches exist; C.7 must re-add it.
  - **Tracked follow-ups (M3/M4):** immutable-record-before-state-pointer ordering can orphan a
    record if a future file-backed `ReviewRepository.save` throws (matches the plan's mandated
    ordering); `FileApprovalRepository` raises `ApprovalVersionConflict` for a client-id mismatch and
    `MemoryApprovalRepository` omits the client check; an empty `themePreset` can surface a raw
    `FormatException`. Non-blocking.
- 2026-09-17 — Cycle 3 (C.7) implemented (`6ad1515` domain+coordinator+integration; `c976c34`
  OpenCode contract). 637 app tests, analyze clean. `RefinementBatch` lifecycle + scope freeze +
  classification freeze + validation evidence; reviewer-only batch creation/confirmation/ready/
  completion; agent-only start/validate; successful validation moves linked feedback `open→addressed`
  with `batchId`; validation failure leaves feedback open; regression reopen; M2 approval gate
  re-added (unresolved contract-impacting batch blocks approval); `ContractImpactRequiresNewRound`
  path; end-to-end C.4–C.7 test. Task 11 verification: app 637 + analyze clean + web built;
  agency_flutter_ui 42 + clean; widgetbook 1 + clean; Python 283 OK + validate_repo (98 paths) +
  knowledge/workflow/prototype validators; B.1D/B.1E freshness fresh.
