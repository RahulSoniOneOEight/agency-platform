# Build Prototype

Detailed operating stages: **9. Prepare prototype manifest** + **10. Generate demo data** + **11. Build runnable prototype** + **12. Render prototype** + **13. Structural QA**.

## PURPOSE
Translate validated Experience Directions into executable prototype specifications, deterministic demo data, one shared Flutter runtime, rendered review routes, and a technically stable prototype.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- validated `client-projects/<client>/directions/`
- `client-projects/<client>/resources/selection.yaml` when present
- `design-contract/`
- `packages/agency_flutter_ui/`
- `apps/prototype_app/`
- `templates/prototype-manifest.yaml`

## PROCESS
1. Validate direction A/B/C structure and strategic distinctiveness.
2. Resolve exact direction/runtime configuration into the prototype manifest.
3. Generate deterministic industry-appropriate fixture data.
4. Run the prototype composer; do not copy the shared Flutter runtime into the client folder.
5. Build and run the shared Flutter prototype app using stable A/B/C routes.
6. Run analyzer/tests and check routing, state, missing resources, overflow/layout failures, and implementation-registry resolution.
7. Use `?client=<id>&direction=a|b|c` or the internal selector to review each direction.

## WRITE
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/fixtures/demo.yaml`
- build/runtime output from the shared `apps/prototype_app`
- `client-projects/<client>/prototype/qa/screenshot-manifest.yaml`
- technical findings/config/code fixes where structural QA identifies issues

## VALIDATE
- Prototype manifest exists and references the shared runtime.
- A/B/C directions resolve only known patterns/components.
- Deterministic fixtures exist.
- Flutter analyze/tests pass and the prototype app builds successfully.
- Stable rendered routes are available for visual QA.

## DO NOT
- Do not create three separate Flutter apps for A/B/C.
- Do not copy shared Flutter source into the client workspace.
- Do not bypass validated Experience Directions.
- Do not add production backend integrations in this stage.

## NEXT
`06-visual-qa.md`
