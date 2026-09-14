# Visual QA

## PURPOSE
Run technical and visual quality checks on rendered prototypes and record structured findings.

## READ
- Rendered prototype
- `VISUAL_QA.md`
- direction config and selected resources

## PROCESS
1. Confirm Milestone B rendering/screenshot tooling exists.
2. If absent, return a structured blocked result and stop.
3. When available, inspect required viewports, states, hierarchy, spacing, clipping, density, imagery, responsiveness, accessibility, and broken interactions.
4. Map findings back to component, pattern, token, resource, or direction config.

## WRITE
- `client-projects/<client>/qa/findings.yaml`
- resolution status for each finding

## VALIDATE
Required technical and visual checks must be complete before client review.

## DO NOT
- Do not declare UI complete from static analysis alone.
- Do not hide unresolved high-severity findings.

## NEXT
`07-client-review.md`
