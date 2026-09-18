# Milestone H.2 — Production Hardening & Authorized Release Design

Status: Approved conversational design, written for user review before implementation planning.

Base dependency: Milestone H.1 Production Foundation, branch `milestone-h1-production-foundation` at `2ab32431664314d66b175f2823acb55442afc657`.

## 1. Purpose

Milestone H.2 completes the agency platform's production journey by combining the previously separate operational-hardening and authorized-release milestones into one governed production milestone.

H.2 has two internal phases:

```text
H.2A Operational Hardening
→ G ProductionAuthorization for the exact candidate
→ H.2B Authorized Release
```

The reference proof targets Flutter Web + Supabase and deploys through GitHub Actions to Cloudflare Pages. Android/iOS store release automation is explicitly deferred.

H.2 does not replace or weaken any existing authority from C/D/E/F/G/H.1.

## 2. End-to-End Flow

```text
H.1 production-capable application
        ↓
build exact release candidate
        ↓
deploy candidate to staging
        ↓
H.2A hardening gates
   ├─ security
   ├─ observability
   ├─ analytics
   ├─ performance
   ├─ accessibility
   ├─ migration readiness
   └─ staging smoke/journey tests
        ↓
freeze exact candidate
   source SHA
   artifact digest
   build version
   environment
   migration set
   release-relevant config identity
        ↓
G ProductionAuthorization
        ↓
H.2B authorized release
   ├─ verify exact-candidate authorization
   ├─ deploy the already-built artifact
   ├─ apply approved migrations
   ├─ run production smoke tests
   ├─ verify telemetry health
   └─ finalize release evidence
        ↓
Production
        ├─ healthy  → complete
        ├─ degraded → incident/advisory record
        └─ failed   → halt + rollback/recovery
```

## 3. Scope

### H.2A Operational Hardening

H.2A includes:

- provider-neutral observability contract
- Sentry reference observability adapter
- provider-neutral analytics contract
- GA4 reference analytics adapter
- release/version/environment tagging
- structured logs and correlation identifiers
- security scanning and release security evidence
- accessibility gates on critical journeys
- performance budgets and regression checks
- migration readiness, staging migration application, and recovery planning
- staging deployment of the exact candidate
- staging B2C/B2B smoke/journey validation
- blocking versus advisory gate classification
- immutable hardening evidence bound to one exact candidate

### H.2B Authorized Release

H.2B includes:

- GitHub Actions as reference CI/CD executor
- provider-neutral deployment contract
- Cloudflare Pages as the Flutter Web reference deployment adapter
- verification of Milestone G `ProductionAuthorization`
- exact-artifact deployment with no post-authorization rebuild
- approved migration application
- production smoke tests
- telemetry health window
- release outcome classification
- rollback/recovery execution under a pre-authorized recovery policy
- immutable release evidence

### Explicitly deferred

H.2 does not include:

- Android/iOS signing or store release automation
- arbitrary real ERP/payment/shipping/CRM/WhatsApp vendor integrations
- replacement of Supabase as the reference H.1 backend proof
- creation of a `ProductionAuthorization`
- autonomous approval of a release by CI or AI
- multi-client fleet/orchestration management
- generalized incident-management platform
- generalized feature-flag platform
- uncontrolled automatic database rollback

## 4. Authority Model

Authorities remain separated.

| Authority | Owns |
|---|---|
| `ApprovalSnapshot` | approved client experience |
| Review / refinement authorities | client-review state and change handling |
| Visual-QA authorities | visual findings and QA evidence |
| H.1 | production implementation |
| H.2A | hardening/readiness evidence |
| `ProductionAuthorization` | human permission for one exact production candidate |
| H.2B | authorized release execution |
| GitHub Actions | executor only |
| Deployment adapter | deployment mechanism only |
| Supabase | backend reference implementation only |
| Sentry | observability reference implementation only |
| GA4 | analytics reference implementation only |
| Cloudflare Pages | web-hosting reference implementation only |

Rules:

1. H.2A must not create `ProductionAuthorization`.
2. H.2B must not deploy unless the candidate matches a valid G authorization exactly.
3. GitHub Actions, agents, QA tooling, Sentry, GA4, Cloudflare, and Supabase must not become release authority.
4. A new source SHA, artifact digest, migration set, target environment, or release-relevant configuration identity produces a different candidate.
5. A different candidate requires new hardening evidence and a new G authorization before production release.
6. H.2 must not silently alter approved UX. Experience-contract changes return to the existing review/approval workflow.

## 5. Reference Production Stack

The reference path is:

```text
Flutter Web
   ↓
GitHub Actions
   ↓
DeploymentPort
   ↓
CloudflarePagesDeploymentAdapter

Backend
   ↓
Supabase
   ├─ Postgres
   ├─ Auth
   └─ Storage where required

Telemetry
   ├─ ObservabilityPort → SentryAdapter
   └─ AnalyticsPort     → Ga4Adapter
```

The platform contracts remain provider-neutral. Concrete providers prove the contracts but do not define them.

## 6. Provider-Neutral Hardening Interfaces

H.2 should define focused production contracts rather than exposing provider SDKs to application code.

### Observability

```text
ObservabilityPort
├─ captureException
├─ captureMessage
├─ addBreadcrumb
├─ setUserContext
├─ setReleaseContext
├─ startOperation
└─ flush
```

Required context includes:

- client ID
- environment
- source SHA
- build version
- release candidate ID
- release record ID when available
- correlation/request ID when available

Sensitive payloads and secrets must not be logged.

### Analytics

```text
AnalyticsPort
├─ trackEvent
├─ setUserProperties
├─ setConsent
├─ setReleaseContext
└─ flush
```

Reference adapter: GA4.

Analytics must use a governed event taxonomy rather than arbitrary event names from screens.

### Deployment

```text
DeploymentPort
├─ deployStaging
├─ promoteExactArtifactToProduction
├─ rollbackToKnownGood
├─ currentDeployment
└─ deploymentHealth
```

Reference adapter: Cloudflare Pages.

H.2B must deploy the already-built authorized artifact. The production step must not rebuild from source.

## 7. Release Candidate Identity

A release candidate must have a canonical identity that binds all release-relevant inputs.

Required fields:

```text
ReleaseCandidate
├─ client_id
├─ target_environment
├─ source_sha
├─ artifact_digest
├─ build_version
├─ migration_set
├─ release_config_identity
├─ approved_experience_ref
├─ h1_foundation_report_ref
└─ candidate_identity
```

`candidate_identity` is derived deterministically from canonical content.

The exact candidate is immutable once submitted for H.2A hardening.

## 8. Staging-First Release Sequence

The required order is:

```text
build exact candidate
→ deploy exact artifact to staging
→ apply staging migrations
→ run H.2A hardening gates
→ run staging smoke/journey tests
→ freeze candidate
→ obtain G ProductionAuthorization
→ verify authorization
→ promote exact artifact to production
→ apply approved production migrations
→ run production smoke
→ telemetry health window
→ finalize ReleaseRecord
```

Production authorization occurs after staging validation, not before.

This ensures the human release owner authorizes a candidate that has already passed operational checks.

## 9. No-Rebuild Rule

After G authorization:

> The authorized artifact is the artifact deployed to production.

The release pipeline must verify:

- source SHA matches authorization
- artifact digest matches authorization
- environment matches authorization
- build version matches authorization
- migration set matches authorization
- required evidence references match authorization/candidate
- release configuration identity matches the frozen candidate

A rebuild, even from the same source SHA, is a new artifact unless its digest is exactly identical. A changed artifact requires a new candidate and new authorization.

## 10. Hardening Gate Model

H.2A distinguishes blocking gates from advisory findings.

| Area | Blocking before production | Advisory / monitored |
|---|---|---|
| Security | critical/high exploitable vulnerability, secret leakage, broken auth/RLS, unsafe release configuration | medium/low findings not classified as release-blocking |
| Accessibility | critical navigation/semantics failure on key journeys | lower-severity issues outside critical journeys |
| Performance | major regression beyond approved budget on key journeys | smaller trend regressions |
| Observability | Sentry/reference adapter not initialized, release tagging missing, critical error capture unavailable | alert tuning/dashboard refinements |
| Analytics | required governed business events invalid or missing on critical journeys | secondary/experimental events |
| Migrations | invalid migration set, staging apply failure, missing recovery treatment | optimization recommendations |
| Staging smoke | critical B2C/B2B/auth journeys fail | non-critical secondary journeys |
| Production health | critical post-release smoke or telemetry health failure | non-critical operational trend |

Gate rule:

```text
blocking failure
→ candidate is not eligible to proceed to G authorization

all blocking gates pass
→ candidate may be frozen and submitted for G authorization
```

Advisory findings remain visible in hardening/release evidence. They must not silently become blockers or silently disappear.

## 11. Security Hardening

Reference security gates should include:

- repository secret scanning
- dependency vulnerability scanning
- release configuration validation
- Flutter/client secret-boundary validation
- Supabase/RLS policy validation
- auth and permission-path tests
- CSP/security-header validation for Flutter Web where applicable
- production debug/dev-mode guard
- migration safety classification
- artifact integrity verification

Security findings need stable identifiers, severity, evidence, status, and blocking classification.

The milestone should not invent its own vulnerability severity system where authoritative scanner severity is available; it may map scanner output into the release blocking policy.

## 12. Observability

The Sentry reference adapter should prove:

- unhandled exception capture
- handled exception capture
- release/source tagging
- environment tagging
- client tagging
- correlation ID propagation
- redaction/sensitive-data rules
- staging telemetry
- production telemetry
- post-release error-health check

Observability is not an authorization mechanism.

Telemetry failure before authorization is a hardening-gate failure when critical release visibility is unavailable.

## 13. Analytics

GA4 is the reference adapter behind `AnalyticsPort`.

Reference-commerce critical events should cover at minimum:

### B2C

- sign_in
- catalog_view
- product_view
- cart_created / cart_updated
- checkout_or_order_start
- order_created

### B2B

- business_account_selected
- credit_viewed
- rfq_created
- quotation_viewed
- quotation_converted
- order_created

Events must include governed names and validated parameter schemas.

Analytics should support environment separation and consent handling. Production and staging data must be distinguishable.

Analytics correctness is validated as contract/event-shape evidence; H.2 is not a marketing attribution platform.

## 14. Performance Budgets

H.2 should define explicit, versioned budgets for the reference Flutter Web journeys rather than vague "fast" requirements.

The implementation plan must establish concrete repository-owned threshold values for:

- web build size
- first meaningful/interactive load proxy
- key-screen render/load timing
- critical API latency budget in staging
- regression tolerance versus approved baseline

Reference checks may use Flutter/web build metrics and Lighthouse-compatible tooling where practical.

Budgets should be enforced on agreed critical journeys and should not require unrealistic absolute perfection.

A threshold change is a reviewed policy change, not an ad-hoc CI bypass.

## 15. Accessibility

Reference critical journeys:

- sign-in
- catalog/discovery
- product detail
- cart/order
- B2B account/credit
- RFQ/quotation/order

Accessibility validation should combine:

- Flutter semantics/widget tests
- keyboard navigation checks for Flutter Web
- focus visibility/order checks
- labels/roles for critical controls
- contrast checks where automatable
- automated web accessibility checks where compatible with Flutter Web
- targeted manual review evidence when automation cannot validate the behavior

Critical accessibility failures on critical journeys are blocking.

## 16. Migration Readiness and Execution

H.1 defines migrations. H.2 operationalizes them.

Before production authorization, H.2A must prove:

- exact migration set identity
- migration ordering
- staging application succeeds
- post-migration verification succeeds
- recovery treatment exists
- destructive/transformative migrations carry explicit handling
- backup/snapshot requirement is stated where relevant

Production release applies only the migration set bound to the authorized candidate.

Migration execution must be idempotent or safely resumable where applicable.

## 17. Rollback and Recovery

Release outcomes are:

- `healthy`
- `degraded`
- `failed`

### Healthy

Critical smoke tests and telemetry health checks pass.

Action: finalize release as complete.

### Degraded

Core journeys remain safe but a non-critical release issue is observed.

Action: keep release live and create incident/advisory evidence. The release is not silently marked healthy.

### Failed

A critical journey, auth, data-integrity, migration, security, or release-health failure occurs.

Action: halt and execute the approved recovery path.

### App rollback

Redeploy the previous known-good artifact.

### Database recovery

Database rollback is permitted only when the exact migration is explicitly reversible and reversal is safe.

Otherwise use a forward recovery migration or other pre-defined recovery procedure.

Blind database rollback is prohibited.

### Recovery authority

Rollback to the previous known-good artifact may be automated only when that behavior is explicitly covered by the pre-authorized recovery policy.

Creating a new fixed artifact is not rollback. It is a new release candidate and requires the H.2A → G authorization sequence again.

## 18. Release Record

Every production release attempt produces one immutable `ReleaseRecord`.

Required fields:

```text
ReleaseRecord
├─ release_id
├─ client_id
├─ environment
├─ source_sha
├─ artifact_digest
├─ build_version
├─ migration_set
├─ release_config_identity
├─ hardening_report_id
├─ production_authorization_id
├─ staging_evidence
├─ production_smoke_evidence
├─ telemetry_health_evidence
├─ deployment_target
├─ release_status
├─ incident_or_advisory_refs
├─ rollback_or_recovery_ref
├─ previous_known_good_release_id
├─ started_at
├─ completed_at
└─ release_identity
```

`release_identity` is derived deterministically from immutable canonical fields.

The ReleaseRecord binds:

```text
approved experience
+
H.1 foundation evidence
+
exact source SHA
+
exact built artifact
+
exact migration set
+
release configuration
+
H.2A hardening evidence
+
G ProductionAuthorization
+
deployment result
+
production health result
↓
ReleaseRecord
```

## 19. Testing Strategy

H.2 uses four production gates.

### Gate 1 — Build and contract validation

Proves:

- code compiles
- package/app tests pass
- config is valid
- migration set is valid
- provider-neutral contracts validate
- hardening policies/configuration validate
- artifact digest is stable

### Gate 2 — Staging journey validation

Runs against the actually deployed staging candidate.

Critical reference journeys:

#### B2C

```text
sign-in
→ catalog
→ inventory
→ cart
→ order
```

#### B2B

```text
sign-in
→ business membership
→ credit
→ RFQ
→ quotation
→ order
```

Also cover:

- session refresh
- insufficient permission
- backend failure handling
- migration compatibility
- telemetry capture
- analytics event emission

### Gate 3 — Production smoke

Runs against the exact production deployment after authorization.

It must be intentionally small and safe: critical reads, auth/session, deployment/version identity, and approved low-risk transaction checks where a production-safe strategy exists.

Tests must not generate uncontrolled production orders or side effects.

### Gate 4 — Telemetry health window

Validates immediate post-release operational health.

At minimum:

- deployment reachable
- expected release version visible
- critical smoke passed
- Sentry/reference observability receives expected test/health signal
- critical error rate does not breach the release policy
- no release-blocking security/integrity signal emerges

The implementation plan must define a deterministic health-window contract; it must not rely on an indefinite human wait.

## 20. GitHub Actions Release Model

GitHub Actions is the reference executor, not an authority.

Recommended workflow separation:

```text
pull-request validation
        ↓
candidate build
        ↓
staging deployment workflow
        ↓
H.2A hardening workflow
        ↓
human/G authorization
        ↓
production release workflow
        ↓
production smoke/health
        ↓
release finalization
```

The production workflow must:

1. accept an existing candidate/artifact identity
2. load the matching G authorization
3. invoke the existing production authorization release gate
4. reject any candidate mismatch
5. download/retrieve the exact artifact without rebuilding
6. apply only the candidate-bound migration set
7. deploy through `DeploymentPort`
8. run production smoke
9. run telemetry health check
10. persist/finalize release evidence

A manually triggered workflow may execute a valid authorization but cannot create it.

## 21. Cloudflare Pages Reference Deployment

Cloudflare Pages is the reference Flutter Web deployment target.

The adapter should prove:

- staging/preview deployment
- production deployment of an existing artifact
- custom environment binding
- deployment identity retrieval
- current deployment inspection
- promotion/production deployment without source rebuild
- rollback to a known-good deployment/artifact where supported by the governed recovery flow

Cloudflare credentials are server/CI secrets and never enter Flutter configuration or repository fixtures.

The provider-neutral contract must permit replacement by another hosting target later.

## 22. Reference-Commerce Proof

The reference client proves one complete production release lifecycle.

Required proof sequence:

```text
H.1 reference-commerce candidate
→ staging artifact deployment
→ staging Supabase integration
→ H.2A gates
→ hardening report
→ exact candidate freeze
→ explicit synthetic human G authorization fixture for that exact H.2 candidate
→ authorized Cloudflare Pages production deployment
→ production smoke
→ telemetry health
→ ReleaseRecord
```

The H.1/G historical authorization fixture must not be reused if SHA/artifact/migration/release-config identity changed.

A new exact-candidate authorization fixture is required for the reference proof.

## 23. Evidence Artifacts

Recommended conceptual artifacts:

```text
client-projects/reference-commerce/
  production/
    hardening/
      hardening-policy.yaml
      performance-budget.yaml
      analytics-taxonomy.yaml
      accessibility-policy.yaml
      security-policy.yaml
    evidence/
      h2-hardening-report.json
      staging-smoke-report.json
      production-smoke-report.json
      telemetry-health-report.json
      release-record.json
      recovery-report.json   # only when exercised
```

Schema-backed evidence should be preferred for machine-checked release gates.

Provider-native output may be referenced but must not become the sole canonical release record.

## 24. Repository Boundaries

Conceptual implementation boundaries:

```text
packages/
  agency_operations_core/
    observability/
    analytics/
    hardening/
    release/
    deployment/

  agency_sentry_adapter/
  agency_ga4_adapter/
  agency_cloudflare_adapter/

tooling/
  hardening/
    policy validation
    candidate identity
    hardening report
    smoke orchestration
    telemetry health

  release/
    release record
    release coordinator
    recovery coordinator
    deployment evidence

client-projects/reference-commerce/
  production/
    hardening/
    evidence/

.github/workflows/
  candidate-build
  staging-deploy
  hardening
  production-release
```

Exact filenames/package grouping may be refined in the implementation plan, but the authority and dependency boundaries in this spec must remain intact.

## 25. Workflow Integration

The existing productionization workflow must evolve from H.1-only "production-capable" completion to an explicit H.2 release lifecycle without destroying H.1 evidence.

Recommended stage semantics:

- H.1 foundation evidence remains immutable input.
- H.2A creates hardening/staging evidence.
- G authorization remains an external human release-permission gate.
- H.2B creates immutable release evidence.

If the existing stage-08 runtime cannot represent this safely, the implementation plan may introduce a dedicated release stage/contract rather than overloading stage 08. The workflow-state authority must remain with `tooling.workflow.runner`.

No workflow implementation may auto-create authorization.

## 26. Error and Failure Behavior

Release and hardening failures must be normalized into stable failure classes such as:

- candidate_mismatch
- authorization_missing
- authorization_invalid
- artifact_missing
- artifact_digest_mismatch
- migration_validation_failed
- migration_apply_failed
- staging_smoke_failed
- security_gate_failed
- accessibility_gate_failed
- performance_gate_failed
- observability_gate_failed
- analytics_gate_failed
- deployment_failed
- production_smoke_failed
- telemetry_health_failed
- rollback_failed
- recovery_required

Provider-specific exceptions remain adapter/detail evidence and must not become the core release contract.

## 27. H.2 Completion Contract

H.2 is complete only when the reference proof demonstrates:

```text
H.1 production-capable application
        +
H.2A hardening gates pass
        +
staging deployment/journey proof
        +
exact candidate frozen
        +
valid G ProductionAuthorization
        +
exact artifact deployed to production
        +
authorized migration set applied
        +
production smoke passes
        +
telemetry health passes
        +
ReleaseRecord finalized
        ↓
end-to-end production-capable agency platform
```

A failed/rolled-back reference release may prove recovery behavior, but it does not satisfy the healthy-release completion proof by itself.

## 28. Acceptance Criteria

H.2 is accepted only if all of the following hold:

1. H.2 is one milestone with H.2A hardening and H.2B authorized release.
2. Reference production target is Flutter Web + Supabase.
3. Android/iOS store release remains deferred.
4. Observability is provider-neutral with Sentry as reference adapter.
5. Analytics is provider-neutral with GA4 as reference adapter.
6. Deployment is provider-neutral with Cloudflare Pages as reference adapter.
7. GitHub Actions is executor only and cannot grant release authority.
8. Staging deployment occurs before G production authorization.
9. H.2A hardening runs against the staged exact candidate.
10. Blocking and advisory findings are distinct.
11. Blocking hardening failures prevent candidate authorization.
12. Candidate identity binds source SHA, artifact digest, build version, environment, migration set, configuration identity, and authority/evidence refs.
13. G authorization is required for the exact production candidate.
14. Production release invokes the existing G release gate.
15. Production deployment performs no rebuild after authorization.
16. Artifact digest is verified before production deployment.
17. Production applies only the authorized migration set.
18. Migration readiness includes staging apply and recovery treatment.
19. Blind database rollback is prohibited.
20. Previous-known-good application rollback is supported through governed recovery.
21. A newly fixed artifact is treated as a new candidate, not rollback.
22. B2C staging critical journey is validated.
23. B2B staging critical journey is validated.
24. Auth/session and permission behavior is validated in staging.
25. Sentry/reference observability release tagging and error capture are validated.
26. GA4/reference analytics governed critical events are validated.
27. Accessibility has blocking critical-journey gates.
28. Performance has versioned repository-owned budgets.
29. Security has blocking release gates.
30. Normal PR/build validation does not require production credentials.
31. Cloudflare/Sentry/GA4/Supabase privileged credentials remain CI/server secrets.
32. Production smoke is intentionally low-risk and side-effect controlled.
33. Post-release telemetry health is a deterministic bounded gate.
34. Every production attempt creates an immutable ReleaseRecord.
35. ReleaseRecord binds approval, H.1 evidence, exact candidate, H.2A evidence, G authorization, deployment, and health result.
36. Healthy, degraded, and failed release outcomes are represented explicitly.
37. Degraded releases retain incident/advisory evidence.
38. Failed releases preserve failure and recovery evidence.
39. H.2 never creates or silently modifies `ProductionAuthorization`.
40. H.2 never silently redesigns the approved experience.
41. Historical H.1/G authorization fixtures cannot authorize a changed H.2 candidate.
42. Reference proof requires a new explicit synthetic human authorization fixture for the exact H.2 candidate.
43. Existing C/D/E/F/G/H.1 authorities remain unchanged.
44. Provider SDKs do not leak into provider-neutral core contracts.
45. Workflow-state authority remains with the existing workflow runtime.
46. H.2 completion proves one healthy end-to-end reference production release.

## 29. Resulting Roadmap

After H.2:

```text
A–E  platform/design/review/QA/workflow foundation    complete
F    reference client                                 complete
G    exact-candidate production authorization         complete
H.1  production application foundation                complete
H.2  hardening + authorized production release        complete
```

Remaining work is no longer foundational production architecture. It becomes targeted extensions such as:

- real client-specific vendor integrations
- Android/iOS store release automation
- multi-client production operations
- broader incident/operations automation
- promotion of proven client-specific integrations into reusable agency adapters
