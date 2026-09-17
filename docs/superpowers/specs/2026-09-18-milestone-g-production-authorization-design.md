# Milestone G — Production Authorization Design

**Date:** 2026-09-18

## Status

Approved architecture pending written-spec review. Implementation is explicitly blocked until Milestone F is merged and its canonical reference-client outputs are available for integration.

## Purpose

Milestone G introduces a distinct, immutable production-release authorization authority on top of the client-approved and QA-validated experience produced by Milestone F.

Milestone G answers one question only:

> May this exact approved build be released to this exact environment?

It does **not** deploy the application, replace client approval, redefine QA, or absorb release mechanics that belong to Milestone H.

The target flow is:

```text
ApprovalSnapshot
  ↓
QA / review blockers clear
  ↓
required validators green
  ↓
security + release evidence complete
  ↓
exact source/build identity pinned
  ↓
human release owner authorizes
  ↓
ProductionAuthorization
  ↓
Milestone H may consume the authorization
```

## Goals

1. Introduce `ProductionAuthorization` as a separate immutable authority from `ApprovalSnapshot`.
2. Require deterministic eligibility before authorization can be created.
3. Pin authorization to exact client, environment, approval, source commit, and build identity.
4. Require human release-owner authority; OpenCode, CI, Visual AI, and other agents cannot self-authorize.
5. Capture QA, validation, security, rollback, migration, and release-note evidence.
6. Make invalidation and reauthorization deterministic when relevant inputs change.
7. Reuse canonical F/C/D/E evidence instead of copying it into a parallel release-state model.
8. Give Milestone H a simple, verifiable release precondition.

## Non-goals

- No production deployment.
- No CI/CD release execution.
- No production backend integration.
- No secrets-management implementation beyond evidence/reference requirements.
- No generic release-management platform.
- No replacement of `ApprovalSnapshot`, `ReviewState`, `FeedbackRecord`, `RefinementBatch`, `QAFinding`, `QaCoordinator`, or workflow-state authority.
- No autonomous release approval.
- No modification of historical approval or authorization records.
- No generic policy engine.

---

# 1. Authority model

The authorities remain distinct:

```text
ApprovalSnapshot
  = immutable client-approved experience

ProductionEligibility
  = deterministic evaluation of release prerequisites

ProductionAuthorization
  = immutable human-granted permission for one exact release candidate

Milestone H release pipeline
  = consumer of a valid ProductionAuthorization
```

`ProductionAuthorization` must never become a replacement for client approval.

A client-approved experience may still be ineligible for production because QA, security, build identity, rollback, migration, or release evidence is incomplete.

---

# 2. Core domain model

The canonical model is an immutable, versioned authorization record.

Conceptual shape:

```yaml
version: 1
authorization_id: pa-...
authorization_version: 1
client_id: reference-commerce
environment: production

approval:
  approval_id: ...
  approval_version: 2
  review_state_hash: ...

source:
  commit_sha: ...
  build_artifact_id: ...
  build_hash: ...

qa:
  qa_run_id: ...
  status: passed
  unresolved_blocking_findings: 0

validation:
  repository_validation: passed
  workflow_validation: passed
  prototype_validation: passed
  visual_qa_validation: passed

security:
  dependency_check: passed
  secret_scan: passed
  configuration_review: passed

release:
  rollback_plan_ref: ...
  migration_plan_ref: ...
  release_notes_ref: ...

non_blocking_items:
  - ref: feedback-...
    acknowledgement: accepted_for_release

authorized_by:
  actor_id: ...
  role: release_owner
  authorized_at: ...

status: active
```

Exact field names may follow repository conventions during implementation, but the authority and identity requirements above are binding.

## Identity rules

An authorization must pin at least:

- client ID
- target environment
- approval ID/version
- approved review-state identity/hash
- source commit SHA
- build artifact identity
- build content hash where available
- QA evidence identity
- validator evidence identity
- human authorizer identity
- authorization timestamp

Authorization must never be inferred merely from branch name, tag name, latest successful CI run, or current repository state.

---

# 3. Production eligibility

Authorization creation is gated by a deterministic `ProductionEligibility` result.

Conceptually:

```text
ProductionEligibility
  ├─ eligible
  └─ blocked + reasons[]
```

Eligibility is evidence evaluation, not human authorization.

## Required eligibility gates

At minimum:

1. Current required `ApprovalSnapshot` exists.
2. Approval identity matches the release candidate's approved experience.
3. Exact source commit SHA is known.
4. Exact build artifact identity is known where a build artifact exists.
5. Required QA completed successfully.
6. No unresolved blocking QA finding relevant to the candidate.
7. No unresolved blocking review feedback relevant to the candidate.
8. Required repository/workflow/prototype/visual-QA validators are green.
9. Required security evidence is present and passing.
10. Rollback/recovery plan exists.
11. Migration plan exists when the candidate changes persistent schema/data.
12. Release notes identify acknowledged non-blocking items.
13. Target environment is explicit.
14. Human actor holds the release-owner role before authorization creation.

A blocked result must expose structured reasons, not only a Boolean.

Example:

```text
BLOCKED
- approval source identity does not match release candidate
- unresolved blocking feedback FB-017
- rollback plan missing
```

## Evidence freshness

Eligibility evidence must be tied to the candidate identity. Passing evidence for an older commit/build cannot silently authorize a newer candidate.

---

# 4. Human authorization boundary

Only an authorized human release owner may create a `ProductionAuthorization`.

OpenCode/agents may:

- gather canonical evidence
- evaluate eligibility
- explain blockers
- prepare a candidate authorization payload
- validate a proposed authorization

OpenCode/agents must not:

- create a human actor identity
- self-authorize
- auto-acknowledge blocking issues
- silently downgrade a blocking result
- fabricate security evidence
- bypass an invalid or missing approval

CI may validate an authorization but must not create one.

Visual AI and QA providers have no release-authority role.

---

# 5. Persistence and immutability

`ProductionAuthorization` is append-only and immutable after creation.

Rules:

- authorization versions are monotonic per client/environment
- an existing authorization is never rewritten to point to another SHA/build
- invalidation does not mutate historical identity/evidence
- reauthorization creates a new version
- repositories reject duplicate/conflicting versions
- exact record serialization must be deterministic

A historical authorization remains auditable even after it is no longer valid for the current candidate.

---

# 6. Authorization validity and invalidation

Authorization validity is evaluated against the candidate being released.

A valid authorization must match the release candidate on all identity-sensitive fields.

## Reauthorization-required changes

At minimum, reevaluate and normally require a new authorization when any of these change:

- source commit SHA
- build artifact identity/hash
- required ApprovalSnapshot
- contract-impacting UX/product behavior
- blocking review state
- blocking QA state
- required security evidence
- production configuration with release/security impact
- migration plan or migration content
- rollback strategy materially changes
- target environment changes

## Changes that do not automatically require client reapproval

An implementation-only change may preserve the approved experience and therefore not require a new `ApprovalSnapshot`, but a changed release SHA/build still requires production eligibility to be reevaluated and a new production authorization where identity changed.

This preserves the distinction:

```text
client reapproval != production reauthorization
```

## Historical state

The system should represent that an older authorization no longer matches a candidate without rewriting the old record. An append-only invalidation/revocation event or derived validity result is preferred over mutating the authorization body.

---

# 7. Release evidence

Milestone G captures references to evidence; it does not replace the systems that produce that evidence.

Required categories:

## Approval evidence

- `ApprovalSnapshot` ID/version
- review-state hash or equivalent approved-experience identity

## QA evidence

- QA run/reference
- required screenshot/golden/visual-QA status
- unresolved blocking findings count/refs

## Validation evidence

- repository validation
- workflow validation
- prototype validation
- visual-QA validation
- relevant F reference-client regression result where applicable

## Security evidence

At minimum conceptual checks for:

- dependency/security scan
- secret scan
- environment/configuration review

Exact tools are intentionally not mandated by G.

## Operational release evidence

- rollback/recovery plan
- migration plan when required
- release notes
- acknowledged non-blocking issues

Evidence records must identify source, status, and candidate relationship sufficiently to reject stale evidence.

---

# 8. F → G integration

Milestone F is the canonical first fixture for G.

G must consume the final F shapes rather than invent duplicate release evidence.

Expected F inputs include:

- current `ApprovalSnapshot` (expected reference path proves v1→v2 history)
- review-state identity/hash
- source commit SHA
- QA run and QAFinding state
- FeedbackRecord state
- workflow/validator evidence
- machine-readable reference-client E2E report
- human reference report as explanatory evidence only

The F machine report may be referenced as supporting regression evidence, but it is not itself approval or authorization authority.

Implementation of G must not begin until F is merged and these final shapes are inspected.

---

# 9. G → H integration

Milestone H may release only when a valid authorization exists for the exact candidate and environment.

At minimum H must reject release when:

```text
authorization missing
OR authorization does not match candidate SHA/build
OR authorization does not match target environment
OR authorization is invalidated/revoked
OR required evidence is no longer valid
```

`ProductionAuthorization` grants permission to proceed; it does not itself perform deployment.

CI/CD in H may consume and verify the authorization after the human grant.

---

# 10. Repository boundaries

The implementation should follow existing repository patterns.

Recommended logical units:

```text
production_authorization.dart / equivalent
  immutable domain record

production_eligibility.dart
  structured eligible/blocked result + reasons

production_eligibility_evaluator.dart
  deterministic gate evaluation

production_authorization_repository.dart
  persistence contract

file/memory production authorization repositories
  append-only adapters

production_authorization_coordinator.dart
  thin human-authorized orchestration boundary

schemas
  authorization + evidence/eligibility structures as needed
```

Exact locations may be adjusted after inspecting F's merged implementation, but G must not introduce a second workflow or review coordinator for existing domains.

---

# 11. Error semantics

Representative typed errors should include equivalents of:

- `ProductionAuthorizationNotEligible`
- `ProductionAuthorizationVersionConflict`
- `ProductionAuthorizationImmutable`
- `ProductionAuthorizationActorNotAllowed`
- `ProductionAuthorizationCandidateMismatch`
- `ProductionAuthorizationEnvironmentMismatch`
- `ProductionAuthorizationEvidenceMissing`
- `ProductionAuthorizationEvidenceStale`
- `ProductionAuthorizationInvalidated`

Errors should expose structured reason/evidence references where useful.

---

# 12. CI and automation boundary

CI may:

- evaluate production eligibility in read-only mode
- validate authorization schema/invariants
- verify authorization matches exact candidate SHA/build/environment
- fail release gates when authorization is absent/invalid
- run regression/security/QA validators

CI must not:

- create ProductionAuthorization
- manufacture human authorization
- mutate ApprovalSnapshot
- resolve feedback/QAFindings
- waive security evidence
- auto-acknowledge non-blocking release items

The release pipeline introduced in H may execute an already-authorized release, but cannot generate its own authorization.

---

# 13. Testing strategy

## 13.1 Domain tests

Prove:

- immutable serialization
- monotonic versions
- environment scoping
- exact SHA/build identity
- repository conflict protection
- authorized actor requirement

## 13.2 Eligibility tests

Prove authorization is blocked when:

- approval missing/stale
- source identity mismatched
- build identity missing/mismatched
- blocking feedback remains
- blocking QA remains
- validators fail
- security evidence missing/failing
- rollback plan missing
- migration evidence required but missing

Prove all reasons can be surfaced together where practical.

## 13.3 Invalidation tests

Prove:

- SHA-A authorization cannot authorize SHA-B
- target-environment mismatch fails
- new required ApprovalSnapshot invalidates candidate use of old authorization
- security/QA regression blocks candidate
- historical authorization remains immutable
- reauthorization creates a new version

## 13.4 Authority-boundary tests

Prove:

- OpenCode/agent cannot self-authorize
- CI cannot create authorization
- ApprovalSnapshot remains separate
- QA does not grant release permission
- workflow state does not become release authorization

## 13.5 F reference-client integration tests

Using the merged F fixture, prove:

```text
F approved + QA clean + validators clean
→ eligible
→ human release authorization
→ exact candidate can be consumed by H boundary
```

Also prove a changed candidate requires reevaluation/new authorization without unnecessary client reapproval when the change is implementation-only.

---

# 14. Implementation cycles

Milestone G should be implemented in three SDD cycles after F is merged.

## Cycle G.1 — Domain + Eligibility

Build:

- `ProductionAuthorization`
- `ProductionEligibility`
- eligibility evaluator
- repositories/persistence
- schemas
- actor/role enforcement
- deterministic serialization/versioning

Exit criteria:

- immutable/versioned authorization domain works
- eligibility returns deterministic structured blockers
- agents/CI cannot use the creation path as human release owner

## Cycle G.2 — Evidence + Invalidation

Build:

- exact source/build pinning
- QA/validation/security evidence references
- rollback/migration/release-note requirements
- non-blocking acknowledgement structure
- validity/invalidation/revocation model
- reauthorization behavior

Exit criteria:

- stale/mismatched evidence is rejected
- candidate identity changes require reevaluation
- historical authorizations remain immutable

## Cycle G.3 — F Integration + H Handoff

Build/prove:

- merged F reference-client integration
- eligibility against canonical F evidence
- human authorization orchestration
- CI read-only validation
- exact candidate/environment consumption boundary for H
- docs and full regression suite

Exit criteria:

- F→G→H boundary is deterministic and auditable
- no deployment occurs in G
- final whole-branch review has zero blockers/majors or residuals are explicitly ruled/documented

---

# 15. Acceptance criteria

Milestone G is complete when all are true:

1. `ProductionAuthorization` exists as a distinct immutable authority.
2. Authorization is versioned and append-only.
3. Authorization pins exact client/environment/approval/SHA/build identity.
4. Deterministic eligibility runs before authorization.
5. Eligibility returns structured blocking reasons.
6. Current approval is required.
7. Relevant blocking review feedback prevents eligibility.
8. Relevant blocking QA prevents eligibility.
9. Required validators must pass.
10. Security evidence is required and candidate-specific.
11. Rollback evidence is required.
12. Migration evidence is required when applicable.
13. Known non-blocking items are explicitly acknowledged/documented.
14. Only a human release owner can authorize.
15. OpenCode/agents cannot self-authorize.
16. CI cannot create authorization.
17. Authorization does not deploy anything.
18. Candidate SHA/build changes trigger reevaluation and, where identity changes, new authorization.
19. Implementation-only changes need not force client reapproval but do not bypass production reauthorization.
20. Historical authorizations remain immutable/auditable.
21. F reference-client evidence is consumed rather than duplicated.
22. H can deterministically verify an authorization for exact candidate/environment.
23. Existing C/D/E/F authorities remain unchanged.
24. No generic release/BPM/policy platform is introduced.

---

# 16. Final authority summary

```text
GitHub
  → durable repository/audit source

ApprovalSnapshot
  → client-approved experience

QAFinding / FeedbackRecord / validators
  → release-input evidence

ProductionEligibility
  → deterministic readiness evaluation

Human release owner
  → authorization decision authority

ProductionAuthorization
  → immutable permission for exact candidate/environment

Milestone H
  → productionization + authorized release execution
```

Milestone G creates the release-permission boundary. It does not become the release engine.