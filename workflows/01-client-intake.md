# Client Intake

Detailed operating stages: **1. Client intake** + **2. Client profile derivation**.

## PURPOSE
Capture client-supplied facts separately from OpenCode-derived classification, then create the normalized client profile used by the rest of the platform.

## READ
- Client requirements, attachments, references, assets, constraints, and brand material
- `templates/client-input.yaml`
- `templates/client-profile.yaml`
- `client-projects/schema/client-profile.schema.json`

## PROCESS
1. Record supplied/confirmed facts in `input/client-input.yaml`; place attachments in the matching `input/` subfolders.
2. Do not add OpenCode inference to the input contract.
3. Derive business model, industry, use cases, platforms, personas, jobs, capabilities, objectives, and constraints into `derived/client-profile.yaml`.
4. Preserve uncertainty explicitly rather than inventing unsupported facts.

## WRITE
- `client-projects/<client>/brief.md` when a human-readable note is useful
- `client-projects/<client>/input/client-input.yaml`
- `client-projects/<client>/input/brand/`
- `client-projects/<client>/input/references/`
- `client-projects/<client>/input/assets/`
- `client-projects/<client>/input/source-documents/`
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/workflow-state.yaml`

## VALIDATE
- Client input contains only supplied/confirmed facts.
- Derived client profile validates against the Knowledge Platform client-profile schema.
- Both canonical artifacts exist before this workflow is marked complete.

## DO NOT
- Do not start UI implementation.
- Do not select Experience Directions yet.
- Do not store inferred classification inside `input/client-input.yaml`.
- Do not mix shared agency knowledge into client-provided reference facts.

## NEXT
`02-resolve-intelligence.md`
