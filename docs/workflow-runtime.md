# Workflow Runtime

The Workflow Runtime turns the agency process into repository-driven stage contracts that OpenCode can execute repeatably.

## Mental model

```text
GitHub = rules + knowledge + workflow instructions + client state + outputs
OpenCode = executor/orchestrator
workflow-state.yaml = checkpoint
workflows/*.md = stored stage prompts/contracts
validators = guardrails
```

## Standard client run

A typical user command is:

> Start a new project for ABC Furniture using the standard agency workflow.

OpenCode should:

1. Read `AGENTS.md`.
2. Initialize the client workspace if it does not exist.
3. Read `client-projects/<client>/workflow-state.yaml`.
4. Ask the runtime router for the next legal stage.
5. Open only the matching numbered workflow plus its declared inputs.
6. Execute that stage.
7. Validate its outputs.
8. Update workflow state only after the gate is satisfied.
9. Commit/prepare the GitHub changes for review.

## Initialize a client

```bash
python -m tooling.workflow.initialize_client abc-furniture --name "ABC Furniture"
```

Creates the canonical client workspace:

```text
client-projects/abc-furniture/
  input/
    client-input.yaml
    ... optional module/collection templates ...
  derived/
    client-profile.yaml
  resources/
  directions/
  prototype/
  workflow-state.yaml
```

The initializer refuses to overwrite an existing client.

## Input / derived boundary

```text
input/   = client/source truth
derived/ = agency/OpenCode interpretation
```

`input/client-input.yaml` is the only mandatory structured client-input file. Detailed module
files are optional at initialization and become required only when referenced from
`client-input.yaml` or explicitly required by a workflow capability. OpenCode may normalize,
classify, and infer into `derived/`, but must never silently rewrite an inference back into
`input/` as if the client supplied it.

## Stored stages

1. `01-client-intake.md`
2. `02-resolve-intelligence.md`
3. `03-resource-research.md`
4. `04-generate-directions.md`
5. `05-build-prototype.md`
6. `06-visual-qa.md`
7. `07-client-review.md`
8. `08-productionize.md`

Every stage declares `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, and `NEXT`.

## State rules

- State alone is not proof that a stage completed; required artifacts must exist.
- `resource-research` is optional but can only be skipped with a recorded reason.
- Directions require A/B/C plus comparison before prototype routing.
- The prototype stage returns `prototype-platform-not-installed` until Milestone B is installed.
- Productionization requires `approved-experience.yaml`.

## Validation

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_client_input_contract tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

## Current boundary

This runtime orchestrates the agency process but does not itself implement Flutter prototypes, automated screenshots, AI visual QA, production backends, or deployment. Those remain later milestones.
