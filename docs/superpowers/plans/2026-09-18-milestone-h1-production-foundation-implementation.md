# Milestone H.1 — Production Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a provider-neutral production application foundation for approved Flutter experiences, prove it with `reference-commerce`, and supply Supabase/Postgres + Supabase Auth reference adapters without granting release authority or deploying production.

**Architecture:** Add a pure-Dart production core package containing domain failures, environment configuration, identities, repositories, authentication, integration ports, and application use cases. Add a separate Supabase adapter package and deterministic fake integration adapters, then compose them in a shared Flutter production app that reuses `agency_flutter_ui` and the approved reference-commerce experience. Production migrations, contract tests, deterministic production-path E2E tests, repository validation, and the existing stage-08 workflow gate complete H.1.

**Tech Stack:** Dart >=3.3, Flutter, `supabase_flutter`, Supabase/Postgres SQL migrations, Python 3.12 repository validators, GitHub Actions, existing `agency_flutter_ui`, existing workflow runtime.

**Spec:** `docs/superpowers/specs/2026-09-18-milestone-h1-production-foundation-design.md`

## Global Constraints

- H.1 implements production behavior only; it must not create or mutate `ApprovalSnapshot`, `ReviewState`, `FeedbackRecord`, `RefinementBatch`, `QAFinding`, `workflow-state.yaml` outside the existing workflow runner, or `ProductionAuthorization`.
- Supabase/Postgres and Supabase Auth are reference adapters only; provider-neutral contracts remain the platform boundary.
- Flutter may contain only client-safe configuration. No service-role key, vendor secret, webhook secret, ERP credential, shipping credential, payment secret, or WhatsApp server token may be committed or embedded in the app.
- Backend/Supabase RLS is the actual authorization boundary; Flutter role guards are UX convenience only.
- Reference roles are exactly `consumer`, `b2b_buyer`, `b2b_manager`, and `admin`.
- External ERP/payment/shipping/CRM/WhatsApp integrations remain deterministic fake adapters in H.1.
- Provider-specific exceptions normalize to provider-neutral `DomainFailure`.
- Retries are allowed only for explicitly safe/idempotent operations; order/payment-like mutations use idempotency keys.
- Runtime environments are exactly `dev`, `staging`, and `production`.
- Normal CI must not require production credentials or a live Supabase project.
- H.1 performs no production deployment and cannot satisfy or manufacture G authorization.
- The approved reference-commerce UX must be reused; H.1 must not silently redesign it.
- No `pubspec.lock` policy change.

---

# File Structure Locked by This Plan

```text
packages/
  agency_production_core/
    pubspec.yaml
    lib/
      agency_production_core.dart
      src/
        config/environment_config.dart
        domain/domain_failure.dart
        domain/identity.dart
        domain/models.dart
        ports/auth_service.dart
        ports/repositories.dart
        ports/integrations.dart
        application/commerce_service.dart
        application/order_service.dart
        application/quote_service.dart
    test/
      environment_config_test.dart
      domain_failure_test.dart
      repository_contract_test.dart
      application_services_test.dart

  agency_supabase_adapter/
    pubspec.yaml
    lib/
      agency_supabase_adapter.dart
      src/
        supabase_error_mapper.dart
        supabase_auth_adapter.dart
        supabase_catalog_repository.dart
        supabase_account_repository.dart
        supabase_cart_repository.dart
        supabase_order_repository.dart
        supabase_quote_repository.dart
    test/
      supabase_error_mapper_test.dart
      supabase_repository_mapping_test.dart
      supabase_auth_adapter_test.dart

  agency_integration_adapters/
    pubspec.yaml
    lib/
      agency_integration_adapters.dart
      src/fake/
        fake_payment_adapter.dart
        fake_shipping_adapter.dart
        fake_erp_adapter.dart
        fake_crm_adapter.dart
        fake_whatsapp_adapter.dart
    test/
      fake_integration_contract_test.dart

apps/
  production_app/
    pubspec.yaml
    lib/
      main.dart
      app/production_app.dart
      app/production_composition_root.dart
      runtime/reference_commerce_runtime.dart
    test/
      reference_commerce_b2c_production_path_test.dart
      reference_commerce_b2b_production_path_test.dart
      production_failure_states_test.dart
      environment_boot_test.dart

supabase/
  migrations/
    202609180001_reference_commerce_foundation.sql
    202609180002_reference_commerce_rls.sql
  seed/
    reference_commerce_seed.sql

client-projects/reference-commerce/
  production/
    config/dev.json
    config/staging.json
    config/production.json
    fixtures/integration-scenarios.json
    evidence/h1-foundation-report.json

tooling/production/
  __init__.py
  validate_config.py
  validate_migrations.py
  report.py

tooling/validation/
  test_production_config.py
  test_production_migrations.py
  test_h1_authority_boundaries.py
  test_h1_reference_report.py
```

---

# Cycle H.1A — Production Core and Application Contracts

### Task 1: Production core models, failure contract, and environment configuration

**Files:**
- Create: `packages/agency_production_core/pubspec.yaml`
- Create: `packages/agency_production_core/lib/agency_production_core.dart`
- Create: `packages/agency_production_core/lib/src/domain/domain_failure.dart`
- Create: `packages/agency_production_core/lib/src/domain/identity.dart`
- Create: `packages/agency_production_core/lib/src/domain/models.dart`
- Create: `packages/agency_production_core/lib/src/config/environment_config.dart`
- Test: `packages/agency_production_core/test/domain_failure_test.dart`
- Test: `packages/agency_production_core/test/environment_config_test.dart`

**Interfaces:**
- Produces:
  - `enum ProductionEnvironment { dev, staging, production }`
  - `enum DomainFailureCode { unauthorized, forbidden, validation, conflict, unavailable, timeout, staleData, unknown }`
  - `final class DomainFailure implements Exception`
  - `enum UserRole { consumer, b2bBuyer, b2bManager, admin }`
  - `final class AppIdentity`
  - immutable models: `Product`, `Variant`, `InventoryAvailability`, `CustomerProfile`, `BusinessAccount`, `AccountMembership`, `CreditSnapshot`, `Cart`, `CartItem`, `Order`, `OrderItem`, `Rfq`, `Quotation`
  - `final class EnvironmentConfig`
- `EnvironmentConfig.fromJson(Map<String,Object?>)` rejects privileged keys by name and validates exactly one of dev/staging/production.

- [ ] **Step 1: Add failing tests for the failure contract and allowed environments**

```dart
test('DomainFailure retains stable machine fields', () {
  final failure = DomainFailure(
    code: DomainFailureCode.unavailable,
    operation: 'load_catalog',
    retryable: true,
    message: 'Service unavailable',
    correlationId: 'req-1',
  );

  expect(failure.code, DomainFailureCode.unavailable);
  expect(failure.operation, 'load_catalog');
  expect(failure.retryable, isTrue);
});

test('EnvironmentConfig rejects privileged keys', () {
  expect(
    () => EnvironmentConfig.fromJson({
      'environment': 'production',
      'api_base_url': 'https://api.example.test',
      'supabase_url': 'https://project.supabase.co',
      'supabase_anon_key': 'public-safe-key',
      'service_role_key': 'must-not-be-here',
    }),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
cd packages/agency_production_core
flutter test test/domain_failure_test.dart test/environment_config_test.dart
```

Expected: FAIL because the package/types do not exist.

- [ ] **Step 3: Implement the minimal production-core types**

```dart
enum ProductionEnvironment { dev, staging, production }

enum DomainFailureCode {
  unauthorized,
  forbidden,
  validation,
  conflict,
  unavailable,
  timeout,
  staleData,
  unknown,
}

final class DomainFailure implements Exception {
  const DomainFailure({
    required this.code,
    required this.operation,
    required this.retryable,
    required this.message,
    this.correlationId,
  });

  final DomainFailureCode code;
  final String operation;
  final bool retryable;
  final String message;
  final String? correlationId;
}
```

Implement `EnvironmentConfig.fromJson` with an explicit allowlist:
`environment`, `api_base_url`, `supabase_url`, `supabase_anon_key`, `analytics_enabled`, `feature_flags`, `integration_modes`, `app_version`.

- [ ] **Step 4: Add model invariant tests**

Verify positive monetary quantities where applicable, stable non-empty IDs, immutable collections, B2B membership role, and that credit values cannot be negative.

- [ ] **Step 5: Run package tests and analysis**

```bash
flutter test
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/agency_production_core
git commit -m "feat: add production core domain and configuration"
```

### Task 2: Provider-neutral repositories, authentication, and integration ports

**Files:**
- Create: `packages/agency_production_core/lib/src/ports/auth_service.dart`
- Create: `packages/agency_production_core/lib/src/ports/repositories.dart`
- Create: `packages/agency_production_core/lib/src/ports/integrations.dart`
- Modify: `packages/agency_production_core/lib/agency_production_core.dart`
- Test: `packages/agency_production_core/test/repository_contract_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class AuthService`
  - `Stream<AppIdentity?> authStateChanges()`
  - `Future<AppIdentity> signIn({required String email, required String password})`
  - `Future<void> signOut()`
  - `Future<AppIdentity?> currentIdentity()`
  - `Future<AppIdentity> refreshSession()`
  - `CatalogRepository`, `InventoryRepository`, `CustomerRepository`, `AccountRepository`, `CartRepository`, `OrderRepository`, `QuoteRepository`
  - `PaymentPort`, `ShippingPort`, `ErpPort`, `CrmPort`, `WhatsAppPort`
  - `IdempotencyKey` value object required by mutable external transaction methods.

- [ ] **Step 1: Write compile-failing contract tests with in-memory test doubles**

```dart
final class MemoryOrderRepository implements OrderRepository {
  final orders = <String, Order>{};

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
  }) async {
    return orders.putIfAbsent(
      idempotencyKey.value,
      () => Order.fromCart(cart, id: 'order-1'),
    );
  }
}
```

Test that the same idempotency key does not create two orders.

- [ ] **Step 2: Run the contract test and verify failure**

```bash
cd packages/agency_production_core
flutter test test/repository_contract_test.dart
```

- [ ] **Step 3: Implement the interfaces exactly as exercised by the tests**

Mutation interfaces that can create externally visible effects must accept `IdempotencyKey`.

Read operations do not require idempotency keys.

- [ ] **Step 4: Test role/account membership separately from identity**

Construct one identity with memberships in two `BusinessAccount` records and verify account-specific access is resolved from `AccountMembership`, not from a single global user role.

- [ ] **Step 5: Run package tests/analyze and commit**

```bash
flutter test
flutter analyze
git add packages/agency_production_core
git commit -m "feat: add production ports and auth contracts"
```

### Task 3: Production application services and safe retry/idempotency rules

**Files:**
- Create: `packages/agency_production_core/lib/src/application/commerce_service.dart`
- Create: `packages/agency_production_core/lib/src/application/order_service.dart`
- Create: `packages/agency_production_core/lib/src/application/quote_service.dart`
- Test: `packages/agency_production_core/test/application_services_test.dart`

**Interfaces:**
- `CommerceService.loadCatalog()` composes catalog + availability reads.
- `OrderService.placeOrder({required String cartId, required IdempotencyKey idempotencyKey})`.
- `QuoteService.createRfq(...)` and `QuoteService.convertQuotationToOrder(...)`.
- Application services catch only `DomainFailure`; provider exceptions are forbidden above adapter boundaries.

- [ ] **Step 1: Write failing tests for B2C order placement and duplicate submission**

Test first call creates one order and second call with the same key returns the same order identity.

- [ ] **Step 2: Write failing tests for retryable vs non-retryable failures**

```dart
expect(timeoutFailure.retryable, isTrue);
expect(validationFailure.retryable, isFalse);
```

- [ ] **Step 3: Implement the minimal services**

Do not implement generic retry middleware. Expose retryability through `DomainFailure`; explicit caller logic decides whether a read/safe operation is retried.

- [ ] **Step 4: Add B2B tests**

Cover account/credit lookup, RFQ creation, quotation conversion, insufficient permission, and insufficient available credit.

- [ ] **Step 5: Run all production-core tests/analyze and commit**

```bash
flutter test
flutter analyze
git add packages/agency_production_core
git commit -m "feat: add production commerce application services"
```

---

# Cycle H.1B — Supabase and External Adapter Boundaries

### Task 4: Supabase/Postgres schema, RLS policies, seed data, and migration validation

**Files:**
- Create: `supabase/migrations/202609180001_reference_commerce_foundation.sql`
- Create: `supabase/migrations/202609180002_reference_commerce_rls.sql`
- Create: `supabase/seed/reference_commerce_seed.sql`
- Create: `tooling/production/__init__.py`
- Create: `tooling/production/validate_migrations.py`
- Test: `tooling/validation/test_production_migrations.py`

**Interfaces:**
- Foundation migration creates tables for profiles, business_accounts, account_memberships, credit_snapshots, categories, products, variants, inventory, carts, cart_items, orders, order_items, rfqs, quotations.
- RLS migration enables RLS on user/account-owned tables and defines account-membership policies.
- Migration validator classifies each migration as additive/transformative/destructive based on an explicit metadata header:
  `-- migration-class: additive|transformative|destructive`.

- [ ] **Step 1: Write validator tests for ordered versioned migrations and required metadata**

Test duplicate version, missing class header, and unsupported class all fail.

- [ ] **Step 2: Run and verify failure**

```bash
python -m unittest tooling.validation.test_production_migrations -v
```

- [ ] **Step 3: Implement deterministic migration validation**

`validate_migrations(root: Path) -> list[str]` must return stable sorted errors and must not execute SQL.

- [ ] **Step 4: Write foundation SQL**

Use UUID/text primary keys suitable for Supabase, foreign keys, useful indexes, `created_at`/mutation timestamps where needed, and uniqueness for idempotency keys on order creation.

- [ ] **Step 5: Write RLS SQL**

Policies must enforce:
- consumer owns own customer/cart/order records,
- B2B user accesses an account only through account_memberships,
- manager-level write operations require `b2b_manager` membership,
- admin behavior is expressed through server/backend policy, not Flutter checks.

- [ ] **Step 6: Add deterministic seed data aligned with reference-commerce IDs**

Seed data must be synthetic and must not include production secrets/PII.

- [ ] **Step 7: Run validator tests and commit**

```bash
python -m unittest tooling.validation.test_production_migrations -v
git add supabase tooling/production/validate_migrations.py tooling/validation/test_production_migrations.py
git commit -m "feat: add reference Supabase schema and migrations"
```

### Task 5: Supabase repositories and Supabase Auth adapter

**Files:**
- Create: `packages/agency_supabase_adapter/pubspec.yaml`
- Create: `packages/agency_supabase_adapter/lib/agency_supabase_adapter.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_error_mapper.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_auth_adapter.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_catalog_repository.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_account_repository.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_cart_repository.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_order_repository.dart`
- Create: `packages/agency_supabase_adapter/lib/src/supabase_quote_repository.dart`
- Test: `packages/agency_supabase_adapter/test/supabase_error_mapper_test.dart`
- Test: `packages/agency_supabase_adapter/test/supabase_repository_mapping_test.dart`
- Test: `packages/agency_supabase_adapter/test/supabase_auth_adapter_test.dart`

**Interfaces:**
- Depends on `agency_production_core`.
- Uses `supabase_flutter` behind adapter classes only.
- `mapSupabaseFailure(Object error, {required String operation}) -> DomainFailure`.
- Repository implementations satisfy the Task-2 production ports.

- [ ] **Step 1: Add the package with path dependency on production core and dependency on `supabase_flutter`**

Do not add Supabase dependency to `agency_production_core` or `agency_flutter_ui`.

- [ ] **Step 2: Write error-mapping tests**

Map auth failures to unauthorized/forbidden, PostgREST conflicts to conflict, timeout/network failures to timeout/unavailable, and unrecognized exceptions to unknown.

- [ ] **Step 3: Implement the mapper and pass tests**

No raw Supabase exception may leave the package's public adapter methods.

- [ ] **Step 4: Write repository mapping tests with a narrow client seam**

Adapters must expose/inject a small query-client abstraction in tests so normal CI does not need a live Supabase project.

- [ ] **Step 5: Implement repository adapters**

All wire-format JSON/row mapping remains inside this package.

- [ ] **Step 6: Write Supabase Auth mapping tests**

Verify sign-in/current identity/refresh/sign-out and membership/role mapping.

- [ ] **Step 7: Run package tests/analyze and commit**

```bash
cd packages/agency_supabase_adapter
flutter test
flutter analyze
git add .
git commit -m "feat: add Supabase production adapters"
```

### Task 6: Deterministic fake ERP/payment/shipping/CRM/WhatsApp adapters

**Files:**
- Create: `packages/agency_integration_adapters/pubspec.yaml`
- Create: `packages/agency_integration_adapters/lib/agency_integration_adapters.dart`
- Create: `packages/agency_integration_adapters/lib/src/fake/fake_payment_adapter.dart`
- Create: `packages/agency_integration_adapters/lib/src/fake/fake_shipping_adapter.dart`
- Create: `packages/agency_integration_adapters/lib/src/fake/fake_erp_adapter.dart`
- Create: `packages/agency_integration_adapters/lib/src/fake/fake_crm_adapter.dart`
- Create: `packages/agency_integration_adapters/lib/src/fake/fake_whatsapp_adapter.dart`
- Test: `packages/agency_integration_adapters/test/fake_integration_contract_test.dart`

**Interfaces:**
- `enum FakeIntegrationScenario { success, validationFailure, timeout, unavailable, retryableFailure, duplicate }`
- Each adapter implements its corresponding production-core port.
- Scenario selection is constructor-injected and deterministic.

- [ ] **Step 1: Write one shared contract suite used against all five fake adapters**

The suite verifies stable success result, normalized failure code, retryability, deterministic duplicate behavior, and no provider-specific exception leakage.

- [ ] **Step 2: Run and verify failure**

```bash
cd packages/agency_integration_adapters
flutter test
```

- [ ] **Step 3: Implement fake adapters**

Payment and other externally mutating ports must honor the provided `IdempotencyKey`.

- [ ] **Step 4: Verify timeout/unavailable/validation/duplicate scenarios**

No randomness, sleep-based timing, or network dependency is permitted.

- [ ] **Step 5: Run tests/analyze and commit**

```bash
flutter test
flutter analyze
git add .
git commit -m "feat: add deterministic production integration adapters"
```

---

# Cycle H.1C — Reference Production App, Workflow, and CI Proof

### Task 7: Environment files, secret-boundary validator, and production composition root

**Files:**
- Create: `client-projects/reference-commerce/production/config/dev.json`
- Create: `client-projects/reference-commerce/production/config/staging.json`
- Create: `client-projects/reference-commerce/production/config/production.json`
- Create: `tooling/production/validate_config.py`
- Test: `tooling/validation/test_production_config.py`
- Create: `apps/production_app/pubspec.yaml`
- Create: `apps/production_app/lib/main.dart`
- Create: `apps/production_app/lib/app/production_app.dart`
- Create: `apps/production_app/lib/app/production_composition_root.dart`
- Create: `apps/production_app/lib/runtime/reference_commerce_runtime.dart`
- Test: `apps/production_app/test/environment_boot_test.dart`

**Interfaces:**
- `validate_production_config(root: Path, client_dir: Path) -> list[str]`.
- Validator rejects privileged key names recursively, requires all three environments, and checks environment/name consistency.
- `ProductionCompositionRoot.referenceCommerce(EnvironmentConfig config)` wires provider-neutral services.
- Dev/test composition uses deterministic fake/in-memory boundaries.
- Staging/production composition may create Supabase adapters only when client-safe config is present; missing privileged server credentials are not treated as Flutter config.

- [ ] **Step 1: Write Python tests for missing environment, wrong environment name, privileged key, and valid configs**

Forbidden key fragments include:
`service_role`, `secret`, `private_key`, `webhook_secret`, `erp_password`, `payment_secret`, `whatsapp_token`.

- [ ] **Step 2: Implement config validation and pass tests**

- [ ] **Step 3: Create the Flutter production app using existing `agency_flutter_ui`**

Do not copy widgets from `apps/prototype_app`. Reuse approved shared UI/components and production-core services.

- [ ] **Step 4: Write boot tests**

Verify dev boot with deterministic adapters, staging/prod config parsing, and deterministic failure for malformed config.

- [ ] **Step 5: Run app tests/analyze and commit**

```bash
cd apps/production_app
flutter test
flutter analyze
flutter build web
git add .
git commit -m "feat: compose reference production application"
```

### Task 8: Reference-commerce production-path E2E and failure-state proof

**Files:**
- Create: `client-projects/reference-commerce/production/fixtures/integration-scenarios.json`
- Create: `apps/production_app/test/reference_commerce_b2c_production_path_test.dart`
- Create: `apps/production_app/test/reference_commerce_b2b_production_path_test.dart`
- Create: `apps/production_app/test/production_failure_states_test.dart`

**Interfaces:**
- Uses the same application services/ports as production composition.
- Test harness substitutes deterministic repositories/adapters but does not bypass application services.

- [ ] **Step 1: Write B2C failing E2E**

```text
sign in
→ load catalog/inventory
→ create/persist cart
→ place order with idempotency key
→ repeat submission
→ assert exactly one order identity
```

- [ ] **Step 2: Implement only the missing composition/test harness needed to pass**

No new UX pattern may be introduced.

- [ ] **Step 3: Write B2B failing E2E**

```text
sign in
→ resolve business membership
→ load credit
→ create RFQ
→ receive deterministic quote
→ convert quote to order
```

Add insufficient-role and insufficient-credit cases.

- [ ] **Step 4: Add the required failure-state suite**

Cover:
- expired session + refresh
- forbidden B2B action
- inventory unavailable
- stale cart
- backend unavailable
- timeout
- retryable versus non-retryable error
- duplicate order protection
- malformed environment config

- [ ] **Step 5: Run production-app tests/analyze/build and commit**

```bash
cd apps/production_app
flutter test
flutter analyze
flutter build web
git add .
git commit -m "test: prove reference production commerce paths"
```

### Task 9: H.1 evidence report, workflow stage-08 contract, authority boundaries, and repository validation

**Files:**
- Create: `tooling/production/report.py`
- Create: `client-projects/reference-commerce/production/evidence/h1-foundation-report.json`
- Create: `tooling/validation/test_h1_reference_report.py`
- Create: `tooling/validation/test_h1_authority_boundaries.py`
- Modify: `workflows/08-productionize.md`
- Modify: `workflows/contracts/08-productionize.yaml`
- Modify: `tooling/validation/validate_repo.py`
- Modify: `tooling/validation/test_validate_repo.py`
- Modify: `.github/workflows/validate.yml`
- Modify: `.github/workflows/flutter-ci.yml`
- Modify: `AGENTS.md`

**Interfaces:**
- `build_h1_report(root: Path, client_dir: Path) -> dict[str, object]`.
- Report is deterministic evidence only; no subjective score.
- Stage-08 validator named `production-foundation` verifies config, migrations, H.1 report freshness, and production-app contract evidence.
- Stage-08 remains unable to create ProductionAuthorization or deploy.

- [ ] **Step 1: Write report tests**

Required keys:
`report_version`, `client_id`, `environments`, `ports`, `adapters`, `migrations`, `b2c_path`, `b2b_path`, `failure_scenarios`, `authority_checks`, `report_identity`.

- [ ] **Step 2: Implement deterministic report generation**

Identity is SHA-256 of canonical report content excluding `report_identity`.

- [ ] **Step 3: Write authority-boundary tests**

Explicitly assert:
- no H.1 module imports G coordinator to create authorization,
- no H.1 code writes production deployment artifacts,
- no existing approval/review/QA authority is duplicated under `production/`,
- Flutter configs contain no forbidden secret keys,
- Supabase imports appear only in the Supabase adapter/app composition boundary.

- [ ] **Step 4: Update stage-08 workflow documentation and contract**

The stage must require approved experience and produce H.1 foundation evidence, but completion must say **production-capable**, not **production-authorized** or **deployed**.

- [ ] **Step 5: Wire repository validation and CI**

Repository Validation runs:
- production config tests/validator
- production migration tests/validator
- H.1 report/boundary tests

Flutter CI discovers and analyzes/tests:
- `agency_production_core`
- `agency_supabase_adapter`
- `agency_integration_adapters`
- `apps/production_app`
- production app web build

Normal CI uses no live Supabase credentials.

- [ ] **Step 6: Regenerate the H.1 report and prove byte freshness**

Generate twice and assert identical bytes.

- [ ] **Step 7: Commit**

```bash
git add tooling client-projects/reference-commerce/production workflows .github AGENTS.md
git commit -m "feat: gate and validate production foundation"
```

### Task 10: Full regression, final review, and PR delivery

**Files:**
- Create: `docs/superpowers/ledgers/2026-09-18-milestone-h1-production-foundation-ledger.md`
- Modify only files required by verified review findings.

**Interfaces:**
- No new runtime interfaces. This task proves the branch satisfies the spec and records evidence.

- [ ] **Step 1: Run Python validation**

```bash
py -3.12 -m unittest discover tooling/validation -v
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 -m tooling.prototype.validate_prototype
py -3.12 -m tooling.reference_client.validate_reference_client client-projects/reference-commerce
py -3.12 -m tooling.production_authorization.validate client-projects/reference-commerce
py -3.12 -m tooling.production.validate_config client-projects/reference-commerce
py -3.12 -m tooling.production.validate_migrations
```

- [ ] **Step 2: Run every new Dart/Flutter package**

```bash
cd packages/agency_production_core && flutter test && flutter analyze
cd ../agency_supabase_adapter && flutter test && flutter analyze
cd ../agency_integration_adapters && flutter test && flutter analyze
cd ../../apps/production_app && flutter test && flutter analyze && flutter build web
```

Also rerun unchanged shared/prototype regression required by repository policy.

- [ ] **Step 3: Run B.1D/B.1E freshness checks**

Use the repository's canonical `--check` commands for Flutter bindings and resolved themes; both must be fresh.

- [ ] **Step 4: Review `git diff origin/main...HEAD` against all 26 H.1 acceptance criteria**

Review specifically for:
- accidental UX redesign,
- secret leakage,
- provider coupling in production core,
- missing RLS boundary,
- raw Supabase exceptions escaping adapters,
- non-idempotent mutation retries,
- fake adapters pretending to be real integrations,
- CI requiring live credentials,
- H.1 creating G authorization,
- H.1 deploying or implementing H.2/H.3 early.

Target: 0 blockers / 0 majors.

- [ ] **Step 5: Resolve blockers/majors and rerun affected tests**

Record residual minors and rationale in the ledger.

- [ ] **Step 6: Finalize the ledger**

Record:
- task commits
- rulings/deviations
- exact test counts
- migration/config validation
- Flutter package/app test results
- final branch SHA
- known limitations
- deliberately deferred H.2/H.3 work

- [ ] **Step 7: Push and open PR against `main`**

PR title:

`Milestone H.1 - Production Foundation`

Do not merge without explicit user authorization.
