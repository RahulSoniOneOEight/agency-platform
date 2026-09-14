# Productionize

Detailed operating stages: **18. Promote reusable learnings** + **19. Productionize** + **20. Final QA & release**.

## PURPOSE
Decide what proven client work should improve the shared agency system, then harden the approved client experience into production software and complete final release verification.

## READ
- `client-projects/<client>/approved-experience.yaml`
- client-specific capability/gap/resource artifacts
- shared Design Contract, presets, experience patterns, and resource registry
- production requirements
- app/backend integration contracts
- applicable security, accessibility, analytics, performance, CI, and release requirements

## PROCESS
1. Review new client-proven components, patterns, resources, and workflow knowledge for reuse value.
2. Promote only generalized, proven learnings into `design-contract/`, `presets/`, `experience-patterns/`, or `resources/registry/`; keep one-off exceptions client-only.
3. Verify `approved-experience.yaml` exists and validates.
4. Replace prototype shortcuts with production state, APIs, auth, errors, analytics, accessibility, performance, security, and environment configuration.
5. Add ERP, commerce, CRM, payments, shipping, WhatsApp, Supabase/Postgres, or n8n only when required by the approved production scope.
6. Run functional, integration, visual, device/responsive, performance, accessibility, security, and release checks required by the production scope.
7. Produce the release candidate and obtain required client/release approval.

## WRITE
- justified updates to shared agency intelligence/registries
- production application and integration changes
- tests and environment configuration
- CI/release artifacts and documentation/status updates

## VALIDATE
- Reusable promotions are generalized and do not leak client-only behavior into the shared system.
- Productionization cannot begin until `approved-experience.yaml` exists and validates.
- Final release requires the production milestone's functional/integration/visual/performance/release gates to pass.

## DO NOT
- Do not redesign the approved experience silently.
- Do not introduce integrations unrelated to the approved scope.
- Do not promote every client-specific customization into the shared system.
- Do not claim production/release capabilities exist until their dedicated implementation milestone has installed them.

## NEXT
Production release / post-release operating workflow defined by later delivery milestones.
