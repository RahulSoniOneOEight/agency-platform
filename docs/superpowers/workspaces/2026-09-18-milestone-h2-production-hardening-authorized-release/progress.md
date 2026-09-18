# Milestone H.2 — SDD Progress Ledger

Plan: `docs/superpowers/plans/2026-09-18-milestone-h2-production-hardening-authorized-release-implementation.md`
Spec: `docs/superpowers/specs/2026-09-18-milestone-h2-production-hardening-authorized-release-design.md`
Branch: `milestone-h2-production-hardening-release`
Base: `b3b18ff1877e72447381c3e7bdfaf31889616f78` (H.2 design + plan docs on top of H.1 `2ab3243`)

## Execution model

Subagent-driven development: one fresh implementer per task, an independent
reviewer after every task (spec-compliance verdict + code-quality verdict), a
scoped fix loop with re-review, and one whole-branch review at the end.

**Routing deviation:** only `general`/`explore` subagents are exposed in this
session. The plan's `@strategy` / `@builder` / `@worker` / `@reviewer` model
routing is approximated with fresh `general` implementers and separate fresh
`general` reviewers. No implementer ever reviews its own task. This mirrors the
recorded H.1 deviation.

## Task status

| Task | Title | Status | Commit | Tests | Review |
|------|-------|--------|--------|-------|--------|
| 1 | Provider-neutral operations core | complete | `f51ad29`, `7f011ab` (fix) | 30 | clean after fix |
| 2 | ReleaseCandidate + ReleaseRecord models | complete | `0edfdb2`, `a200b89`, `1822967` (fixes) | 80 | clean after fixes |
| 3 | Sentry / GA4 / Cloudflare reference adapters | complete | `26fcd38`, `1549132` (fix) | 59 (20+21+18) | clean after fix |
| 4 | Hardening policies + validators | complete | `97849ea` | 12 | clean |
| 5 | Candidate build manifest + artifact integrity | pending | | | |
| 6 | Hardening gates | pending | | | |
| 7 | Staging deployment, smoke, hardening report | pending | | | |
| 8 | Bridge H.2 candidate to G authorization | pending | | | |
| 9 | Production release, smoke, telemetry, ReleaseRecord | pending | | | |
| 10 | Recovery coordinator | pending | | | |
| 11 | Production-release workflow + no-rebuild | pending | | | |
| 12 | Workflow integration + authority boundaries | pending | | | |
| 13 | Reference-commerce e2e proof | pending | | | |
| 14 | Regression, whole-branch review, ledger, PR | pending | | | |

## Preflight interface scan (completed)

- Toolchain: Python 3.12.10 (`py -3.12`), Flutter 3.47.4 stable, Dart 3.13.3.
- G release gate: `tooling.production_authorization.release_gate.verify_release_gate(authorization, candidate, invalidation_events=()) -> None`; pass/fail by exception. H.2 MUST call it and MUST NOT call `ProductionAuthorizationCoordinator.authorize` or `FileProductionAuthorizationRepository.create`.
- G candidate identity = full canonical JSON of all candidate fields (pretty, sorted). No expiry concept.
- H.1 identity convention: compact canonical JSON (`sort_keys=True, separators=(",", ":")`) + `sha256:` prefix, stripping the identity key. Copy-per-module (no shared helper).
- Hardening evidence dir: `client-projects/reference-commerce/production/evidence/` (currently only `h1-foundation-report.json`).
- Config allowlist: `tooling.production.validate_config.ALLOWED_KEYS`; forbidden fragments list.
- Migrations: `supabase/migrations/*.sql`, 12–14 digit version, `-- migration-class:` header.
- Workflow runtime: stage list is fixed at 8 in `tooling/workflow/state.py::STAGES`; stage-09 requires edits to state, schema (2 enums), router, validate_workflow, 08 contract/MD, and the fixed-eight tests.
- CI: `validate.yml` has a single long unittest line (must append new modules) plus per-validator steps; `flutter-ci.yml` auto-discovers packages under `packages/**` via `find`.
- New Dart packages auto-included by `melos.yaml` glob; no `pubspec.lock` is ever committed.

## Rulings / deviations

- **R1 (routing):** `general` subagents used for both implementer and reviewer roles; recorded deviation above.
- **R2 (synthetic authorization fixture):** the H.2 reference proof requires a new explicit synthetic-human G authorization fixture bound to the exact H.2 candidate (spec §22, AC 42). It is a static data fixture representing a human release-owner action; no H.2 code path may create, grant, or mutate `ProductionAuthorization` (AC 39). `tooling/release` must not import `ProductionAuthorizationCoordinator` or the repository `create`.
- **R3 (Task 1):** `HardeningFinding` and `RecoveryPolicy` lost `const` constructors in the fix loop to gain real list immutability (`List.unmodifiable`). The plan's illustrative snippet (`...implementation.md:198`) still shows `const` and is intentionally left untouched as the frozen design; the compiled contract is authoritative.
- **R4 (Task 1):** `packages/agency_operations_core/pubspec.lock` is generated untracked by test runs and is never committed; no `pubspec.lock` policy change.
- **R5 (Task 1):** `RecoveryPolicy.requireReversibleMigrationForDatabaseRollback` renamed to `allowDatabaseReverseMigration` (positive semantics: DB reversal allowed only when true AND the migration is explicitly reversible).
- **R6 (Task 2):** canonical identity hashing byte-matches Python `json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=True)` + `sha256:` (cross-language golden vectors pinned); numeric values are rejected in identity payloads. `crypto: ^3.0.0` added as a provider-neutral dependency.
- **R7 (Task 2):** `migrationSetIdentity` is an H.2-specific derived binding field (not in spec §7's base list) and is required by `h2-release-candidate.schema.json`.
- **R8 (Task 3):** reference adapters prove the provider-neutral contracts through narrow injectable transports; default concrete transports use an injectable HTTP seam rather than bundling vendor SDK packages, keeping normal PR CI dependency-light and credential-free. This satisfies "provider SDK/HTTP details remain inside adapter packages" and the no-leak/credential-free constraints.
- **R9 (Task 4):** hardening policy validator is the sole policy authority; no network. Parked minors: duplicate-YAML-key shadowing, non-mapping `production_authorization` shape, blocking/advisory severity overlap, and only 4 of 7 budgets asserted in the test (validator enforces all 7).
- **R10 (Task 5, planned):** the committed H.2 reference candidate is generated from a committed deterministic artifact fixture tree under `client-projects/reference-commerce/production/release/artifact-fixture/`; the real `candidate-build` workflow builds the actual Flutter Web artifact and uploads a real manifest/candidate without committing them. This keeps PR CI deterministic and credential-free.
- **R11 (Task 5, planned):** Python `candidate_identity` mirrors the Dart canonical-hash convention (ensure_ascii=True, sort_keys, compact separators) and is proven by the shared golden vectors. Python `migration_set_identity` follows the plan's ordered (path + normalized content hash) pair convention; the Dart `migrationSetIdentity` is a runtime representation not used by the Python release gate.
- **R12:** TBD as tasks progress.
- **R13 (Task 5, fix loop):** reference-commerce has no `approved-experience.yaml`; its approved experience is authoritatively represented by the F review/approval evidence at `client-projects/reference-commerce/reference-e2e/evidence/review-approval-evidence.json`. The candidate's `approved_experience_ref` points at that existing file. H.2 must never create approval authority, so no `approved-experience.yaml` is generated for the client; the approval ref is bound by existence only and validated by the test suite.

## Reviewer findings / fix loop

- **Task 1 (1 Important):** `enum ReleaseOutcome { healthy, degraded, failed }` (plan line 180) was missing. Fixed in `7f011ab`; re-review PASS, 0 Critical / 0 Important. Parked minors: redundant test coverage in deployment/observability suites; stale `const` example in the plan doc.
- **Task 2 (1 Important + 1 Important):** cross-language canonicalization divergence (`ensure_ascii`) and `U+007F` escaping. Fixed in `a200b89` and `1822967`; re-review PASS with an independent full-BMP/supplementary-plane sweep, 0 Critical / 0 Important. Parked minors: `pubspec.lock` not gitignored (intentional, R4); UTF-16 vs code-point key sort for supplementary-plane map keys (documented, not reachable).
- **Task 3 (1 Important):** Sentry/GA4 `setReleaseContext` bypassed redaction/rejection and could override identity tags. Fixed in `1549132`; re-review PASS, 0 Critical / 0 Important. Parked minors: Sentry release-context reserved keys (`userId`/`correlationId`) can survive when unset; Cloudflare no-build regex is narrow; `pubspec.lock` gitignore.
