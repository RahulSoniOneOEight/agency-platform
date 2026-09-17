# Productionize

## PURPOSE
Harden the approved client experience into production software and integrations without reopening the approved UX contract unnecessarily.

## READ
- `client-projects/<client>/approved-experience.yaml`
- production requirements
- app/backend integration contracts
- applicable security, accessibility, analytics, and performance requirements

## PROCESS
1. Verify approved experience exists and validates.
2. Replace prototype shortcuts with production state, APIs, auth, errors, analytics, accessibility, performance, security, and environment configuration.
3. Add ERP, commerce, CRM, payments, shipping, WhatsApp, Supabase/Postgres, or n8n only when required by the approved production scope.
4. Keep reusable learnings separate from client-only exceptions.

## WRITE
- Production application and integration changes
- release/QA artifacts required by the delivery pipeline

## VALIDATE
Productionization cannot begin until `approved-experience.yaml` exists and validates.

## DO NOT
- Do not redesign the approved experience silently.
- Do not introduce integrations unrelated to the approved scope.

## NEXT
Release / reusable-learning promotion workflow defined by later delivery milestones.

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/08-productionize.yaml`.
