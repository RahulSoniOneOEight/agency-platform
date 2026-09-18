# Milestone H.2 — Production Hardening & Authorized Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the H.1 production-capable Flutter Web application, prove readiness in staging, bind a frozen exact candidate to Milestone G authorization, and release that exact artifact through a provider-neutral deployment pipeline with Cloudflare Pages, Sentry, GA4, smoke tests, telemetry health, and governed rollback/recovery evidence.

**Architecture:** H.2 is one milestone with two internal phases. H.2A adds provider-neutral operations contracts, Sentry/GA4/Cloudflare reference adapters, candidate identity, hardening policies, staging deployment, hardening evidence, and blocking/advisory gates. H.2B consumes the existing G release gate, promotes the already-built exact artifact without rebuilding, applies only the authorized migration set, runs production smoke and telemetry-health checks, and writes one immutable ReleaseRecord per production attempt.

**Tech Stack:** Dart/Flutter, Python 3.12, GitHub Actions, Supabase/Postgres, Cloudflare Pages, Sentry, GA4 Measurement Protocol/reference adapter, existing H.1 production packages, existing Milestone G production-authorization tooling.

**Spec:** `docs/superpowers/specs/2026-09-18-milestone-h2-production-hardening-authorized-release-design.md`

## Global Constraints

- H.2 is one milestone with H.2A Operational Hardening and H.2B Authorized Release.
- Reference production target is Flutter Web + Supabase.
- Android/iOS signing and store release automation remain out of scope.
- Observability is provider-neutral; Sentry is the reference adapter only.
- Analytics is provider-neutral; GA4 is the reference adapter only.
- Deployment is provider-neutral; Cloudflare Pages is the reference adapter only.
- GitHub Actions is an executor and can never create or grant `ProductionAuthorization`.
- Staging deployment and H.2A hardening occur before G authorization.
- A candidate is immutable once submitted to H.2A.
- Candidate identity binds client, target environment, source SHA, artifact digest, build version, migration set, release-config identity, approved-experience reference, and H.1 report reference.
- Any candidate-relevant change requires a new candidate and new G authorization.
- After G authorization the production pipeline must not rebuild. It must deploy the already-built artifact whose digest matches the authorization-bound candidate.
- Production may apply only the candidate-bound migration set.
- H.2 must invoke the existing G release gate; it must not duplicate or weaken G validity semantics.
- H.2 must not create, mutate, or silently substitute for `ProductionAuthorization`.
- Blocking hardening failures prevent a candidate from proceeding to authorization; advisory findings remain recorded but do not block.
- Blind database rollback is prohibited. Use only explicitly safe reversible rollback or a forward-recovery procedure.
- Rollback to a previous known-good application artifact may run only under the pre-authorized recovery policy.
- A newly fixed artifact is a new candidate, not a rollback.
- Every production attempt creates one immutable ReleaseRecord.
- Healthy, degraded, and failed release outcomes are distinct.
- Provider SDKs must not leak into provider-neutral core contracts.
- Privileged Cloudflare/Sentry/GA4/Supabase credentials remain CI/server secrets and are never committed or exposed to Flutter client config.
- Normal PR/build CI remains credential-free and deterministic.
- H.2 must not silently redesign the approved client experience.
- Workflow-state authority remains with `tooling.workflow.runner`.
- No `pubspec.lock` policy change.
- Live staging/production deployment is an external side effect. Execution must stop for explicit human approval before any workflow that deploys to real Cloudflare/Supabase environments.

---

# Repository Structure Locked by This Plan

```text
packages/
  agency_operations_core/
    pubspec.yaml
    lib/
      agency_operations_core.dart
      src/
        observability/observability_port.dart
        analytics/analytics_port.dart
        analytics/analytics_event.dart
        deployment/deployment_port.dart
        hardening/hardening_models.dart
        release/release_candidate.dart
        release/release_record.dart
        release/release_failure.dart
        release/recovery_policy.dart
    test/
      observability_contract_test.dart
      analytics_contract_test.dart
      deployment_contract_test.dart
      release_candidate_test.dart
      release_record_test.dart
      recovery_policy_test.dart

  agency_sentry_adapter/
    pubspec.yaml
    lib/...
    test/...

  agency_ga4_adapter/
    pubspec.yaml
    lib/...
    test/...

  agency_cloudflare_adapter/
    pubspec.yaml
    lib/...
    test/...

tooling/
  hardening/
    __init__.py
    candidate.py
    policies.py
    security.py
    performance.py
    accessibility.py
    analytics.py
    observability.py
    migrations.py
    staging_smoke.py
    report.py
    validate.py

  release/
    __init__.py
    coordinator.py
    evidence.py
    smoke.py
    telemetry_health.py
    recovery.py
    release_record.py
    validate.py

client-projects/reference-commerce/
  production/
    hardening/
      hardening-policy.yaml
      performance-budget.yaml
      analytics-taxonomy.yaml
      accessibility-policy.yaml
      security-policy.yaml
      recovery-policy.yaml
    release/
      candidate.json
      artifact-manifest.json
      staging-deployment.json
      production-deployment.json
      production-authorization-ref.json
    evidence/
      h2-hardening-report.json
      staging-smoke-report.json
      production-smoke-report.json
      telemetry-health-report.json
      release-record.json
      recovery-report.json

client-projects/schema/
  h2-hardening-report.schema.json
  h2-release-candidate.schema.json
  h2-release-record.schema.json
  h2-smoke-report.schema.json
  h2-telemetry-health-report.schema.json

.github/workflows/
  candidate-build.yml
  staging-deploy.yml
  h2-hardening.yml
  production-release.yml
```

The implementation may split files further for clarity, but these conceptual boundaries and authority relationships must remain unchanged.

---

# Cycle H.2A-1 — Operations Contracts and Exact Candidate Identity

### Task 1: Provider-neutral operations core

**Files:**
- Create: `packages/agency_operations_core/pubspec.yaml`
- Create: `packages/agency_operations_core/lib/agency_operations_core.dart`
- Create: `packages/agency_operations_core/lib/src/observability/observability_port.dart`
- Create: `packages/agency_operations_core/lib/src/analytics/analytics_event.dart`
- Create: `packages/agency_operations_core/lib/src/analytics/analytics_port.dart`
- Create: `packages/agency_operations_core/lib/src/deployment/deployment_port.dart`
- Create: `packages/agency_operations_core/lib/src/hardening/hardening_models.dart`
- Create: `packages/agency_operations_core/lib/src/release/release_failure.dart`
- Create: `packages/agency_operations_core/lib/src/release/recovery_policy.dart`
- Test: `packages/agency_operations_core/test/observability_contract_test.dart`
- Test: `packages/agency_operations_core/test/analytics_contract_test.dart`
- Test: `packages/agency_operations_core/test/deployment_contract_test.dart`
- Test: `packages/agency_operations_core/test/recovery_policy_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class ObservabilityPort`
  - `abstract interface class AnalyticsPort`
  - `abstract interface class DeploymentPort`
  - `final class AnalyticsEvent`
  - `enum HardeningSeverity { info, low, medium, high, critical }`
  - `enum GateDisposition { advisory, blocking }`
  - `enum ReleaseOutcome { healthy, degraded, failed }`
  - `enum ReleaseFailureCode { candidateMismatch, authorizationMissing, authorizationInvalid, artifactMissing, artifactDigestMismatch, migrationValidationFailed, migrationApplyFailed, stagingSmokeFailed, securityGateFailed, accessibilityGateFailed, performanceGateFailed, observabilityGateFailed, analyticsGateFailed, deploymentFailed, productionSmokeFailed, telemetryHealthFailed, rollbackFailed, recoveryRequired }`
  - `final class RecoveryPolicy`
- Consumes H.1 environment/release context types only through stable values; no Sentry/GA4/Cloudflare imports.

- [ ] **Step 1: Write compile-failing contract tests**

```dart
test('operations ports are provider neutral', () {
  final event = AnalyticsEvent(
    name: 'order_created',
    parameters: const {'environment': 'staging'},
  );
  expect(event.name, 'order_created');
  expect(event.parameters['environment'], 'staging');
});

test('blocking severity is policy data, not inferred from provider', () {
  const finding = HardeningFinding(
    id: 'security-1',
    area: HardeningArea.security,
    severity: HardeningSeverity.high,
    disposition: GateDisposition.blocking,
    summary: 'example',
  );
  expect(finding.disposition, GateDisposition.blocking);
});
```

- [ ] **Step 2: Run focused tests and verify failure**

```bash
cd packages/agency_operations_core
flutter test
```

Expected: FAIL because the package/interfaces do not exist.

- [ ] **Step 3: Implement the minimal provider-neutral contracts**

Exact required methods:

```dart
abstract interface class ObservabilityPort {
  Future<void> captureException(Object error, StackTrace stackTrace, {Map<String, Object?> context = const {}});
  Future<void> captureMessage(String message, {Map<String, Object?> context = const {}});
  Future<void> addBreadcrumb(String message, {Map<String, Object?> data = const {}});
  Future<void> setUserContext(String? userId);
  Future<void> setReleaseContext(Map<String, String> context);
  Future<T> startOperation<T>(String name, Future<T> Function() operation);
  Future<void> flush();
}

abstract interface class AnalyticsPort {
  Future<void> trackEvent(AnalyticsEvent event);
  Future<void> setUserProperties(Map<String, Object?> properties);
  Future<void> setConsent({required bool analyticsStorage});
  Future<void> setReleaseContext(Map<String, String> context);
  Future<void> flush();
}

abstract interface class DeploymentPort {
  Future<DeploymentResult> deployStaging(DeploymentRequest request);
  Future<DeploymentResult> promoteExactArtifactToProduction(DeploymentRequest request);
  Future<DeploymentResult> rollbackToKnownGood(DeploymentRequest request);
  Future<DeploymentResult?> currentDeployment(String environment);
  Future<DeploymentHealth> deploymentHealth(String deploymentId);
}
```

- [ ] **Step 4: Add recovery-policy tests**

Prove:
- previous-known-good artifact rollback may be allowed,
- database reversal requires `migrationReversible == true`,
- a new artifact digest is rejected as rollback.

- [ ] **Step 5: Run tests/analyze**

```bash
flutter test
flutter analyze
```

- [ ] **Step 6: Commit**

```bash
git add packages/agency_operations_core
git commit -m "feat: add provider-neutral operations contracts"
```

### Task 2: Exact release-candidate and immutable ReleaseRecord models

**Files:**
- Create: `packages/agency_operations_core/lib/src/release/release_candidate.dart`
- Create: `packages/agency_operations_core/lib/src/release/release_record.dart`
- Modify: `packages/agency_operations_core/lib/agency_operations_core.dart`
- Test: `packages/agency_operations_core/test/release_candidate_test.dart`
- Test: `packages/agency_operations_core/test/release_record_test.dart`
- Create: `client-projects/schema/h2-release-candidate.schema.json`
- Create: `client-projects/schema/h2-release-record.schema.json`

**Interfaces:**
- Produces:
  - `ReleaseCandidate`
  - `ReleaseRecord`
  - deterministic `candidateIdentity`
  - deterministic `releaseIdentity`
- Candidate canonical fields:
  `clientId`, `targetEnvironment`, `sourceSha`, `artifactDigest`, `buildVersion`, `migrationSet`, `releaseConfigIdentity`, `approvedExperienceRef`, `h1FoundationReportRef`.
- ReleaseRecord additionally binds hardening report, G authorization, deployment result, production smoke, telemetry health, previous known-good release, and outcome.

- [ ] **Step 1: Write identity-stability tests**

```dart
test('candidate identity changes when artifact digest changes', () {
  final a = fixtureCandidate(artifactDigest: 'sha256:NaN');
  final b = fixtureCandidate(artifactDigest: 'sha256:NaN');
  expect(a.candidateIdentity, isNot(b.candidateIdentity));
});
```

Also prove identity changes for source SHA, environment, migration set, config identity, and build version.

- [ ] **Step 2: Implement canonical JSON hashing**

Use sorted canonical JSON and SHA-256 with prefix `sha256:`.

- [ ] **Step 3: Write ReleaseRecord immutability tests**

A record cannot report `healthy` without production deployment, production-smoke evidence, telemetry-health evidence, and a production-authorization ID.

- [ ] **Step 4: Implement JSON schemas mirroring the Dart contract**

Use JSON Schema draft already used by the repository; require all identity-bearing fields and restrict outcomes to `healthy|degraded|failed`.

- [ ] **Step 5: Run tests/analyze and commit**

```bash
cd packages/agency_operations_core
flutter test
flutter analyze
git add . ../../client-projects/schema/h2-release-candidate.schema.json ../../client-projects/schema/h2-release-record.schema.json
git commit -m "feat: bind exact release candidate and release record identities"
```

### Task 3: Reference Sentry, GA4, and Cloudflare adapters

**Files:**
- Create: `packages/agency_sentry_adapter/pubspec.yaml`
- Create: `packages/agency_sentry_adapter/lib/agency_sentry_adapter.dart`
- Create: `packages/agency_sentry_adapter/lib/src/sentry_observability_adapter.dart`
- Create: `packages/agency_sentry_adapter/test/sentry_observability_adapter_test.dart`
- Create: `packages/agency_ga4_adapter/pubspec.yaml`
- Create: `packages/agency_ga4_adapter/lib/agency_ga4_adapter.dart`
- Create: `packages/agency_ga4_adapter/lib/src/ga4_analytics_adapter.dart`
- Create: `packages/agency_ga4_adapter/test/ga4_analytics_adapter_test.dart`
- Create: `packages/agency_cloudflare_adapter/pubspec.yaml`
- Create: `packages/agency_cloudflare_adapter/lib/agency_cloudflare_adapter.dart`
- Create: `packages/agency_cloudflare_adapter/lib/src/cloudflare_pages_deployment_adapter.dart`
- Create: `packages/agency_cloudflare_adapter/test/cloudflare_pages_deployment_adapter_test.dart`

**Interfaces:**
- All three packages depend on `agency_operations_core`.
- Provider SDK/HTTP details remain inside adapter packages.
- Each adapter accepts an injectable narrow transport seam so ordinary tests and PR CI require no live credentials.
- Cloudflare production promotion accepts an existing artifact path/digest and must not call a build command.

- [ ] **Step 1: Write Sentry adapter tests**

Prove release/environment/client/candidate context is forwarded, correlation ID survives, and sensitive keys `password`, `authorization`, `cookie`, `service_role_key`, `secret`, `token` are redacted before capture.

- [ ] **Step 2: Implement Sentry adapter behind an injectable transport**

Use the production Sentry SDK only inside the adapter package. Unit tests use a recording transport.

- [ ] **Step 3: Write GA4 adapter tests**

Prove governed event name/parameters are forwarded, environment is attached, consent=false suppresses analytics emission, and no secret-like parameter names are allowed.

- [ ] **Step 4: Implement GA4 adapter**

Use a narrow injectable GA4 transport; do not put Measurement Protocol secrets in Flutter config.

- [ ] **Step 5: Write Cloudflare adapter tests**

Prove:
- staging deployment uses the exact supplied artifact,
- production promotion uses the exact same digest,
- rollback targets a supplied known-good deployment,
- no adapter method invokes a source build.

- [ ] **Step 6: Implement Cloudflare Pages adapter**

Provider credentials are constructor/server inputs only. The adapter returns provider deployment ID, URL, environment, artifact digest, and status.

- [ ] **Step 7: Run all three package suites and commit**

```bash
cd packages/agency_sentry_adapter && flutter test && flutter analyze
cd ../agency_ga4_adapter && flutter test && flutter analyze
cd ../agency_cloudflare_adapter && flutter test && flutter analyze
git add packages/agency_sentry_adapter packages/agency_ga4_adapter packages/agency_cloudflare_adapter
git commit -m "feat: add Sentry GA4 and Cloudflare reference adapters"
```

---

# Cycle H.2A-2 — Hardening Policies, Staging Proof, and Candidate Freeze

### Task 4: Repository-owned hardening policies and validators

**Files:**
- Create: `client-projects/reference-commerce/production/hardening/hardening-policy.yaml`
- Create: `client-projects/reference-commerce/production/hardening/security-policy.yaml`
- Create: `client-projects/reference-commerce/production/hardening/performance-budget.yaml`
- Create: `client-projects/reference-commerce/production/hardening/accessibility-policy.yaml`
- Create: `client-projects/reference-commerce/production/hardening/analytics-taxonomy.yaml`
- Create: `client-projects/reference-commerce/production/hardening/recovery-policy.yaml`
- Create: `tooling/hardening/__init__.py`
- Create: `tooling/hardening/policies.py`
- Test: `tooling/validation/test_h2_hardening_policies.py`

**Interfaces:**
- `validate_hardening_policies(root: Path, client_dir: Path) -> list[str]`
- Exact reference performance budgets:
  - `main_js_raw_bytes_max: 4500000`
  - `web_build_total_bytes_max: 18000000`
  - `first_contentful_paint_ms_max: 3000`
  - `largest_contentful_paint_ms_max: 4500`
  - `critical_screen_ready_ms_max: 4500`
  - `critical_api_p95_ms_max: 1200`
  - `baseline_regression_percent_max: 20`
- Critical journeys are exactly: `sign-in`, `catalog`, `product-detail`, `cart-order`, `b2b-account-credit`, `rfq-quotation-order`.
- Security blocking severities: `critical` and `high` when finding status is open and policy classifies it release-relevant.
- Recovery policy allows application rollback to previous known-good artifact; database reversal requires explicit reversible flag.

- [ ] **Step 1: Write validator tests for exact budgets and required policy files**

```python
def test_reference_performance_budget_is_explicit():
    policy = load_yaml(PERFORMANCE_BUDGET)
    assert policy["main_js_raw_bytes_max"] == 4_500_000
    assert policy["web_build_total_bytes_max"] == 18_000_000
    assert policy["critical_api_p95_ms_max"] == 1_200
    assert policy["baseline_regression_percent_max"] == 20
```

- [ ] **Step 2: Add negative tests**

Reject missing critical journey, threshold <= 0, unknown release outcome, missing recovery mode, and any policy that marks production authorization as automated.

- [ ] **Step 3: Implement validator**

Return stable sorted errors. No network calls.

- [ ] **Step 4: Run validator tests and commit**

```bash
py -3.12 -m unittest tooling.validation.test_h2_hardening_policies -v
git add client-projects/reference-commerce/production/hardening tooling/hardening/policies.py tooling/validation/test_h2_hardening_policies.py
git commit -m "feat: define production hardening policies"
```

### Task 5: Candidate build manifest and artifact integrity

**Files:**
- Create: `tooling/hardening/candidate.py`
- Create: `client-projects/reference-commerce/production/release/candidate.json`
- Create: `client-projects/reference-commerce/production/release/artifact-manifest.json`
- Test: `tooling/validation/test_h2_candidate.py`
- Create: `.github/workflows/candidate-build.yml`

**Interfaces:**
- `build_candidate(root, client_dir, artifact_path, source_sha, build_version) -> dict`
- `verify_candidate_artifact(candidate, artifact_manifest) -> list[str]`
- Artifact manifest contains deterministic SHA-256 digest over the packaged Flutter Web artifact.
- Candidate includes H.1 foundation report reference and approved-experience reference.
- Workflow uploads one immutable build artifact and its manifest. It does not deploy.

- [ ] **Step 1: Write failing candidate-identity tests**

Verify mismatch on source SHA, artifact digest, environment, config identity, or migration-set identity.

- [ ] **Step 2: Implement migration-set and release-config identities**

Migration set identity is SHA-256 over ordered migration file path + normalized content hash pairs. Release-config identity is SHA-256 over canonical production client-safe config used by the candidate.

- [ ] **Step 3: Implement artifact packaging identity**

Package `apps/production_app/build/web` deterministically enough that the manifest hashes the exact deployable directory contents in sorted path order. Do not claim ZIP byte reproducibility across platforms; hash the canonical file-manifest instead.

- [ ] **Step 4: Add candidate-build workflow**

Workflow:
1. checkout exact SHA,
2. set up Flutter,
3. run H.1 validation,
4. build `apps/production_app` web once,
5. create canonical artifact manifest and candidate JSON,
6. upload the web directory + manifest + candidate,
7. never deploy and never create authorization.

- [ ] **Step 5: Test workflow structure with static validator**

Add test asserting no `wrangler pages deploy`, production deployment command, authorization creation command, or second `flutter build web` appears after candidate artifact creation.

- [ ] **Step 6: Commit**

```bash
git add tooling/hardening/candidate.py tooling/validation/test_h2_candidate.py client-projects/reference-commerce/production/release .github/workflows/candidate-build.yml
git commit -m "feat: build immutable H2 release candidates"
```

### Task 6: Security, performance, accessibility, analytics, observability, and migration gates

**Files:**
- Create: `tooling/hardening/security.py`
- Create: `tooling/hardening/performance.py`
- Create: `tooling/hardening/accessibility.py`
- Create: `tooling/hardening/analytics.py`
- Create: `tooling/hardening/observability.py`
- Create: `tooling/hardening/migrations.py`
- Test: `tooling/validation/test_h2_security_gate.py`
- Test: `tooling/validation/test_h2_performance_gate.py`
- Test: `tooling/validation/test_h2_accessibility_gate.py`
- Test: `tooling/validation/test_h2_analytics_gate.py`
- Test: `tooling/validation/test_h2_observability_gate.py`
- Test: `tooling/validation/test_h2_migration_gate.py`

**Interfaces:**
- Each evaluator returns a deterministic list of finding dictionaries with `id`, `area`, `severity`, `disposition`, `status`, `summary`, `evidence_refs`.
- Provider-native scanner severity is preserved.
- Gate aggregation blocks only on `disposition == blocking && status == open`.

- [ ] **Step 1: Implement security gate tests**

Fixtures cover:
- critical/high open finding → blocking,
- medium finding → advisory,
- committed secret-like config → blocking,
- RLS/auth policy validation failure → blocking,
- production debug flag enabled → blocking.

- [ ] **Step 2: Implement security evaluator**

Consume static scanner/security evidence JSON; do not run arbitrary remote scanners inside the evaluator.

- [ ] **Step 3: Implement performance gate tests against exact policy thresholds**

Boundary value passes at threshold and fails at threshold + 1; baseline regression fails above 20%.

- [ ] **Step 4: Implement accessibility gate**

Critical journey missing keyboard/focus/semantic evidence is blocking; non-critical manual-review issue can remain advisory.

- [ ] **Step 5: Implement analytics gate**

Require governed critical event names:
`sign_in`, `catalog_view`, `product_view`, `cart_created`, `cart_updated`, `checkout_or_order_start`, `order_created`, `business_account_selected`, `credit_viewed`, `rfq_created`, `quotation_viewed`, `quotation_converted`.

- [ ] **Step 6: Implement observability gate**

Require initialized reference adapter evidence, release/environment/client/candidate tags, handled/unhandled capture evidence, and redaction evidence.

- [ ] **Step 7: Implement migration gate**

Require exact migration-set identity, staging-apply evidence, post-apply verification, and recovery treatment for transformative/destructive migrations.

- [ ] **Step 8: Run all gate tests and commit**

```bash
py -3.12 -m unittest tooling.validation.test_h2_security_gate tooling.validation.test_h2_performance_gate tooling.validation.test_h2_accessibility_gate tooling.validation.test_h2_analytics_gate tooling.validation.test_h2_observability_gate tooling.validation.test_h2_migration_gate -v
git add tooling/hardening tooling/validation
git commit -m "feat: enforce H2 operational hardening gates"
```

### Task 7: Staging deployment, smoke tests, and hardening report

**Files:**
- Create: `tooling/hardening/staging_smoke.py`
- Create: `tooling/hardening/report.py`
- Create: `tooling/hardening/validate.py`
- Create: `client-projects/schema/h2-hardening-report.schema.json`
- Create: `client-projects/schema/h2-smoke-report.schema.json`
- Create: `client-projects/reference-commerce/production/evidence/staging-smoke-report.json`
- Create: `client-projects/reference-commerce/production/evidence/h2-hardening-report.json`
- Create: `client-projects/reference-commerce/production/release/staging-deployment.json`
- Create: `.github/workflows/staging-deploy.yml`
- Create: `.github/workflows/h2-hardening.yml`
- Test: `tooling/validation/test_h2_staging_smoke.py`
- Test: `tooling/validation/test_h2_hardening_report.py`

**Interfaces:**
- `run_staging_smoke(...)->dict`
- `build_hardening_report(...)->dict`
- Hardening report binds candidate identity and every gate result.
- Report contains `blocking_findings`, `advisory_findings`, `eligible_for_authorization`.
- `eligible_for_authorization` is true only when blocking findings are empty and staging critical journeys pass.

- [ ] **Step 1: Write deterministic smoke-orchestration tests**

Critical staged journeys:
- B2C sign-in → catalog → inventory → cart → order,
- B2B sign-in → membership → credit → RFQ → quotation → order,
- session refresh,
- insufficient permission,
- backend failure mapping,
- release/version identity endpoint or build marker.

- [ ] **Step 2: Implement smoke runner with injectable HTTP/browser seam**

Unit/PR tests use fixtures. Live staging workflow uses the real staging URL supplied by deployment output.

- [ ] **Step 3: Write hardening-report tests**

Prove one blocking finding makes `eligible_for_authorization=false`; advisory-only report remains eligible; candidate mismatch fails validation.

- [ ] **Step 4: Implement staging-deploy workflow**

The workflow downloads the candidate artifact built by Task 5 and deploys through Cloudflare tooling. It must not call `flutter build web`.

- [ ] **Step 5: Implement H.2 hardening workflow**

Run security/performance/accessibility/analytics/observability/migration gates and staging smoke against the exact staged candidate; emit report artifacts.

- [ ] **Step 6: Add credential-free validation mode**

PR CI validates workflow structure and committed fixture reports without Cloudflare/Sentry/GA4/Supabase production credentials.

- [ ] **Step 7: Commit**

```bash
git add tooling/hardening client-projects/schema client-projects/reference-commerce/production .github/workflows/staging-deploy.yml .github/workflows/h2-hardening.yml tooling/validation
git commit -m "feat: prove staging hardening readiness"
```

---

# Cycle H.2B — Authorized Release, Health, and Recovery

### Task 8: Bridge H.2 exact-candidate identity to existing G authorization

**Files:**
- Create: `tooling/release/__init__.py`
- Create: `tooling/release/coordinator.py`
- Create: `tooling/release/evidence.py`
- Create: `client-projects/reference-commerce/production/release/production-authorization-ref.json`
- Test: `tooling/validation/test_h2_authorization_bridge.py`

**Interfaces:**
- `verify_h2_authorized_candidate(h2_candidate, g_candidate, authorization, invalidation_events=()) -> None`
- Must call existing `tooling.production_authorization.release_gate.verify_release_gate`.
- H.2 additionally verifies H.2-only candidate fields: migration-set identity, release-config identity, H.1 report ref, hardening report candidate identity, and artifact manifest digest.
- No function in `tooling/release` may create `ProductionAuthorization`.

- [ ] **Step 1: Write mismatch tests**

Fail on:
- source SHA mismatch,
- artifact digest mismatch,
- environment mismatch,
- migration set mismatch,
- config identity mismatch,
- hardening report bound to another candidate,
- invalidated/revoked G authorization.

- [ ] **Step 2: Implement bridge by delegating G validity to existing release gate**

Do not duplicate G authorization-validity logic.

- [ ] **Step 3: Add authority-boundary test**

Static test fails if `tooling/release` imports G coordinator functions that create authorization.

- [ ] **Step 4: Add exact H.2 synthetic human authorization fixture**

Create a new explicit reference authorization fixture for the exact H.2 candidate only after candidate/hardening identities are known. Do not reuse H.1/G historical authorization.

- [ ] **Step 5: Commit**

```bash
git add tooling/release client-projects/reference-commerce/production/release tooling/validation/test_h2_authorization_bridge.py
git commit -m "feat: bind H2 release to exact G authorization"
```

### Task 9: Production release coordinator, smoke, telemetry health, and ReleaseRecord

**Files:**
- Create: `tooling/release/smoke.py`
- Create: `tooling/release/telemetry_health.py`
- Create: `tooling/release/release_record.py`
- Create: `client-projects/schema/h2-telemetry-health-report.schema.json`
- Create: `client-projects/reference-commerce/production/evidence/production-smoke-report.json`
- Create: `client-projects/reference-commerce/production/evidence/telemetry-health-report.json`
- Create: `client-projects/reference-commerce/production/evidence/release-record.json`
- Test: `tooling/validation/test_h2_production_release.py`
- Test: `tooling/validation/test_h2_release_record.py`

**Interfaces:**
- `run_production_smoke(...)->dict`
- `evaluate_telemetry_health(...)->dict`
- `build_release_record(...)->dict`
- Production smoke is low-risk and may not create uncontrolled real orders.
- Reference production smoke:
  - release/build identity reachable,
  - app shell reachable,
  - auth/session endpoint healthy using designated synthetic release-check identity,
  - catalog/inventory read,
  - permission-denied negative check,
  - no uncontrolled order/payment side effect.
- Telemetry health window is deterministically represented by exactly 5 samples at 60-second spacing when live execution is enabled, for a total 4-minute observation span. Fixture/unit mode supplies 5 recorded samples immediately.
- Blocking telemetry condition: any critical unhandled error attributed to the release, failed health signal, or configured critical-error-rate threshold breach.

- [ ] **Step 1: Write production-smoke safety tests**

Assert no smoke step invokes order/payment mutation APIs unless fixture mode explicitly marks the mutation sandbox-safe.

- [ ] **Step 2: Implement low-risk production smoke**

Use injectable HTTP/browser seam.

- [ ] **Step 3: Write telemetry-health tests**

Exactly 5 ordered samples required; wrong release tag, missing sample, critical error, or failed deployment health makes outcome failed.

- [ ] **Step 4: Implement bounded telemetry evaluator**

The evaluator consumes sample evidence; sleeping/polling belongs only in live workflow wrapper, not unit logic.

- [ ] **Step 5: Write ReleaseRecord tests**

Healthy requires all evidence; degraded requires advisory/incident refs; failed requires failure evidence and recovery disposition.

- [ ] **Step 6: Implement deterministic ReleaseRecord identity**

Canonical JSON + SHA-256 excluding `release_identity`.

- [ ] **Step 7: Commit**

```bash
git add tooling/release client-projects/schema client-projects/reference-commerce/production/evidence tooling/validation
git commit -m "feat: record authorized production release health"
```

### Task 10: Recovery coordinator and governed rollback evidence

**Files:**
- Create: `tooling/release/recovery.py`
- Create: `client-projects/reference-commerce/production/evidence/recovery-report.json`
- Test: `tooling/validation/test_h2_recovery.py`

**Interfaces:**
- `plan_recovery(release_record, recovery_policy, previous_known_good) -> RecoveryDecision`
- `execute_recovery(decision, deployment_port, migration_executor) -> RecoveryReport`
- New artifact digest is rejected from rollback.
- Database rollback permitted only when exact migration metadata says reversible and recovery policy allows it.
- Otherwise decision is forward recovery/manual halt.

- [ ] **Step 1: Write application rollback tests**

A failed release may target only the previous-known-good artifact/deployment identified in the ReleaseRecord chain.

- [ ] **Step 2: Write database recovery tests**

Non-reversible migration → no reverse SQL execution; result is `forward_recovery_required` or `manual_halt_required`.

- [ ] **Step 3: Implement recovery coordinator**

Keep decision logic provider-neutral. Deployment mechanics remain behind `DeploymentPort`.

- [ ] **Step 4: Write immutable recovery report**

Include failed release ID, reason, selected action, previous-known-good ID, migration action, deployment result, verification result, and report identity.

- [ ] **Step 5: Commit**

```bash
git add tooling/release/recovery.py client-projects/reference-commerce/production/evidence/recovery-report.json tooling/validation/test_h2_recovery.py
git commit -m "feat: add governed production recovery flow"
```

### Task 11: GitHub Actions production-release workflow and no-rebuild enforcement

**Files:**
- Create: `.github/workflows/production-release.yml`
- Test: `tooling/validation/test_h2_release_workflow.py`
- Modify: `.github/workflows/validate.yml`
- Modify: `.github/workflows/flutter-ci.yml`

**Interfaces:**
- Production workflow inputs: candidate artifact/run identity and production authorization reference.
- Workflow order:
  1. download exact candidate/artifact,
  2. verify H.2 candidate,
  3. verify G authorization,
  4. verify artifact digest,
  5. verify migration-set identity,
  6. apply authorized migrations,
  7. deploy exact artifact via Cloudflare reference mechanism,
  8. production smoke,
  9. 5-sample telemetry health window,
  10. finalize ReleaseRecord,
  11. if failed, invoke governed recovery path.
- Workflow contains no `flutter build web`.

- [ ] **Step 1: Write static workflow tests**

Assert:
- no build command,
- no authorization creation command,
- release-gate verification occurs before deploy,
- artifact digest verification occurs before deploy,
- production smoke and health occur after deploy,
- recovery runs only on failed outcome.

- [ ] **Step 2: Implement production workflow**

Use GitHub environment protection for `production` as an execution safeguard, but do not treat it as replacement for G authorization.

- [ ] **Step 3: Add secret-name validation**

Expected live secrets are referenced only through GitHub environment secrets, e.g. Cloudflare API token/account/project identifiers and server-side telemetry credentials. No secret values are committed.

- [ ] **Step 4: Extend credential-free PR CI**

PR CI runs static workflow validation and all H.2 deterministic tests without invoking live deployments.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows tooling/validation/test_h2_release_workflow.py
git commit -m "feat: add exact-artifact authorized release workflow"
```

---

# Cycle H.2C — Workflow Integration, Reference Proof, and Final Delivery

### Task 12: Workflow/runtime integration and repository authority boundaries

**Files:**
- Modify: `workflows/08-productionize.md`
- Modify: `workflows/contracts/08-productionize.yaml`
- Create: `workflows/09-release.md`
- Create: `workflows/contracts/09-release.yaml`
- Modify: `tooling/workflow/contracts.py`
- Modify: `tooling/validation/validate_repo.py`
- Modify: `tooling/validation/test_validate_repo.py`
- Create: `tooling/validation/test_h2_authority_boundaries.py`
- Create: `tooling/validation/test_h2_workflow_integration.py`
- Modify: `AGENTS.md`
- Modify: `docs/client-delivery.md`

**Interfaces:**
- Stage 08 remains `production-capable` / H.1 foundation.
- New stage 09 `release` consumes H.1 evidence + H.2 hardening evidence + exact G authorization.
- Stage 09 writes release evidence through the workflow runtime but does not create authorization.
- Stage 09 checkpoints: `staging-validated`, `candidate-authorized`, `production-released`.
- Stage 09 validators: `h2-hardening`, `production-authorization`, `h2-release-record`.

- [ ] **Step 1: Write workflow contract tests**

Assert stage 09 cannot complete with missing H.2 hardening report or missing exact G authorization.

- [ ] **Step 2: Implement stage-09 contract**

```yaml
stage: release
version: 1
requires:
  stages:
    - productionize
  artifacts:
    - production/evidence/h1-foundation-report.json
    - production/evidence/h2-hardening-report.json
produces:
  - production/evidence/release-record.json
validators:
  - h2-hardening
  - production-authorization
  - h2-release-record
checkpoints:
  - staging-validated
  - candidate-authorized
  - production-released
next: []
```

Adjust exact paths to existing workflow contract conventions while preserving semantics.

- [ ] **Step 3: Add authority-boundary tests**

Reject:
- any H.2 code path that creates authorization,
- any stage-08 production deployment,
- provider SDK imports in operations core,
- privileged secret values/config in client files,
- direct workflow-state mutation outside runner.

- [ ] **Step 4: Update repository docs and required paths**

Remove obsolete wording that H.2/H.3 are future milestones. Document the single H.2 model.

- [ ] **Step 5: Run workflow/repository validation and commit**

```bash
py -3.12 -m unittest tooling.validation.test_h2_workflow_integration tooling.validation.test_h2_authority_boundaries tooling.validation.test_validate_repo -v
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 tooling/validation/validate_repo.py
git add workflows tooling AGENTS.md docs/client-delivery.md
git commit -m "feat: integrate H2 authorized release workflow"
```

### Task 13: Reference-commerce end-to-end release proof

**Files:**
- Modify/create reference artifacts only under `client-projects/reference-commerce/production/release/` and `.../evidence/`
- Test: `tooling/validation/test_h2_reference_release.py`
- Create: `tooling/release/validate.py`

**Interfaces:**
- Deterministic fixture mode proves the complete control flow with synthetic provider responses.
- Live reference proof, when credentials and explicit human approval are provided, deploys the exact staging-tested artifact and records provider IDs/URLs without committing secrets.
- A live successful release updates committed evidence only through sanitized, schema-valid artifacts.
- The exact human-created G authorization for the frozen candidate is required before production.

- [ ] **Step 1: Implement deterministic fixture-mode reference proof**

Prove:
candidate build → staging deploy fixture → all H.2A gates pass → candidate freeze → exact G authorization fixture → exact artifact production promotion fixture → production smoke → telemetry health → healthy ReleaseRecord.

- [ ] **Step 2: Add negative reference scenarios**

Candidate mismatch, digest mismatch, authorization invalidation, migration failure, production smoke failure, telemetry failure, and rollback path.

- [ ] **Step 3: Implement reference release validator**

`python -m tooling.release.validate client-projects/reference-commerce` validates all identities and evidence chains without network calls.

- [ ] **Step 4: Run deterministic end-to-end proof**

```bash
py -3.12 -m unittest tooling.validation.test_h2_reference_release -v
py -3.12 -m tooling.release.validate client-projects/reference-commerce
```

- [ ] **Step 5: Stop before live external deployment**

A real staging/production Cloudflare/Supabase release is an external side effect and uses security-sensitive credentials. The executing agent must stop here and request explicit human authorization before triggering live deployment workflows.

- [ ] **Step 6: After explicit authorization, execute the live reference proof**

Use configured GitHub environments/secrets. Do not expose secret values in logs or committed artifacts. Verify exact artifact digest before and after deployment.

- [ ] **Step 7: Sanitize and commit live evidence**

Commit only schema-valid provider IDs, deployment URLs allowed by policy, timestamps, identities, results, and evidence refs. Never commit credentials/tokens.

- [ ] **Step 8: Commit**

```bash
git add client-projects/reference-commerce/production tooling/release/validate.py tooling/validation/test_h2_reference_release.py
git commit -m "test: prove authorized reference production release"
```

### Task 14: Full regression, final review, ledger, and PR delivery

**Files:**
- Create: `docs/superpowers/ledgers/2026-09-18-milestone-h2-production-hardening-authorized-release-ledger.md`
- Modify only files required by reviewed findings.

**Interfaces:**
- No new architecture. This task proves all 46 H.2 acceptance criteria and records final evidence.

- [ ] **Step 1: Run full Python validation**

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
py -3.12 -m tooling.production.report client-projects/reference-commerce
py -3.12 -m tooling.hardening.validate client-projects/reference-commerce
py -3.12 -m tooling.release.validate client-projects/reference-commerce
```

- [ ] **Step 2: Run all H.1 and H.2 Dart/Flutter packages**

```bash
cd packages/agency_production_core && flutter test && flutter analyze
cd ../agency_supabase_adapter && flutter test && flutter analyze
cd ../agency_integration_adapters && flutter test && flutter analyze
cd ../agency_operations_core && flutter test && flutter analyze
cd ../agency_sentry_adapter && flutter test && flutter analyze
cd ../agency_ga4_adapter && flutter test && flutter analyze
cd ../agency_cloudflare_adapter && flutter test && flutter analyze
cd ../../apps/production_app && flutter test && flutter analyze && flutter build web
```

Also run the existing shared UI, prototype app, and Widgetbook regression required by repository policy.

- [ ] **Step 3: Run design/runtime freshness checks**

Run canonical B.1D Flutter-binding and B.1E resolved-theme `--check` commands. Both must be fresh.

- [ ] **Step 4: Validate no-rebuild and authority boundaries**

Explicitly inspect workflow files and test evidence for:
- production workflow contains no build step,
- G release gate called before production deployment,
- no H.2 authorization creation,
- exact artifact/migration/config identities match,
- provider secrets absent from repo/client config,
- stage-08 still non-deploying,
- stage-09 uses workflow runner authority.

- [ ] **Step 5: Review `git diff origin/main...HEAD` against all 46 H.2 acceptance criteria**

Target: 0 blockers / 0 majors.

- [ ] **Step 6: Fix reviewed blockers/majors and rerun affected suites**

Use SDD fix-loop rules. Record any residual minors and rulings.

- [ ] **Step 7: Finalize ledger**

Record:
- task commits,
- reviewer findings and fixes,
- all rulings/deviations,
- exact Python and Dart/Flutter test counts,
- hardening gate results,
- candidate/artifact identity,
- staging proof,
- authorization identity,
- release/rollback proof,
- CI run results,
- final branch SHA,
- live-release status,
- known limitations,
- deferred Android/iOS and client-specific integrations.

- [ ] **Step 8: Push and open PR**

PR title:

`Milestone H.2 - Production Hardening and Authorized Release`

Do not merge without explicit human authorization.
