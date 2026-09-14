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

The detailed client-delivery model is `docs/operating-flow.md`. It contains 20 consulting/delivery stages; the runtime intentionally groups them into eight executable workflow files.

## Standard client run

A typical user command is:

> Start a new project for ABC Furniture using the standard agency workflow.

OpenCode should:

1. Read `AGENTS.md` and `docs/operating-flow.md`.
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

Creates:

```text
client-projects/abc-furniture/
├── brief.md
├── workflow-state.yaml
├── input/
│   ├── client-input.yaml
│   ├── brand/.gitkeep
│   ├── references/.gitkeep
│   ├── assets/.gitkeep
│   └── source-documents/.gitkeep
├── derived/
│   ├── client-profile.yaml
│   ├── resolved-presets.yaml
│   ├── intelligence-map.yaml
│   ├── capability-map.yaml
│   ├── gaps.yaml
│   └── resource-requirements.yaml
├── resources/.gitkeep
└── directions/.gitkeep
```

The initializer refuses to overwrite an existing client and does not create legacy flat `client-profile.yaml` / `resolved-intelligence.yaml` files.

## Information separation

- `input/` = supplied/confirmed client facts and attachments.
- `derived/` = agency/OpenCode interpretation, classification, reuse/gap analysis, and structured resource needs.
- `resources/`, `directions/`, `prototype/`, and `approved-experience.yaml` = project decisions and executable/review artifacts.

Legacy root-level client profile/intelligence files are supported only as read fallback during migration; new writes use canonical paths.

## Stored runtime stages

1. `01-client-intake.md` → detailed stages 1–2
2. `02-resolve-intelligence.md` → detailed stages 3–4
3. `03-resource-research.md` → detailed stages 5–6
4. `04-generate-directions.md` → detailed stages 7–8
5. `05-build-prototype.md` → detailed stages 9–13
6. `06-visual-qa.md` → detailed stages 14–15
7. `07-client-review.md` → detailed stages 16–17
8. `08-productionize.md` → detailed stages 18–20

Every stage declares `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, and `NEXT`.

## State and artifact rules

- State alone is not proof that a stage completed; required artifacts must exist.
- Client intake completion requires canonical client input and derived profile (legacy read fallback is migration-only).
- Intelligence resolution completion requires resolved presets, intelligence map, capability map, and gaps.
- `resource-research` is optional but can only be skipped with a recorded reason; when completed it requires resource requirements plus resource selection.
- Directions require A/B/C plus comparison before prototype routing.
- Build-prototype requires the shared Prototype Platform plus generated prototype artifacts.
- Visual QA requires screenshot and findings contracts with no unresolved critical findings.
- Productionization requires a valid `approved-experience.yaml`.

## Validation

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_client_information_architecture tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

## Current boundary

The runtime and Prototype Platform cover client intake through approved experience. `08-productionize.md` documents stages 18–20, but full production backend/integration/release infrastructure remains a later milestone and must not be claimed as installed until implemented.