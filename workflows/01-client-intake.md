# Client Intake

## PURPOSE
Convert raw client requirements into the canonical source-truth layer (`input/`) and a normalized derived profile (`derived/`), preserving the boundary between client-provided facts and agency interpretation.

## READ
- User/client requirements and supplied source material
- `client-projects/<client>/input/client-input.yaml`
- referenced input modules under `client-projects/<client>/input/`
- `client-projects/schema/input/`
- `client-projects/schema/client-profile.schema.json`

## PROCESS
1. Capture client facts into `input/client-input.yaml` and referenced module files. Treat `input/` as immutable client/source truth.
2. Normalize and classify client wording into platform vocabulary in `derived/`; mark any agency inference explicitly.
3. Never edit `input/` merely to satisfy derivation, and never copy inferred values back into `input/`.
4. Record unresolved questions in `input/open-questions.yaml` with blocking flags; blocking questions prevent intake completion.

## WRITE
- `client-projects/<client>/input/client-input.yaml`
- referenced `client-projects/<client>/input/**` module files
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/workflow-state.yaml`

## VALIDATE
`input/client-input.yaml` and all referenced modules must validate against their schemas, no unresolved blocking open questions may remain, and `derived/client-profile.yaml` must exist before marking this stage complete.

## DO NOT
- Do not start UI implementation.
- Do not select Experience Directions yet.
- Do not rewrite agency inferences into `input/` as client-supplied facts.
- Do not store credentials/secrets in integration requirements.

## NEXT
`02-resolve-intelligence.md`

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/01-client-intake.yaml`.
