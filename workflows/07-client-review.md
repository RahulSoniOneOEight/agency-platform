# Client Review

## PURPOSE
Convert client evaluation of A/B/C working prototypes into one approved implementation contract.

## READ
- `client-projects/<client>/directions/`
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- direction comparison
- `client-projects/<client>/prototype/qa/visual-findings.yaml`
- client feedback
- `templates/approved-experience.yaml`

## PROCESS
1. Confirm visual QA has no unresolved critical findings.
2. Present rationale, target user/job, strengths, trade-offs, and working prototype for each direction.
3. Capture either one selected direction or a coherent mix of sections from A/B/C.
4. Record the base direction and every mixed section source explicitly.
5. Capture client-specific exceptions without promoting them to the shared system automatically.

## WRITE
- `client-projects/<client>/approved-experience.yaml`

## VALIDATE
- Approval references only direction A/B/C artifacts that exist.
- Mixed selections include `source_direction` for every section.
- The approved-experience validator passes before the workflow can advance.

## DO NOT
- Do not treat meeting notes as the production contract.
- Do not productionize unapproved alternatives.
- Do not merge incompatible fragments without resolving navigation/journey consistency.

## NEXT
`08-productionize.md`
