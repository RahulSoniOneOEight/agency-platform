# Client Intake

## PURPOSE
Convert raw client requirements into the standard brief, client profile, and initial workflow state.

## READ
- User/client requirements
- `templates/client-profile.yaml`
- `client-projects/schema/client-profile.schema.json`

## PROCESS
1. Capture goals, business model, industry, personas, jobs, platforms, constraints, brand, and references.
2. Separate explicit facts from inferred classifications.
3. Populate the client profile without inventing unsupported client facts.

## WRITE
- `client-projects/<client>/brief.md`
- `client-projects/<client>/client-profile.yaml`
- `client-projects/<client>/workflow-state.yaml`

## VALIDATE
Client profile must validate against the Knowledge Platform client-profile schema before marking this stage complete.

## DO NOT
- Do not start UI implementation.
- Do not select Experience Directions yet.
- Do not mix shared agency knowledge into client-provided reference facts.

## NEXT
`02-resolve-intelligence.md`
