# Resolve Intelligence

## PURPOSE
Resolve the shared Design Intelligence and reusable presets that should inform the client project, including likely resource needs and gaps.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
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
5. Derive likely high-impact resource needs and gaps into `derived/resource-requirements.yaml`; do not call external providers in this stage.
6. Mark each requirement with impact and sourcing mode: authoritative, prefer_client, comparative, or discovery.

## WRITE
- `client-projects/<client>/resolved-intelligence.yaml`
- `client-projects/<client>/derived/resource-requirements.yaml` when resource needs exist

## VALIDATE
All referenced presets, components, patterns, journeys, and resource requirement roles must resolve without invalid references.

## DO NOT
- Do not duplicate components inside presets.
- Do not force Discovery/Search/Trade as final directions.
- Do not copy external reference code into the client project.
- Do not perform Pexels/provider search in this stage.

## NEXT
`03-resource-research.md`

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/02-resolve-intelligence.yaml`.
