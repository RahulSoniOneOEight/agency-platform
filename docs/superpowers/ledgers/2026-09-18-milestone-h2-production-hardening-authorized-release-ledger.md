# Milestone H.2 — Production Hardening & Authorized Release Ledger

Plan: `docs/superpowers/plans/2026-09-18-milestone-h2-production-hardening-authorized-release-implementation.md`
Spec: `docs/superpowers/specs/2026-09-18-milestone-h2-production-hardening-authorized-release-design.md`
Branch: `milestone-h2-production-hardening-release`
Base: `origin/main` (H.1 merged, `3653cfc`)
Reviewed code tip: `9b77d72` (Task 13).
Delivery: pushed as `milestone-h2-production-hardening-release`; PR **#26** (`https://github.com/RahulSoniOneOEight/agency-platform/pull/26`), not merged.
Final CI (PR #26): `validate-structure` pass, `credential-free-validation` pass, `flutter-checks` pass, `candidate-build` pass, `live-hardening` skipped (no live secrets, by design).

H.2 is one milestone with H.2A Operational Hardening → Milestone-G
`ProductionAuthorization` for the exact candidate → H.2B Authorized Release. It
does not create, mutate, or substitute for `ProductionAuthorization`, does not
redesign the approved experience, and performs no live external deployment in
this delivery (intentionally stopped pending explicit human approval).

## Execution model

Subagent-driven development: one fresh implementer per task, an independent
reviewer after every task (spec-compliance verdict + code-quality verdict), a
scoped fix loop with re-review, and one whole-branch final review.

**Routing deviation (R1):** only `general`/`explore` subagents were exposed in
this session. The plan's `@strategy`/`@builder`/`@worker`/`@reviewer` model
routing was approximated with fresh `general` implementers and separate fresh
`general` reviewers. No implementer ever reviewed its own task. This mirrors the
recorded H.1 deviation.

## Cycles and tasks

### Cycle H.2A-1 — Operations contracts and exact candidate identity

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 1. Provider-neutral operations core | `f51ad29`, `7f011ab` | 30 | clean after fix (1 Important) |
| 2. Exact candidate + ReleaseRecord identities | `0edfdb2`, `a200b89`, `1822967` | 80 | clean after fixes (2 Important) |
| 3. Sentry / GA4 / Cloudflare adapters | `26fcd38`, `1549132` | 59 (20+21+18) | clean after fix (1 Important) |

### Cycle H.2A-2 — Hardening policies, staging proof, candidate freeze

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 4. Hardening policies + validators | `97849ea` | 12 | clean |
| 5. Candidate build manifest + artifact integrity | `04ade9c`, `fb9eb8f` | 33 | clean after fix (1 Important) |
| 6. Security/perf/a11y/analytics/observability/migration gates | `7c56162`, `3b90dac` | 72 | clean after fix (2 Important) |
| 7. Staging deploy, smoke, hardening report | `f25fae2`, `c090af1`, `d94deaa` | 43 | clean after 2 fixes (3 Important) |

### Cycle H.2B — Authorized release, health, recovery

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 8. Bridge H.2 candidate to G authorization | `0c590c7`, `451a8a8`, `5bbbb59`, `366cbbd` | 34 | clean after fixes |
| 9. Production release, smoke, telemetry, ReleaseRecord | `b9e2a5d`, `678e003`, `901c12e` | 69 | clean after fixes (1 Important) |
| 10. Recovery coordinator | `ab66d22`, `c26d0c3`, `ef905e2` | 53 | clean after 2 fixes (2 Important) |
| 11. Production-release workflow + no-rebuild | `5d89e6f`, `79ab90b`, `c933551` | 43 | clean after fixes |

### Cycle H.2C — Workflow integration, reference proof, final

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 12. Workflow integration + authority boundaries | `707df54`, `300a7ea` | 83 | clean after fix (1 Critical) |
| 13. Reference-commerce e2e proof | `9b77d72` | 42 | clean |
| 14. Full regression, whole-branch review, ledger, PR | this ledger | see Verification | 0 blockers / 0 majors |

## Reviewer findings that changed the code

- **Task 1 (Important):** `enum ReleaseOutcome` missing → added.
- **Task 2 (2 Important):** cross-language canonicalization diverged from the repo's Python `ensure_ascii=True` convention, then `U+007F` was still escaped differently → fixed and pinned with cross-language golden vectors.
- **Task 3 (Important):** `setReleaseContext` bypassed redaction/rejection and could override identity tags → fixed with a single redaction choke point and identity-wins merge order.
- **Task 5 (Important):** `verify_candidate_artifact` could not verify the migration-set identity → embedded `migration_set_entries`; also pinned the fixture source/version and bound a real approval ref.
- **Task 6 (2 Important):** security gate failed open on an omitted `release_relevant` flag and on a malformed `findings` container → fail-closed.
- **Task 7 (3 Important):** hardening-report validator trusted metadata; `staging_smoke_ref` was unbound; live smoke targeted a placeholder URL → re-derive from committed gate evidence, bind the smoke ref, wire the real staging URL.
- **Task 9 (Important):** `validate_release_record` trusted report metadata → re-validate smoke/telemetry content; then bind hardening/staging/deployment evidence.
- **Task 10 (2 Important):** recovery validator did not re-derive execution results, and DB reversal was self-asserted → re-derive results and bind reversibility to committed migration-class authority.
- **Task 11 (Important):** the no-rebuild/ordering static guard was evadable → whole-workflow per-step token scanning; denylist limits accepted as defense-in-depth.
- **Task 12 (Critical):** `workflow-execution-manifest.schema.json` and `workflow-stage-contract.schema.json` stage enums were not updated for `release` → added, plus schema-coverage tests and CI wiring.

## Rulings / deviations

- **R1:** `general` subagents used for implementer and reviewer roles (recorded routing deviation).
- **R2:** the H.2 reference proof requires a new explicit synthetic-human G authorization fixture for the exact H.2 candidate (spec §22 / AC 42). It is committed data representing a human release-owner action; no H.2 code path creates, grants, or mutates `ProductionAuthorization` (AC 39). It lives at `release/reference-proof/production-authorization-v0001.json` — outside `production/` and outside the G repository's scanned `release/production-authorizations/<env>/`, so G validation is unchanged.
- **R3:** `HardeningFinding`/`RecoveryPolicy` lost `const` constructors to gain real list immutability; the plan's illustrative `const` snippet is stale.
- **R4:** `pubspec.lock` files are generated untracked and never committed; no `pubspec.lock` policy change.
- **R5:** `RecoveryPolicy.requireReversibleMigrationForDatabaseRollback` renamed to `allowDatabaseReverseMigration`.
- **R6:** canonical identity hashing byte-matches Python `json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=True)` + `sha256:`; numeric values are rejected in identity payloads.
- **R7:** `migrationSetIdentity` (Dart) and `migration_set_identity` (Python, ordered `{path, sha256}` entries) are H.2-specific derived bindings.
- **R8:** reference adapters prove the contracts through narrow injectable transports; concrete default transports use an injectable HTTP seam rather than bundling vendor SDK packages (keeps PR CI dependency-light and credential-free).
- **R9:** the hardening policy validator is the sole policy authority; no network.
- **R10:** the committed H.2 reference candidate is generated from a committed deterministic `artifact-fixture/` tree; the real `candidate-build` workflow builds the actual Flutter Web artifact and uploads it without committing.
- **R11:** Python `candidate_identity` mirrors Dart; Python `migration_set_identity` follows the ordered-pair convention.
- **R12:** the H.2 reference candidate binds `approved_experience_ref` to the existing F approval evidence (`reference-e2e/evidence/review-approval-evidence.json`); reference-commerce has no `approved-experience.yaml`, and H.2 must not create approval authority.
- **R13:** `migration_set_entries` embedded so the filesystem-free verifier can recompute the migration-set identity.
- **R14:** hardening gates are offline/deterministic; `aggregate_gate` blocks only on `blocking && open`.
- **R15:** deterministic fixture mode uses committed fixture gate evidence + fixture staging deployment; live workflows regenerate.
- **R16 (X1):** the H.1 authority tests were reconciled to allow `production/hardening`, `production/release`, and the pointer ref, while still forbidding an authorization BODY under `production/`, code-created authorization, duplicated review/approval/QA authority, and production deployment artifacts.
- **R17 (X2):** `.gitattributes` pins `client-projects/**/reference-e2e/report/*.md` to `text eol=lf` so deterministic byte comparison passes on Windows checkouts.
- **R18 (final-review M3):** spec §8 places migrations after promotion while §20 and the implemented workflow apply schema before app; the implemented order (migrations before deploy) is retained and the spec text is noted as inconsistent.
- **R19 (final-review M2):** the production-release workflow now runs the offline `tooling.release.validate` chain before the digest check/deploy, so the H.2→G binding is enforced in the live workflow, not only offline.
- **R20 (final-review M4):** untracked `pubspec.lock` files remain uncommitted by policy (R4).

## Verification (final)

Python (`py -3.12`):

- `-m unittest discover tooling/validation` — **1346 tests, OK**
- `tooling/validation/validate_repo.py` — **exit 0, 226 required paths**
- `-m tooling.knowledge.validate_knowledge` — pass
- `-m tooling.workflow.validate_workflow` — pass
- `-m tooling.prototype.validate_prototype` — pass
- `-m tooling.reference_client.validate_reference_client client-projects/reference-commerce` — pass (reports byte-fresh)
- `-m tooling.production_authorization.validate client-projects/reference-commerce` — pass
- `-m tooling.production.validate_config client-projects/reference-commerce` — exit 0
- `-m tooling.production.validate_migrations` — exit 0
- `-m tooling.production.report client-projects/reference-commerce` — exit 0
- `-m tooling.hardening.validate client-projects/reference-commerce` — exit 0
- `-m tooling.release.validate client-projects/reference-commerce` — exit 0

Dart/Flutter (`flutter test` + `flutter analyze`, all analyze clean):

| Package/app | Tests |
|-------------|-------|
| `packages/agency_production_core` | 66 |
| `packages/agency_supabase_adapter` | 65 |
| `packages/agency_integration_adapters` | 80 |
| `packages/agency_operations_core` | 80 |
| `packages/agency_sentry_adapter` | 20 |
| `packages/agency_ga4_adapter` | 21 |
| `packages/agency_cloudflare_adapter` | 18 |
| `apps/production_app` | 37 (+ `flutter build web` OK) |
| `packages/agency_flutter_ui` (regression) | 42 |
| `apps/prototype_app` (regression) | 790 |
| `apps/widgetbook` (regression) | 1 (+7 skipped; goldens Linux-CI only) |

Total Dart/Flutter: **1220 tests**; Python: **1346 tests**.

Freshness checks:

- B.1D `python -m tooling.design_contract.generate_flutter_bindings --check` — fresh
- B.1E `python -m tooling.design_contract.generate_resolved_themes --check` — fresh

## Hardening gate results (reference-commerce, fixture mode)

All six gates pass with **0 blocking findings** and **6 advisory findings
retained**; `eligible_for_authorization: true`. Security: no open critical/high
release-relevant findings, no secret leak, RLS valid, production debug off.
Performance: all seven budgets within the exact policy thresholds. Accessibility:
all six critical journeys have keyboard/focus/semantics/labels/contrast evidence.
Analytics: all 12 governed critical events present. Observability: adapter
initialized, release/environment/client/candidate tags, handled+unhandled
capture, redaction proven. Migrations: identity matches, staging apply and
post-apply verification pass, recovery treatment present.

## Candidate / evidence identities

- Candidate: `sha256:be27d17be2be37bf05778fefb983b1116fa5e45e029a7e06b180e68fcfbc98da`
- Source SHA (fixture): `b3b18ff1877e72447381c3e7bdfaf31889616f78`
- Artifact digest: `sha256:a477522873976ac4b6f816460a1915ca67e6043918b20c84a56c898f9eb3a989`
- Migration-set identity: `sha256:f37830c5d1f64588127bc2a1b8c9311650e3db255e2c079821fd3d0d784455e5`
- Release-config identity: `sha256:43b6737e3c7922c81e8620d113a2f4bd8c2e518578b160fc50c949f35b1659d0`
- H.2 hardening report identity: `sha256:33bc72613e224ae17415ab266baafd725df4806e22b716360acfd418980992e0`
- Staging smoke report identity: `sha256:29cb955e290e0c1e3e4745dd70d2ae831eee361791043e784a08fd01e322e43c`
- Staging deployment: `staging-deploy-0001`, artifact digest equals the candidate digest (no rebuild).
- G authorization (H.2 synthetic human fixture): `pa-reference-commerce-production-h2-0001`, version 1, release owner, active.
- ReleaseRecord: `rel-reference-commerce-production-0.1.0+h2rc1`, status `healthy`, `release_identity` `sha256:b173acdca6…` (final identity in the committed artifact).
- Production smoke `sha256:71b66ce…`; telemetry health `sha256:7cb2133…` (5 healthy samples at 60s spacing).

## Staging proof

Staging deployment of the exact candidate artifact, then all six H.2A gates plus
staging smoke (B2C `sign-in→catalog→inventory→cart→order`; B2B
`sign-in→membership→credit→RFQ→quotation→order`; session refresh;
insufficient permission; backend failure mapping; release/version identity). The
hardening report is eligible only with 0 blocking findings and passing critical
journeys.

## Production-release status, smoke, telemetry

The deterministic fixture proof completes: exact artifact promotion (same digest
as staged/authorized), low-risk production smoke (release identity, app shell,
auth/session via synthetic release-check identity, catalog/inventory read,
permission-denied negative check, no uncontrolled order/payment mutation), and a
5-sample/60s telemetry health window → `healthy` ReleaseRecord. **No live
Cloudflare/Supabase deployment was executed.**

## Rollback / recovery proof

Governed application rollback to the previous known-good artifact
(`rel-reference-commerce-production-0.1.0+h2rc1`), verification passed, no blind
DB rollback (`migration_result.attempted: false`). A new artifact digest is
denied as a new candidate, not rollback. Recovery decisions and reversibility are
bound to committed artifacts and committed migration `-- migration-class:`
headers (`additive`-only reversible).

## Final whole-branch review

Reviewed `git diff origin/main...HEAD` against all 46 acceptance criteria:
**all 46 PASS, 0 blockers / 0 majors.** Four minors were recorded and closed:
CI wiring for the reference-proof gate (committed), live workflow now runs the
offline H.2→G chain (R19), spec §8/§20 order text inconsistency (R18), and the
`pubspec.lock` decision (R20).

## Known limitations

- No live Cloudflare/Supabase staging or production deployment; CI is
  deterministic and credential-free by design. The live release path is
  implemented but intentionally not executed.
- The production-release workflow validates the committed reference candidate
  fixture; a real candidate requires a non-fixture validation mode.
- Static workflow analysis is defense-in-depth and cannot defeat a committer who
  also edits the tests; the real guarantee is the workflow design plus human
  review.
- `validate_recovery` is a committed-fixture validator; a legitimate non-reference
  DB-reverse report is intentionally not accepted.
- Windows `core.autocrlf` is neutralized for the report markdown via
  `.gitattributes`; other generated artifacts rely on the existing LF pins.

## Explicitly deferred

- Android/iOS signing and store release automation.
- Real ERP/payment/shipping/CRM/WhatsApp vendor integrations and any live
  client-specific providers.
- Multi-client fleet/orchestration and generalized incident management.
- Creation of any `ProductionAuthorization` by H.2 (remains human/Milestone-G).

## Final status

0 blockers, 0 majors. All 46 H.2 acceptance criteria pass. Not merged. No live
deployment executed. Pushed as `milestone-h2-production-hardening-release` and
opened as a PR titled **Milestone H.2 - Production Hardening and Authorized
Release**.
