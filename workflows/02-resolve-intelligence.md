# Resolve Intelligence

## PURPOSE
Resolve the shared Design Intelligence and reusable presets that should inform the client project.

## READ
- `client-projects/<client>/client-profile.yaml`
- `presets/business-model/`
- `presets/industry/`
- `presets/use-case/`
- `design-contract/`
- `experience-patterns/`

## PROCESS
1. Resolve business-model, industry, and use-case presets.
2. Search design-contract components, patterns, and journeys by metadata fit.
3. Record conflicts and client-specific exceptions explicitly.
4. Treat presets and archetypes as hypotheses, not forced outputs.

## WRITE
- `client-projects/<client>/resolved-intelligence.yaml`

## VALIDATE
All referenced presets, components, patterns, and journeys must exist and resolve without invalid references.

## DO NOT
- Do not duplicate components inside presets.
- Do not force Discovery/Search/Trade as final directions.
- Do not copy external reference code into the client project.

## NEXT
`03-resource-research.md`
