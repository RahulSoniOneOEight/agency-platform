# Build Prototype

## PURPOSE
Turn validated Experience Directions into a runnable A/B/C prototype using the shared Flutter platform.

## READ
- `client-projects/<client>/client-profile.yaml`
- validated `client-projects/<client>/directions/`
- `design-contract/`
- `packages/agency_flutter_ui/`
- `apps/prototype_app/`
- selected resources where applicable

## PROCESS
1. Validate direction A/B/C structure and strategic distinctiveness.
2. Run the prototype composer; do not copy the shared Flutter runtime into the client folder.
3. Generate deterministic fixture data appropriate to the client industry.
4. Write the client prototype manifest referencing `apps/prototype_app`.
5. Confirm the shared Flutter app analyzes, tests, and builds for web.
6. Use `?client=<id>&direction=a|b|c` or the internal selector to review each direction.

## WRITE
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/fixtures/demo.yaml`
- `client-projects/<client>/prototype/qa/screenshot-manifest.yaml`

## VALIDATE
- Prototype manifest exists and references the shared runtime.
- A/B/C directions resolve only known patterns/components.
- Flutter prototype app builds successfully.

## DO NOT
- Do not create three separate Flutter apps for A/B/C.
- Do not copy shared Flutter source into the client workspace.
- Do not bypass validated Experience Directions.
- Do not add production backend integrations in this stage.

## NEXT
`06-visual-qa.md`
