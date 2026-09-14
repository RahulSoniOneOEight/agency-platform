# Workflow Runtime Layer — Design Specification

## Goal

Add a repository-driven workflow runtime so OpenCode can move a client project through the agency process using stored stage instructions, structured templates, explicit workflow state, and validation instead of relying on ad-hoc prompts.

## Context

Milestone A provides the Knowledge Platform: Design Intelligence, Resource Intelligence, presets, experience patterns, client-profile contracts, and the Experience Direction Engine. The missing layer is the repeatable operating mechanism that tells OpenCode which stage to run, what files to read, what files to write, and which gates must be satisfied before moving forward.

This runtime sits between the Knowledge Platform and the future Flutter Prototype Platform.

## Architecture

The runtime has five parts:

1. **Master routing rules in `AGENTS.md`** — identify the standard client workflow and mandatory gates.
2. **Stage workflows in `workflows/`** — concise OpenCode instructions for each lifecycle stage.
3. **Templates in `templates/`** — canonical structures for generated client artifacts.
4. **Per-client workflow state** — records the current stage, completed stages, pending stages, and blocked reasons.
5. **Runtime tooling + validation** — initializes client workspaces, validates stage transitions, and reports the next allowed workflow.

OpenCode remains the execution engine. GitHub remains the source of truth.

## Repository Structure

```text
agency-platform/
├── AGENTS.md
├── workflows/
│   ├── 01-client-intake.md
│   ├── 02-resolve-intelligence.md
│   ├── 03-resource-research.md
│   ├── 04-generate-directions.md
│   ├── 05-build-prototype.md
│   ├── 06-visual-qa.md
│   ├── 07-client-review.md
│   └── 08-productionize.md
├── templates/
│   ├── client-profile.yaml
│   ├── direction.yaml
│   ├── direction-comparison.yaml
│   ├── workflow-state.yaml
│   └── approved-experience.yaml
├── tooling/workflow/
│   ├── initialize_client.py
│   ├── state.py
│   ├── router.py
│   └── validate_workflow.py
└── client-projects/<client>/
    ├── brief.md
    ├── client-profile.yaml
    ├── references/
    ├── resources/
    ├── directions/
    ├── fixtures/
    ├── workflow-state.yaml
    ├── approved-experience.yaml
    └── app/
```

## Workflow Stages

### 1. Client Intake

Reads:
- user/client requirements
- `templates/client-profile.yaml`

Writes:
- `client-projects/<client>/brief.md`
- `client-projects/<client>/client-profile.yaml`
- initial `workflow-state.yaml`

Gate:
- client profile validates against the Knowledge Platform client-profile schema.

### 2. Resolve Intelligence

Reads:
- client profile
- `presets/`
- `design-contract/`
- `experience-patterns/`

Writes:
- `client-projects/<client>/resolved-intelligence.yaml`

Gate:
- business-model, industry, and use-case presets resolve without invalid references.

### 3. Resource Research

Reads:
- client profile
- resolved intelligence
- client references
- resource registry and source-routing policies

Writes:
- `client-projects/<client>/resources/selection.yaml`
- client-specific provenance entries where needed

Gate:
- selected resources must be approved or approved-with-rules and contain provenance.

Resource research may be skipped when no external resources are needed; the state must record `skipped` with a reason.

### 4. Generate Directions

Reads:
- client profile
- resolved intelligence
- resource context
- experience-pattern library
- design-contract indexes

Runs:
- candidate generation
- scoring
- strategic-diversity validation

Writes:
- `directions/direction-a.yaml`
- `directions/direction-b.yaml`
- `directions/direction-c.yaml`
- `directions/comparison.yaml`

Gate:
- directions validate structurally and represent materially different strategies.

### 5. Build Prototype

Reads:
- validated directions
- design contract
- Flutter shared package/starter when Milestone B exists

Writes:
- runnable prototype implementation
- demo fixture data

Gate:
- prototype builds successfully.

Until Milestone B exists, this workflow must report `blocked: prototype-platform-not-installed` rather than inventing a separate implementation path.

### 6. Visual QA

Reads:
- rendered prototype
- `VISUAL_QA.md`

Writes:
- structured QA findings and resolution status

Gate:
- required technical and visual checks are complete.

Until Milestone B visual tooling exists, this workflow may remain blocked.

### 7. Client Review

Reads:
- A/B/C directions
- runnable prototypes
- direction comparison
- client feedback

Writes:
- `approved-experience.yaml`

Supports:
- select one full direction
- mix components/journeys from multiple directions
- reject/refine selected areas

Gate:
- approved experience validates and all referenced components/patterns/resources exist.

### 8. Productionize

Reads:
- `approved-experience.yaml`
- production requirements

Writes:
- production application/integration changes

Gate:
- productionization cannot begin before `approved-experience.yaml` exists and validates.

## Workflow State Contract

`workflow-state.yaml` is the runtime checkpoint for each client.

Example:

```yaml
version: 1
client_id: acme
current_stage: generate-directions
status: in_progress
completed:
  - client-intake
  - resolve-intelligence
skipped:
  - stage: resource-research
    reason: no-external-resources-required
pending:
  - generate-directions
  - build-prototype
  - visual-qa
  - client-review
  - productionize
blocked: []
last_updated: 2026-09-14
```

Allowed status values:
- `not_started`
- `in_progress`
- `blocked`
- `complete`

The state file is machine-managed by tooling but human-readable and reviewable in GitHub.

## Router Behavior

The router determines the next legal stage from `workflow-state.yaml` and required artifacts.

Rules:

1. Never infer completion from prose alone; required artifacts must exist and validate.
2. Never skip a mandatory gate.
3. Optional stages may be explicitly skipped with a reason.
4. Do not start `build-prototype` without valid direction artifacts.
5. Do not start `client-review` without prototype/QA artifacts once Milestone B is active.
6. Do not start `productionize` without a valid approved experience.
7. If a future subsystem is not installed, return a structured blocked reason instead of fabricating work.

## OpenCode Operating Model

A user should be able to give a high-level command such as:

> Start a new project for ABC Furniture using the standard agency workflow.

OpenCode then:

1. reads `AGENTS.md`;
2. identifies the client workflow;
3. initializes or reads the client workspace;
4. asks the router for the current/next valid stage;
5. reads the corresponding `workflows/*.md` file;
6. loads only the files named by that workflow;
7. executes the stage;
8. validates outputs;
9. updates `workflow-state.yaml`;
10. commits or prepares the resulting changes for review.

The workflows are therefore stored prompts/instructions, but they are stage contracts rather than free-form prompt text.

## Workflow File Contract

Every `workflows/*.md` file must contain these sections:

```text
PURPOSE
READ
PROCESS
WRITE
VALIDATE
DO NOT
NEXT
```

This keeps stage prompts small and predictable.

Example `04-generate-directions.md` behavior:

- READ client profile, resolved presets, design indexes, experience patterns, resource context.
- PROCESS 6–10 candidates, score them, enforce diversity, choose best three.
- WRITE three direction files plus comparison.
- VALIDATE schema and distinctiveness.
- DO NOT force Discovery/Search/Trade or create theme-only alternatives.
- NEXT build prototype.

## Client Initializer

`tooling/workflow/initialize_client.py` creates only the standard client workspace skeleton and initial workflow state.

Input:

```text
client_id
optional display name
```

Creates:

```text
client-projects/<client>/
brief.md
client-profile.yaml
workflow-state.yaml
references/.gitkeep
resources/.gitkeep
directions/.gitkeep
fixtures/.gitkeep
```

It must refuse to overwrite an existing client directory unless an explicit future migration mode is introduced.

## Validation

`tooling/workflow/validate_workflow.py` validates:

- workflow files contain all required sections;
- templates are present;
- workflow-state schema is valid;
- completed stages have required artifacts;
- skipped optional stages contain reasons;
- illegal transitions are rejected;
- productionization is blocked without approved experience;
- prototype stages are blocked cleanly while Milestone B is absent.

## Testing

Test-first coverage should include:

1. new client initialization creates the exact expected structure;
2. existing clients cannot be overwritten;
3. initial next stage is `client-intake`;
4. validated client profile advances to `resolve-intelligence`;
5. missing required artifacts block transitions;
6. resource-research can be explicitly skipped with a reason;
7. valid A/B/C direction artifacts advance to prototype stage;
8. prototype stage returns the Milestone-B blocked reason while that subsystem is absent;
9. productionize cannot be selected without valid `approved-experience.yaml`;
10. workflow files missing required sections fail validation.

Existing Knowledge Platform and Flutter CI must remain green.

## CI

Extend Repository Validation to run:

```text
python -m unittest tooling.validation.test_workflow_runtime -v
python -m tooling.workflow.validate_workflow
```

The workflow-runtime validator should run in addition to, not replace, the Knowledge Platform validator.

## Scope Boundaries

Included:
- repository workflows
- templates
- client initializer
- workflow state
- stage router
- transition validation
- OpenCode routing instructions
- CI validation

Not included:
- Flutter shared component implementation
- runnable prototype composer
- screenshot automation
- AI vision automation
- backend/ERP/Supabase/n8n integrations
- production deployment pipelines

Those belong to later milestones.

## Success Criteria

The runtime is complete when a developer/OpenCode can:

1. initialize a new client workspace;
2. read the current state;
3. determine the next valid workflow without a hand-written prompt;
4. load the stage-specific instructions from GitHub;
5. produce and validate structured artifacts;
6. update workflow state deterministically;
7. prevent stage skipping;
8. stop cleanly at unavailable future subsystems;
9. preserve all decisions and run state in GitHub.

## Key Principle

```text
GitHub = rules + knowledge + workflow instructions + client state + outputs
OpenCode = executor/orchestrator
workflow-state.yaml = checkpoint
workflows/*.md = stored stage prompts
validators = guardrails
```
