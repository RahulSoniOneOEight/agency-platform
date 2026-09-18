# Milestone H.1 — Production Foundation Design

Status: Approved conversational design, written for user review before implementation planning.

Base: Milestone G merged to `main` at `a199f6554f85a5a0ee633e108e95b4f365693d83`.

## 1. Purpose

Milestone H.1 turns an approved Flutter experience into a production-capable application architecture without silently redesigning the approved UX and without weakening the existing approval, QA, workflow, or release-authorization authorities.

H.1 is the first of three productionization sub-milestones:

```text
H.1 Production Foundation
→ H.2 Operational Hardening
→ G ProductionAuthorization for the exact release candidate
→ H.3 Authorized Release
```

H.1 proves a generic agency production architecture using `reference-commerce` as the canonical proof client.

## 2. Scope

H.1 includes:

- provider-neutral production repository/service contracts
- provider-neutral authentication contract
- Supabase/Postgres reference persistence adapters
- Supabase Auth reference adapter
- environment/configuration model for dev, staging, and production
- strict secrets boundary
- deterministic fake adapters for ERP, payments, shipping, CRM, and WhatsApp
- normalized domain failure model
- migration framework and reference migrations
- production-path unit, contract, adapter, and end-to-end tests
- reference-commerce production proof for B2C and B2B journeys

H.1 does not include:

- real vendor ERP/payment/shipping/CRM/WhatsApp integrations
- production deployment
- app-store release automation
- observability/analytics/performance/accessibility/security hardening beyond the minimum production foundation
- creation of ProductionAuthorization
- client reapproval unless the approved experience contract changes

## 3. Authority Boundaries

Existing authorities remain unchanged:

```text
ApprovalSnapshot
    = client-approved experience authority

ReviewState / FeedbackRecord / RefinementBatch
    = review/refinement authorities

QAFinding
    = automated visual-QA authority

workflow-state.yaml
    = canonical workflow checkpoint

ProductionAuthorization
    = exact release permission authority

H.1
    = production implementation only
```

Rules:

1. H.1 must not create, rewrite, or substitute for ApprovalSnapshot.
2. H.1 must not create ProductionAuthorization.
3. Supabase schema is persistence implementation, not product/business authority.
4. Provider adapters are implementation mechanisms, not product authority.
5. Prototype fixtures remain demo/test inputs; they are not silently promoted into production data.
6. Any implementation change that alters the approved experience contract routes back through the existing review/approval workflow.
7. G remains the release-permission gate; H.1 may prepare a release candidate but cannot authorize release.

## 4. Architectural Approach

H.1 uses a hybrid ports-and-adapters architecture.

```text
Flutter Presentation
        ↓
Application / Use Cases
        ↓
Provider-neutral Ports
        ├─ CatalogRepository
        ├─ InventoryRepository
        ├─ CustomerRepository
        ├─ AccountRepository
        ├─ CartRepository
        ├─ OrderRepository
        ├─ QuoteRepository
        ├─ AuthService
        └─ Integration Ports
                ↓
Production Adapters
        ├─ Supabase/Postgres
        ├─ Supabase Auth
        ├─ Fake ERP
        ├─ Fake Payments
        ├─ Fake Shipping
        ├─ Fake CRM
        └─ Fake WhatsApp
```

The approved Flutter UI consumes application/use-case interfaces and must not know which backend provider implements them.

A future client can replace an adapter without changing the approved UI or use-case contract, for example:

```text
OrderRepository
→ SupabaseOrderRepository

or

OrderRepository
→ MedusaOrderRepository

or

OrderRepository
→ CustomApiOrderRepository
```

## 5. Reference-Commerce Production Model

The H.1 reference proof covers the existing approved F journeys and avoids broadening the product unnecessarily.

Core production entities:

- identity/user profile
- customer
- B2B account
- B2B account membership
- credit limit / available credit
- product
- variant
- category/collection
- inventory availability
- cart
- cart item
- order
- order item
- RFQ
- quotation

Reference flow:

```text
Auth/User
  ↓
Customer or B2B Account
  ↓
Catalog + Inventory
  ↓
Cart
  ↓
Order
  ↓
RFQ / Quote where applicable
```

## 6. Authentication and Permissions

Authentication remains provider-neutral.

Contract shape:

```text
AuthService
├─ signIn
├─ signOut
├─ refreshSession
├─ currentIdentity
└─ authStateChanges
        ↓
SupabaseAuthAdapter
```

Reference roles:

- `consumer`
- `b2b_buyer`
- `b2b_manager`
- `admin`

B2B users are linked to one or more business accounts through memberships. Business permissions are not embedded solely on the user record.

Security boundary:

```text
Flutter role visibility / guards
        = UX convenience

Backend / Supabase RLS policy
        = actual authorization enforcement
```

Client-side guards must never be treated as the real security boundary.

## 7. Environment and Configuration

H.1 defines exactly three runtime environments:

- `dev`
- `staging`
- `production`

Client-safe configuration may include:

- environment
- API base URL
- Supabase project URL
- Supabase anon/public key
- analytics-enabled flag
- feature flags
- integration modes
- application/build version

Privileged credentials are never committed and never placed in the Flutter client.

Privileged examples:

- Supabase service-role key
- payment secret
- ERP credentials
- shipping credentials
- WhatsApp server token
- webhook signing secret

Privileged integrations must remain behind a server-side boundary.

## 8. Integration Ports

H.1 defines production-shaped interfaces for external systems but ships deterministic fake adapters only.

Required reference integration ports:

- `PaymentPort`
- `ShippingPort`
- `ErpPort`
- `CrmPort`
- `WhatsAppPort`

Each fake adapter must support deterministic scenarios for:

- success
- validation failure
- timeout
- unavailable service
- retryable failure
- idempotent duplicate request where applicable

Vendor-specific exceptions must not leak into Flutter or application code.

## 9. Error Contract

Infrastructure/provider errors normalize into provider-neutral failures:

```text
Infrastructure exception
        ↓
Adapter
        ↓
DomainFailure
        ├─ unauthorized
        ├─ forbidden
        ├─ validation
        ├─ conflict
        ├─ unavailable
        ├─ timeout
        ├─ staleData
        └─ unknown
        ↓
Application / Use Case
        ↓
Approved UX state
```

A normalized failure records at minimum:

- stable code
- human-safe message/key
- retryable boolean
- operation
- optional correlation/request identifier
- provider detail only in safe diagnostic context, never as UI contract

Retries are permitted only when the operation is explicitly safe or idempotent.

Order/payment-like mutations must use idempotency keys rather than blind retry.

## 10. Supabase/Postgres Reference Adapter

The platform remains provider-neutral, but `reference-commerce` receives a working Supabase/Postgres adapter.

Reference responsibilities:

- catalog reads
- inventory reads
- customer/account profile persistence
- B2B account and credit visibility
- cart persistence
- order persistence
- RFQ and quotation persistence
- auth/session through Supabase Auth
- RLS-backed authorization policies
- deterministic seed/reference data
- versioned migrations

The adapter must conform to the same contracts used by fake/in-memory test adapters.

## 11. Migrations

Migrations are versioned, reviewable, repeatable, and reversible where practical.

Three change classes:

- additive — new table/column/index
- transformative — backfill/data reshape/relationship migration
- destructive — rename/drop/removal

Default strategy:

```text
expand
→ migrate
→ verify
→ contract
```

Destructive one-step migrations are avoided unless explicitly justified.

Migration flow:

```text
schema change
→ versioned migration
→ local/test validation
→ staging apply
→ data/backfill verification
→ production candidate
```

H.1 provides the migration framework and reference migrations but does not execute an authorized production deployment.

## 12. Testing Strategy

Four layers are mandatory.

### Unit tests

Cover:

- use cases
- validation
- domain failures
- role/permission logic
- idempotency behavior
- environment configuration validation

### Contract tests

Every adapter must satisfy shared behavior contracts for:

- repositories
- authentication
- external integration ports

The same contract suites should be reusable across fake, Supabase, and future provider adapters.

### Adapter tests

Cover:

- Supabase repository mapping
- Supabase Auth mapping
- RLS/security-policy expectations where testable
- fake ERP/payment/shipping/CRM/WhatsApp scenarios
- infrastructure-to-domain failure normalization

Normal CI must not require production credentials.

### End-to-end production-path tests

Reference-commerce must prove:

1. B2C sign-in → browse → cart → order
2. B2B sign-in → account/credit → RFQ → quote → order conversion
3. session expiration and refresh
4. insufficient B2B permission
5. inventory unavailable
6. stale cart
7. backend unavailable
8. retryable versus non-retryable failure
9. duplicate order/idempotency protection
10. environment misconfiguration
11. migration compatibility

## 13. CI and External-Service Policy

Normal repository CI:

- must run without production secrets
- must not require a live Supabase project
- must use deterministic fake/local adapters for ordinary contract tests
- must validate migrations and configuration structure
- must never create ProductionAuthorization
- must never deploy production

A separate staging integration path may run against an explicitly configured Supabase staging project when credentials are available.

Missing optional staging credentials should skip the live integration path rather than weaken normal deterministic validation.

## 14. H.1 Completion Contract

H.1 is complete when the repository contains and validates:

```text
approved Flutter experience
+
provider-neutral production interfaces
+
Supabase/Postgres reference implementation
+
provider-neutral auth + Supabase Auth adapter
+
deterministic external fake adapters
+
dev/staging/prod configuration
+
strict secret boundary
+
migration framework
+
production-path automated tests
↓
Production-capable application candidate
```

H.1 completion does not mean release-ready.

Next stages:

```text
H.1
↓
H.2 Operational Hardening
   observability
   analytics taxonomy
   performance budgets
   accessibility
   security gates
↓
G ProductionEligibility / ProductionAuthorization
   for the exact candidate
↓
H.3 Authorized Release
   staging
   release execution
   smoke verification
   rollback/manual halt
```

## 15. Proposed Repository Boundaries

Exact names may be refined during implementation planning, but responsibilities should remain separated.

```text
packages/
  agency_production_core/
    domain/
    application/
    ports/
    failures/
    config/

  agency_supabase_adapter/
    repositories/
    auth/
    mapping/

  agency_integration_adapters/
    fake/
      erp/
      payment/
      shipping/
      crm/
      whatsapp/

supabase/
  migrations/
  seed/

client-projects/reference-commerce/
  production/
    config/
    fixtures/
    evidence/

tooling/
  production/
    config validation
    migration validation
    integration contract validation
```

The final implementation plan may choose Dart package boundaries that better fit the existing monorepo, but it must preserve these conceptual boundaries.

## 16. Acceptance Criteria

H.1 is accepted only if all of the following hold:

1. Approved UX is not silently redesigned.
2. Production data access is behind provider-neutral ports.
3. Authentication is behind a provider-neutral contract.
4. Supabase/Postgres is only the reference adapter, not platform authority.
5. Supabase Auth is only the reference auth adapter.
6. Flutter does not contain privileged secrets.
7. Backend/RLS is the true authorization boundary.
8. B2B account membership is modeled separately from user identity.
9. Catalog/inventory/customer/account/cart/order/RFQ/quote flows are covered.
10. ERP/payment/shipping/CRM/WhatsApp remain integration ports with deterministic fake adapters.
11. Provider exceptions normalize to stable domain failures.
12. Retry behavior is explicit and safe.
13. Mutable transaction flows use idempotency where required.
14. Dev/staging/production configuration validates deterministically.
15. Normal CI requires no production credentials.
16. Supabase migrations are versioned and validated.
17. Additive/transformative/destructive migration semantics are documented.
18. B2C production-path E2E is covered.
19. B2B production-path E2E is covered.
20. Auth/session failure behavior is covered.
21. Permission failure behavior is covered.
22. Backend/inventory/stale-data failures are covered.
23. H.1 cannot create ProductionAuthorization.
24. H.1 performs no production deployment.
25. Existing C/D/E/F/G authorities remain unchanged.
26. H.2/H.3 concerns are not pulled prematurely into H.1.
