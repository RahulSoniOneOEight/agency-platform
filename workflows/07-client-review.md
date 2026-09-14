# Client Review

Detailed operating stages: **16. Client review** + **17. Select / mix directions**.

## PURPOSE
Convert client evaluation of A/B/C working prototypes into one explicit, validated approved-experience contract.

## READ
- `client-projects/<client>/directions/`
- `client-projects/<client>/directions/comparison.yaml`
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/screenshots/`
- `client-projects/<client>/prototype/qa/visual-findings.yaml`
- client feedback
- `templates/approved-experience.yaml`

## PROCESS
1. Confirm visual QA has no unresolved critical findings.
2. Present rationale, target user/job, strengths, trade-offs, and working prototype for each direction.
3. Capture structured client feedback, including requested refinements.
4. Capture either one selected direction or a coherent mix such as A home + B search + C trade.
5. Record the base direction and every mixed section source explicitly.
6. Resolve navigation/journey conflicts before freezing the approved experience.
7. Capture client-specific exceptions without promoting them to the shared system automatically.

## WRITE
- `client-projects/<client>/workflow-state.yaml`
- corrected direction/comparison artifacts when feedback materially changes an alternative
- `client-projects/<client>/approved-experience.yaml`

## VALIDATE
- Approval references only direction A/B/C artifacts that exist.
- Mixed selections include `source_direction` for every section.
- The resulting experience is internally coherent.
- The approved-experience validator passes before the workflow advances.

## DO NOT
- Do not treat meeting notes as the production contract.
- Do not productionize unapproved alternatives.
- Do not merge incompatible fragments without resolving navigation/journey consistency.

## NEXT
`08-productionize.md`
