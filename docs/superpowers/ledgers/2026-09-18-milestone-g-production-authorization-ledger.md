# SDD ledger — plan: docs/superpowers/plans/2026-09-18-milestone-g-production-authorization-implementation.md

- 2026-09-18 — G planning checkpoint. Milestone F PR #23 merged at `1d81ff107568c6f06ed4c7e3e7b0c2207d6e11f9`.
- Ruling RG1: G core is implemented in Python under `tooling/production_authorization/` because production release authorization is a repository/CI control-plane concern and F evidence is already machine-readable Python/JSON; Flutter review authorities remain untouched. Cost if wrong: H may later need a thin Dart/UI adapter, but authority remains reusable.
- Ruling RG2: The F machine report is supporting regression evidence, not ApprovalSnapshot authority. The release candidate pins approval version/hash/source identity explicitly. Cost if wrong: real-client integration will require the canonical ApprovalRepository adapter in H/production tooling.
- Ruling RG3: Reference-commerce may commit a deterministic synthetic authorization fixture proving the model, but real-client authorization creation remains human-only and never occurs in CI.

## Execution

- Cycle G.1 — Domain + Eligibility: COMPLETE.
  - `a05560baa16a417dd0b2decc8481718b92d04316` — domain models, schemas, append-only repository, eligibility evaluator, focused tests.
- Cycle G.2 — Evidence + Invalidation: COMPLETE.
  - `adeb20dfaf8105d25677e065670dff2827085111` — human authorization coordinator, evidence freshness, invalidation events, reauthorization semantics, tests.
- Cycle G.3 — F Integration + H Handoff: COMPLETE.
  - `ffc3667e827f9cbc92e8cafe624cb5428afe1f62` — merged-F reference candidate/evidence, synthetic human authorization fixture, exact-candidate H release gate, docs.
  - `2b10a7e40aa1d4da3df69ba2be9aa54c1ff6071d` — repository validator/CI integration and G integration/boundary tests.
  - `15f499c0733f40fc4a31fd3fede729d8dee48225` — whole-branch review fix pinning authorization to QA/validator/security identities and operational release evidence, plus strict evidence deserialization.

## Review findings

- Whole-branch review found one material release-integrity gap before delivery: validity originally pinned approval/SHA/build but did not compare the authorization's evidence IDs and release-plan refs with the current candidate. Fixed in `15f499c`; tests now cover changed validator evidence and changed release notes requiring reauthorization.
- No existing C/D/E/F authority file was modified. G remains a separate Python repository/CI control-plane authority and performs no deployment.
- RG4 deviation: this chat environment does not expose the user's local OpenCode subagent runtime, so G was executed directly against GitHub rather than dispatching OpenCode subagents. The spec/plan boundaries and test/review gates were still followed; PR remains unmerged for human review.

## Verification

- Repository Validation on head `15f499c0733f40fc4a31fd3fede729d8dee48225`: **838 tests OK**.
- `validate_repo.py`: **170 required paths**; runtime bundles, Flutter bindings, themes, refinement notes, F reference client, and G production authorization all valid.
- Knowledge Platform, workflow runtime, prototype platform, Visual QA, F reference-client validator: PASS.
- Production authorization validator: PASS — exact candidate/environment is human-authorized and evidence is fresh.
- Flutter CI: required regression check; final status recorded in PR checks.
- PR: #24, `Milestone G - Production Authorization`, base `main`; do not merge without explicit authorization.

## Acceptance review

All 24 Milestone G acceptance criteria are represented in implementation/tests:
1. distinct immutable authority
2. versioned append-only records
3. exact client/environment/approval/SHA/build pinning
4. eligibility before authorization
5. structured blocker reasons
6. current approval required
7. blocking review feedback blocks
8. blocking QA blocks
9. validators must pass
10. security evidence candidate-specific
11. rollback evidence required
12. migration evidence required when applicable
13. non-blocking items acknowledged
14. human release owner only
15. agents/OpenCode cannot self-authorize
16. CI validates but cannot authorize
17. G does not deploy
18. changed SHA/build requires reevaluation/new authorization
19. implementation-only change preserves client approval but not production authorization
20. historical authorization remains immutable/auditable
21. F evidence consumed by reference
22. H exact-candidate release gate
23. C/D/E/F authorities unchanged
24. no generic release/BPM/policy engine
