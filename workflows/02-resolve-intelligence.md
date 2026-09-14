# Resolve Intelligence

Detailed operating stages: **3. Resolve reusable intelligence** + **4. Identify capability / UX gaps**.

## PURPOSE
Resolve the shared Design Intelligence and presets relevant to the client, then classify each requested capability as reuse, extension, variant, new, or client-only.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- `presets/business-model/`
- `presets/industry/`
- `presets/use-case/`
- `design-contract/`
- `experience-patterns/`
- `DESIGN_SYSTEM.md`

## PROCESS
1. Resolve business-model, industry, and use-case presets.
2. Search Design Contract components, patterns, journeys, variants, and themes by metadata fit.
3. Record relevant reusable intelligence and candidate experience patterns.
4. Compare client requirements against existing capabilities.
5. Classify every meaningful capability as `reuse`, `extend`, `variant`, `new`, or `client-only`.
6. Record only genuinely unresolved/new requirements in the gap artifact.
7. Treat presets and archetypes as hypotheses, not forced outputs.

## WRITE
- `client-projects/<client>/derived/resolved-presets.yaml`
- `client-projects/<client>/derived/intelligence-map.yaml`
- `client-projects/<client>/derived/capability-map.yaml`
- `client-projects/<client>/derived/gaps.yaml`

## VALIDATE
- All referenced presets, components, patterns, journeys, variants, and themes resolve.
- Capability classifications use the approved statuses.
- Gaps are traceable to client requirements and are not duplicates of reusable agency capabilities.

## DO NOT
- Do not duplicate components inside presets.
- Do not force Discovery/Search/Trade as final directions.
- Do not copy external reference code into the client project.
- Do not promote client-only requirements into shared agency intelligence during this stage.

## NEXT
`03-resource-research.md`
