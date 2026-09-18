# Productionize

## PURPOSE
Harden the approved client experience into production software and integrations without reopening the approved UX contract unnecessarily.

Completion of this stage is **production-capable** — a production-shaped application
candidate with provider-neutral ports, a reference Supabase adapter, deterministic
fake integrations, validated environment configuration, versioned migrations, and
production-path tests. Completion is **not** production-authorized and **not**
deployed: H.1 is production implementation only, and the release-permission gate
remains Milestone G's `ProductionAuthorization`.

## READ
- `client-projects/<client>/approved-experience.yaml`
- `docs/superpowers/specs/2026-09-18-milestone-h1-production-foundation-design.md`
- `docs/superpowers/plans/2026-09-18-milestone-h1-production-foundation-implementation.md`
- production requirements
- app/backend integration contracts
- applicable security, accessibility, analytics, and performance requirements

## PROCESS
1. Verify approved experience exists and validates.
2. Replace prototype shortcuts with production state, APIs, auth, errors, analytics, accessibility, performance, security, and environment configuration.
3. Add ERP, commerce, CRM, payments, shipping, WhatsApp, Supabase/Postgres, or n8n only when required by the approved production scope.
4. Keep reusable learnings separate from client-only exceptions.
5. Keep production data access and authentication behind provider-neutral ports; Supabase/Postgres and Supabase Auth are reference adapters, not platform authority.
6. Record the deterministic H.1 production-foundation evidence at `client-projects/<client>/production/evidence/h1-foundation-report.json`.

## WRITE
- Production application and integration changes
- `client-projects/<client>/production/config/<environment>.json` client-safe environment configs
- `supabase/migrations/<version>_<name>.sql` versioned migrations and deterministic seed data
- `client-projects/<client>/production/evidence/h1-foundation-report.json` H.1 foundation evidence
- release/QA artifacts required by the delivery pipeline

## VALIDATE
Productionization cannot begin until `approved-experience.yaml` exists and validates.
The stage-08 gate is named `production-foundation`. It verifies:

- `python -m tooling.production.validate_config <client_dir>` — client-safe dev/staging/production configs
- `python -m tooling.production.validate_migrations` — versioned migration classes
- `python -m tooling.production.report <client_dir>` — H.1 report freshness and identity
- production-app contract evidence (the integration-scenarios fixture and the production-path tests)

## DO NOT
- Do not redesign the approved experience silently.
- Do not introduce integrations unrelated to the approved scope.
- Do not create, rewrite, or substitute for a `ProductionAuthorization`; that is Milestone G's exact-release permission authority.
- Do not deploy production or write production deployment artifacts.
- Do not duplicate an approval, review, or visual-QA authority under `production/`.
- Do not commit privileged secrets (service-role key, vendor/webhook secrets, ERP/payment/WhatsApp credentials) to the app or its config.

## NEXT
Release / reusable-learning promotion workflow defined by later delivery milestones.

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/08-productionize.yaml`.
