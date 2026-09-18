# Milestone H.1 — Production Foundation Ledger

Plan: `docs/superpowers/plans/2026-09-18-milestone-h1-production-foundation-implementation.md`
Spec: `docs/superpowers/specs/2026-09-18-milestone-h1-production-foundation-design.md`
Branch: `milestone-h1-production-foundation`
Base: `a199f6554f85a5a0ee633e108e95b4f365693d83` (Milestone G merged to `main`)
Reviewed code tip: `b3364b30700bb6c6dc8529e601c15a8ca225c458`

Milestone H.1 delivers a provider-neutral production application foundation,
proves it with `reference-commerce`, and supplies Supabase/Postgres + Supabase
Auth reference adapters. H.1 grants no release authority and performs no
deployment.

## Execution model

Subagent-driven development: one fresh implementer per task, an independent
reviewer after every task (spec-compliance verdict + code-quality verdict), a
fix loop with scoped re-reviews, and one whole-branch review at the end. Only
`general`/`explore` subagents were exposed in this session, so the plan's
`@strategy`/`@builder`/`@worker`/`@reviewer` model routing was approximated with
fresh `general` implementers and separate fresh `general` reviewers; no
implementer ever reviewed its own task. This is the recorded routing deviation.

## Cycles and tasks

### Cycle H.1A — Production core and application contracts

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 1. Production core domain/failure/config | `fef1465` | 29 | clean |
| 2. Provider-neutral ports/auth/integrations | `8f7dc8e` | 43 | clean |
| 3. Application services + idempotency/retry | `6e13a3b`, `2b49afb` (fix 1) | 66 | clean after fix |

### Cycle H.1B — Supabase and external adapter boundaries

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 4. Supabase schema/RLS/seed/migration validator | `1581a56`, `eba25e3` (fix 1) | 21 | clean after fix |
| 5. Supabase repositories + Auth adapter | `5db1de0`, `a60095f`, `3f1434a` (fix 1), `98cd9d0` (fix 2) | 65 | clean after fixes |
| 6. Deterministic fake integration adapters | `e99152c`, `4a5dac4` (fix 1) | 80 | clean after fix |

### Cycle H.1C — Reference production app, workflow, and CI proof

| Task | Commit(s) | Tests | Review |
|------|-----------|-------|--------|
| 7. Config validator + composition root | `a061768`, `1ef9722` (fix 1) | 24 Python / 19 Flutter | clean after fix |
| 8. B2C/B2B production-path E2E + failure states | `f4d5677`, `d1bca70` (fix 1) | 37 | clean after fix (1 parked minor) |
| 9. H.1 report + stage-08 + CI/repo validation | `d6b6495` | 922 Python discover | clean |
| 10. Regression + whole-branch review + PR | `b3364b3` (final-review fix) | see below | 1 blocker fixed, 0 majors |

## Reviewer findings that changed the code

- **Task 3 (Critical + Important):** converted order total could diverge from the
  credit-authorized `Quotation.totalMinor`, and quotation conversion was not
  single-shot. Fixed by carrying the negotiated total through
  `OrderRepository.createOrder` and deriving a deterministic conversion
  idempotency key.
- **Task 4 (2 Important):** RLS write policies allowed cross-account writes and
  identity spoofing. Tightened to `identity_id = auth.uid() and account_id is
  null` for personal rows and membership + identity binding for account rows.
- **Task 5 (1 Critical + 4 Important):** the global role was read from
  user-editable `user_metadata` (self-escalation). Now read from server-controlled
  `app_metadata`; also fixed the profile upsert key, made order/RFQ writes atomic
  nested inserts, recovered quotation conflicts, hid the raw provider seams, and
  exposed public adapter factories.
- **Task 6 (2 Important):** the `duplicate` scenario was behaviorally empty and
  `trackShipment`'s failure path was untested. Gave `duplicate` payload-integrity
  semantics and covered the shipping failure paths.
- **Task 7 (1 Important):** the validated environment config files never reached
  the running app. Added `sync_app_config` + committed app assets and made
  `main.dart` load the selected environment asset with no silent fallback.
- **Task 8 (1 Important):** the E2E fixture was only partially consumed. The
  harness now parses both paths and the B2B cases, and journeys assert the
  fixture's step lists.
- **Final whole-branch review (1 Blocker):** the Supabase write adapters omitted
  the ownership columns the shipped schema CHECK constraints and RLS require, so
  reference persistence would fail on first write. Fixed by threading
  `identity_id`/`account_id` through the ports and adapters, attributing B2B
  orders to the account, and making the fake query seam enforce the ownership
  CHECK and RLS identity rule.

## Rulings / deviations

- **R1:** `Order.fromCart(Cart cart, {required String id})` (positional cart) is
  the binding form, matching the Task 2 call site.
- **R2:** `validate_migrations` and `validate_config` expose both a library
  function and `main(argv)` for `python -m` invocation.
- **R3 (deviation):** `agency_supabase_adapter` declares `sdk: '>=3.9.0 <4.0.0'`
  because `supabase_flutter` 2.x requires it; `agency_production_core` keeps
  `>=3.3.0`. Not a `pubspec.lock` policy change.
- **R4:** environment config JSON uses exactly the `EnvironmentConfig` allowlist
  keys.
- **R5:** no `pubspec.lock` is committed; the seven generated lock files remain
  untracked.
- **R6:** CI adds the H.1 unittest modules and an `apps/production_app` web build.
- **R7:** stage-08 keeps `requires.artifacts: [approved-experience.yaml]` and
  `produces: []`; the new `production-foundation` validator is read-only and the
  stage cannot authorize or deploy.
- **R8:** `tooling/production/__init__.py` is owned by Task 4.
- **R9:** the H.1 report references F/G authorities by ref/identity only.
- **R10:** `validate_repo.REQUIRED_PATHS` grew to 193 paths; no existing path was
  removed.
- **R11:** the `RfqStatus.converted` guard is inert today (no port persists
  `converted`); the deterministic conversion key governs replay.
- **Parked minor (Task 8):** the failure-scenario coverage assertion compares two
  hand-maintained sets; the real guard is the per-scenario tests and the fixture
  list. Acceptable residual.
- **Parked residual (final review):** the ownership guard trips only when both
  identity and account are absent, and the fake's RLS identity rule treats
  `null == null` as a pass. The reference production path always writes with an
  authenticated user; tightening the fake to require a non-null current user is a
  deferred test-fidelity improvement.

## Verification (final, at `b3364b3`)

Python (`py -3.12`):

- `-m unittest discover tooling/validation` — **922 tests, OK**
- `tooling/validation/validate_repo.py` — **exit 0, 193 required paths**
- `-m tooling.knowledge.validate_knowledge` — pass
- `-m tooling.workflow.validate_workflow` — pass
- `-m tooling.prototype.validate_prototype` — pass
- `-m tooling.reference_client.validate_reference_client client-projects/reference-commerce` — pass (reports byte-fresh)
- `-m tooling.production_authorization.validate client-projects/reference-commerce` — pass (G authorization valid)
- `-m tooling.production.validate_config client-projects/reference-commerce` — exit 0
- `-m tooling.production.validate_migrations` — exit 0

Dart/Flutter (`flutter test` + `flutter analyze`, all analyze clean):

| Package/app | Tests |
|-------------|-------|
| `packages/agency_production_core` | 66 |
| `packages/agency_supabase_adapter` | 65 |
| `packages/agency_integration_adapters` | 80 |
| `apps/production_app` | 37 (+ `flutter build web` OK) |
| `packages/agency_flutter_ui` (regression) | 42 |
| `apps/prototype_app` (regression) | 790 (+ `flutter build web` OK) |
| `apps/widgetbook` (regression) | 1 (+7 skipped; goldens are Linux-CI only) |

Total Dart/Flutter: **1081 tests**.

Freshness checks:

- B.1D `python -m tooling.design_contract.generate_flutter_bindings --check` — fresh
- B.1E `python -m tooling.design_contract.generate_resolved_themes --check` — fresh

Migration / config validation: 2 versioned migrations (foundation, RLS) plus a
synthetic seed; each carries a `-- migration-class:` header; validator rejects
duplicate versions, missing/unsupported/duplicate class headers, and never
executes SQL. Config validator rejects privileged key fragments (every
dot-segment), requires all three environments, and checks environment/name
consistency.

B2C E2E proof: sign-in → catalog/inventory → cart → order with idempotency key →
repeat submission → exactly one order identity.

B2B E2E proof: sign-in → business membership → credit → RFQ → deterministic
quotation → conversion to order, plus insufficient-role and insufficient-credit
cases, with single-shot conversion replay.

Authority-boundary proof: no H.1 module imports the G coordinator to create
authorization; no deployment artifacts; no approval/review/QA authority
duplicated under `production/`; no forbidden secret keys in Flutter configs;
Supabase imports only at the adapter and app-composition boundary.

## Known limitations

- No live-Supabase integration test; CI is deterministic and credential-free by
  design. The reference adapter's schema/RLS conformance is now covered by a
  constraint-aware fake seam, not a live project.
- `staging.json` / `production.json` carry placeholder anon keys and a
  non-existent project URL; a real project must replace them before H.2/H.3.
- The production app is a minimal proof shell, not a full reproduction of the
  approved reference-commerce UX; full parity is later-milestone work.
- No FK from `identity_id` columns to `auth.users` (intentional, to allow
  synthetic seed loading); identity referential integrity is unenforced at the DB
  layer.
- Manager account-wide administration requires the backend service role (a
  consequence of the tightened RLS identity binding).
- `saveCart` is non-transactional; duplicate `variant_id` line items surface as
  a conflict.
- Secret detection is by key name, not value.

## Explicitly deferred to H.2 / H.3

- Observability, analytics taxonomy, performance budgets, accessibility, and
  security hardening (H.2).
- Real ERP/payment/shipping/CRM/WhatsApp vendor integrations.
- Production deployment, staging apply, and release execution.
- Creation of a new `ProductionAuthorization` for any H.1 candidate (G remains
  the release-authority gate and already holds the reference candidate).
- App-store release automation and rollback/manual-halt execution.

## Final status

0 blockers, 0 majors. Whole-branch review returned 1 blocker which was fixed and
re-reviewed as addressed; all remaining findings are recorded minors/residuals
above. Not merged, not deployed.
