# Build Prototype

## PURPOSE
Turn validated Experience Directions into a runnable A/B/C prototype using the shared Flutter platform and normalized B.1C resources.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- validated `client-projects/<client>/directions/`
- `client-projects/<client>/resources/selection.yaml` when present
- `client-projects/<client>/resources/candidates.yaml` when present
- `client-projects/<client>/resources/provenance.yaml` when present
- `design-contract/`
- `packages/agency_flutter_ui/`
- `apps/prototype_app/`

## PROCESS
1. Validate direction A/B/C structure and strategic distinctiveness.
2. Validate B.1C resource artifacts when present; critical resources must resolve before the prototype is considered ready.
3. Run the prototype composer; do not copy the shared Flutter runtime into the client folder.
4. Generate deterministic fixture data appropriate to the client industry.
5. Write the client prototype manifest referencing `apps/prototype_app` and canonical resource bindings.
6. Generate the deterministic client runtime bundle at `apps/prototype_app/assets/generated/<client-id>.json`.
7. Confirm the shared Flutter app analyzes, tests, and builds for web.
8. Use `?client=<id>&direction=a|b|c` or the internal selector to review each direction.

## WRITE
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/fixtures/demo.yaml`
- `client-projects/<client>/prototype/qa/screenshot-manifest.yaml`
- `apps/prototype_app/assets/generated/<client-id>.json`

## VALIDATE
- Prototype manifest exists and references the shared runtime.
- A/B/C directions resolve only known patterns/components.
- Selected resource bindings use canonical IDs and resolve to known candidates.
- Generated runtime bundle exists, validates against the canonical contract, and matches a
  fresh projection of the strategic sources (repository validation fails on stale bundles).
- An explicit unknown client or direction shows a governed error and never falls back to Direction A.
- Flutter prototype app builds successfully.

## DO NOT
- Do not create three separate Flutter apps for A/B/C.
- Do not copy shared Flutter source into the client workspace.
- Do not bypass validated Experience Directions.
- Do not embed raw provider URLs as resource keys.
- Do not hand-edit generated runtime bundles or the generated Flutter asset; regenerate from source.
- Do not add production backend integrations in this stage.

## NEXT
`06-visual-qa.md`

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/05-build-prototype.yaml`.
