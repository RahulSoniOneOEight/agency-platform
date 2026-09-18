# Milestone G — Production Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an immutable, human-granted ProductionAuthorization authority with deterministic eligibility, candidate-specific evidence, invalidation/reauthorization, F reference-client integration, and a read-only H release gate.

**Architecture:** Implement G as a repository-native Python release-control domain under `tooling/production_authorization/`. It consumes C/D/E/F evidence by reference, persists append-only authorization records under each client project, and exposes read-only validation for CI/H. It does not alter ApprovalSnapshot, ReviewState, QA, workflow-state, or deployment behavior.

**Tech Stack:** Python 3.12, dataclasses, pathlib, json/jsonschema, existing repository validators and GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-18-milestone-g-production-authorization-design.md`

## Global Constraints

- `ProductionAuthorization` is separate from `ApprovalSnapshot`.
- Authorization creation requires an explicit human actor with role `release_owner`.
- Agents, OpenCode, CI, QA providers, and workflow runtime cannot self-authorize.
- Authorization is immutable, append-only, environment-scoped, and candidate-specific.
- A changed source SHA/build identity requires production reevaluation even when client reapproval is unnecessary.
- CI is read-only authority validation; G performs no deployment.
- F report/evidence are supporting inputs only and must not become duplicate approval authority.
- Existing C/D/E/F authority models remain unchanged.
- No generic policy/BPM/release-management engine.
- No pubspec.lock policy change.

---

## Cycle G.1 — Domain + Eligibility

### Task 1: Core production-authorization domain

**Files:**
- Create: `tooling/production_authorization/__init__.py`
- Create: `tooling/production_authorization/errors.py`
- Create: `tooling/production_authorization/models.py`
- Create: `client-projects/schema/production-authorization.schema.json`
- Create: `client-projects/schema/production-release-candidate.schema.json`
- Test: `tooling/validation/test_production_authorization_models.py`

**Interfaces:**
- Produces `ReleaseActor`, `EvidenceRef`, `ReleaseCandidate`, `ProductionAuthorization`, `AuthorizationStatus`, canonical JSON helpers, and typed errors.
- `ReleaseCandidate` pins client, environment, approval version/hash/source identity, candidate SHA, build id/hash, QA evidence, validator evidence, security evidence, rollback/migration/release-notes refs, and acknowledged non-blocking item ids.
- `ProductionAuthorization` pins the exact candidate identity plus human authorizer and monotonic authorization version.

- [ ] Write failing serialization/invariant tests covering canonical key order/content, immutable tuples/mappings, valid SHA/hash formats, environment scoping, positive versions, and human release-owner identity.
- [ ] Run `python -m unittest tooling.validation.test_production_authorization_models -v` and verify failures.
- [ ] Implement the minimal domain/errors and JSON schemas.
- [ ] Re-run the focused test and verify PASS.
- [ ] Commit as `feat: add production authorization domain`.

### Task 2: Append-only repositories

**Files:**
- Create: `tooling/production_authorization/repository.py`
- Test: `tooling/validation/test_production_authorization_repository.py`

**Interfaces:**
- Produces `ProductionAuthorizationRepository` and `FileProductionAuthorizationRepository`.
- Storage: `client-projects/<client>/release/production-authorizations/authorization-vNNNN.json`.
- `create()` is create-only; `list()` is deterministic ascending version; duplicate/out-of-order version raises `ProductionAuthorizationVersionConflict`.

- [ ] Write failing tests for create/list, duplicate version, out-of-order version, byte immutability, deterministic serialization, and per-environment version streams.
- [ ] Run focused tests and verify failures.
- [ ] Implement repository using atomic create-only writes; never overwrite an existing authorization.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `feat: add append-only production authorization repository`.

### Task 3: Deterministic eligibility evaluator

**Files:**
- Create: `tooling/production_authorization/eligibility.py`
- Test: `tooling/validation/test_production_authorization_eligibility.py`

**Interfaces:**
- Produces `EligibilityReason`, `ProductionEligibility`, and `evaluate_eligibility(candidate)`.
- Returns all deterministic blockers in stable code order.
- Required gates: current approval identity, exact candidate SHA/build, QA pass/no blocking QA, no blocking review feedback, required validators pass, security evidence pass, rollback present, migration present when required, release notes present, explicit environment.

- [ ] Write failing tests for every required blocker and multi-reason aggregation.
- [ ] Run focused tests and verify failures.
- [ ] Implement evaluator with stable reason codes and no side effects.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `feat: add production eligibility evaluation`.

## Cycle G.2 — Evidence + Invalidation

### Task 4: Human authorization coordinator

**Files:**
- Create: `tooling/production_authorization/coordinator.py`
- Test: `tooling/validation/test_production_authorization_coordinator.py`

**Interfaces:**
- Produces `ProductionAuthorizationCoordinator.authorize(candidate, actor, authorized_at)`.
- Calls eligibility first, rejects non-human/non-release-owner actors, assigns next environment-specific version, persists exactly once.
- Never creates/changes ApprovalSnapshot, feedback, QA finding, or workflow state.

- [ ] Write failing tests for eligible human authorization, blocked eligibility, agent/CI rejection, version allocation, and no partial write on failure.
- [ ] Run focused tests and verify failures.
- [ ] Implement coordinator.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `feat: add human production authorization boundary`.

### Task 5: Validity, invalidation, and reauthorization

**Files:**
- Create: `tooling/production_authorization/validity.py`
- Create: `client-projects/schema/production-authorization-event.schema.json`
- Test: `tooling/validation/test_production_authorization_validity.py`

**Interfaces:**
- Produces `AuthorizationValidity`, `evaluate_authorization(authorization, candidate, invalidation_events)`, and append-only invalidation event model.
- Old authorization body is never mutated.
- Candidate SHA/build/environment/approval/evidence mismatch or explicit invalidation makes authorization unusable; reauthorization is a new version.

- [ ] Write failing tests for SHA-A→SHA-B, build mismatch, environment mismatch, newer required approval, QA/security regression, explicit invalidation, immutable history, and successful v2 reauthorization.
- [ ] Run focused tests and verify failures.
- [ ] Implement validity/event model.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `feat: add production authorization validity and invalidation`.

### Task 6: Candidate evidence loader and schemas

**Files:**
- Create: `tooling/production_authorization/evidence.py`
- Create: `client-projects/schema/production-release-evidence.schema.json`
- Test: `tooling/validation/test_production_authorization_evidence.py`

**Interfaces:**
- Produces strict evidence parsing and freshness checks.
- Evidence refs carry source/status/candidate_sha/build_hash where identity-sensitive.
- Rejects stale/mismatched QA, validation, security, rollback, migration, or release-notes evidence.

- [ ] Write failing tests for missing, malformed, stale, mismatched, and passing evidence.
- [ ] Run focused tests and verify failures.
- [ ] Implement parser/freshness checks.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `feat: add candidate-specific release evidence`.

## Cycle G.3 — F Integration + H Handoff

### Task 7: Reference-client G fixture and F integration

**Files:**
- Create: `client-projects/reference-commerce/release/candidate.json`
- Create: `client-projects/reference-commerce/release/evidence/security.json`
- Create: `client-projects/reference-commerce/release/evidence/rollback.md`
- Create: `client-projects/reference-commerce/release/evidence/migration.json`
- Create: `client-projects/reference-commerce/release/evidence/release-notes.md`
- Create: `tooling/production_authorization/reference_client.py`
- Test: `tooling/validation/test_production_authorization_reference_client.py`

**Interfaces:**
- Reads merged F `reference-report.json` and evidence files.
- Uses Approval v2 identity (version/review-state hash/source SHA) as the reference candidate approval identity.
- F report remains supporting evidence; it is not copied as approval authority.
- Produces a deterministic eligible candidate for production and a changed implementation-only candidate that requires new production authorization but no new client approval.

- [ ] Write failing tests for F evidence consumption, Approval v2 identity binding, QA/feedback/validator blocker derivation, no duplicate authority files, implementation-only candidate behavior, and tamper rejection.
- [ ] Run focused tests and verify failures.
- [ ] Implement fixture/loader.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `feat: integrate production authorization with reference client`.

### Task 8: Read-only validator and H release gate

**Files:**
- Create: `tooling/production_authorization/validate.py`
- Create: `tooling/production_authorization/release_gate.py`
- Test: `tooling/validation/test_production_authorization_release_gate.py`
- Modify: `tooling/validation/validate_repo.py`
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- `validate_client_authorizations(root, client_dir)` returns deterministic errors only.
- `verify_release_gate(authorization, candidate)` succeeds only for exact client/environment/SHA/build and valid non-invalidated authorization.
- CI validates but never authorizes or mutates release state.

- [ ] Write failing tests for absent authorization, mismatched SHA/build/environment, invalidated authorization, valid exact candidate, and CI read-only behavior.
- [ ] Run focused tests and verify failures.
- [ ] Implement validator/release gate and wire them into repository validation + CI tests.
- [ ] Re-run focused and repository validator tests.
- [ ] Commit as `feat: add production authorization release gate`.

### Task 9: Reference authorization proof and documentation

**Files:**
- Create: `client-projects/reference-commerce/release/production-authorizations/authorization-v0001.json`
- Create: `client-projects/reference-commerce/release/authorization-proof.json`
- Create: `docs/production-authorization.md`
- Modify: `AGENTS.md`
- Test: `tooling/validation/test_production_authorization_authority_boundaries.py`

**Interfaces:**
- The committed reference authorization is deterministic fixture evidence representing an explicit synthetic human release owner for the reference client only.
- It must not imply autonomous authorization in real-client workflows.
- Documentation defines F→G→H handoff and human-only creation rule.

- [ ] Write failing authority-boundary tests proving agent/CI cannot authorize, ApprovalSnapshot/QA/workflow state remain separate, reference fixture is synthetic, and G performs no deployment.
- [ ] Run focused tests and verify failures.
- [ ] Generate the deterministic reference authorization/proof through the coordinator test fixture path and document the boundary.
- [ ] Re-run focused tests and verify PASS.
- [ ] Commit as `docs: prove production authorization boundary`.

### Task 10: Full regression and whole-branch review

**Files:**
- Modify only files required to resolve verified findings.
- Create/update: `docs/superpowers/ledgers/2026-09-18-milestone-g-production-authorization-ledger.md`

- [ ] Run `python -m unittest discover tooling/validation -v`.
- [ ] Run `python tooling/validation/validate_repo.py`.
- [ ] Run knowledge/workflow/prototype/visual-QA/reference-client validators and B.1D/B.1E freshness checks.
- [ ] If Flutter code is untouched, record that Flutter regression is covered by unchanged F/main baseline plus CI; if touched, run the canonical Flutter test/analyze/build gates.
- [ ] Review `git diff origin/main...HEAD` against all 24 G acceptance criteria and authority boundaries.
- [ ] Fix every blocker/major and re-run scoped tests.
- [ ] Record exact counts, commits, rulings, deviations, residual minors, final SHA, and PR/CI status in the ledger.
- [ ] Push branch and open PR against `main`; do not merge without explicit user authorization.
