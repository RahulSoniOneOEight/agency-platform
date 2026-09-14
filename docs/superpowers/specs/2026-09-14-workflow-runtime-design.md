# Workflow Runtime Layer — Design Specification

## Goal

Add a repository-driven workflow runtime so OpenCode can move a client project through the agency process using stored stage instructions, structured templates, explicit workflow state, and validation instead of relying on ad-hoc prompts.

## Architecture

The runtime has five parts:

1. Master routing rules in `AGENTS.md`.
2. Stage workflows in `workflows/`.
3. Canonical templates in `templates/`.
4. Per-client `workflow-state.yaml`.
5. Runtime tooling in `tooling/workflow/` for initialization, routing, state transitions, and validation.

OpenCode remains the executor. GitHub remains the source of truth. The runtime consumes Milestone A Knowledge Platform and explicitly blocks prototype and visual-QA work until Milestone B exists.

## Repository Structure

```text
workflows/
  01-client-intake.md
  02-resolve-intelligence.md
  03-resource-research.md
  04-generate-directions.md
  05-build-prototype.md
  06-visual-qa.md
  07-client-review.md
  08-productionize.md

templates/
  client-profile.yaml
  direction.yaml
  direction-comparison.yaml
  workflow-state.yaml
  approved-experience.yaml

tooling/workflow/
  initialize_client.py
  state.py
  router.py
  validate_workflow.py
```

## Workflow Stages

1. `client-intake`
2. `resolve-intelligence`
3. `resource-research` (optional, explicit skip with reason)
4. `generate-directions`
5. `build-prototype`
6. `visual-qa`
7. `client-review`
8. `productionize`

### Client Intake
Reads client requirements and `templates/client-profile.yaml`; writes `brief.md`, `client-profile.yaml`, and initial `workflow-state.yaml`. Gate: client profile validates against the Knowledge Platform schema.

### Resolve Intelligence
Reads client profile, presets, design contract, and experience patterns; writes `resolved-intelligence.yaml`. Gate: business-model, industry, and use-case presets resolve without invalid references.

### Resource Research
Reads client profile, resolved intelligence, references, resource registry, and source-routing policy; writes `resources/selection.yaml` plus provenance entries. May be skipped only with an explicit reason.

### Generate Directions
Reads client profile, resolved intelligence, resource context, experience patterns, and design indexes. Generates 6–10 candidates, scores them, enforces strategic diversity, and writes A/B/C plus comparison. Discovery/Search/Trade are candidate archetypes only, never forced outputs.

### Build Prototype
Reads validated directions and later Flutter shared package/starter. Until Milestone B exists, returns `blocked: prototype-platform-not-installed` instead of inventing another build path.

### Visual QA
Reads rendered prototype and `VISUAL_QA.md`; writes structured QA findings. Until Milestone B visual tooling exists, this stage remains blocked.

### Client Review
Reads A/B/C, comparison, prototypes, and client feedback; writes `approved-experience.yaml`, supporting select/mix/refine. Gate: all references resolve.

### Productionize
Reads approved experience and production requirements. Gate: cannot begin before valid `approved-experience.yaml` exists.

## Workflow State Contract

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

Statuses: `not_started`, `in_progress`, `blocked`, `complete`.

## Router Rules

- Never infer completion from prose alone; required artifacts must exist and validate.
- Never skip a mandatory gate.
- Optional stages may be skipped only with a reason.
- Do not start prototype without valid A/B/C direction artifacts.
- Do not start productionize without valid approved experience.
- When a required future subsystem is absent, return a structured blocked reason.

## Workflow File Contract

Every `workflows/*.md` must contain:

```text
PURPOSE
READ
PROCESS
WRITE
VALIDATE
DO NOT
NEXT
```

## Client Initializer

`initialize_client.py` accepts `client_id` and optional display name, creates standard client skeleton plus initial workflow state, and refuses to overwrite an existing client directory.

## Validation

`validate_workflow.py` validates workflow sections, templates, state shape, completed-stage artifacts, optional skip reasons, legal transitions, approved-experience gate, and Milestone-B blocking.

## Testing

Cover initialization, overwrite refusal, initial routing, client-profile advancement, missing-artifact blocking, explicit resource skip, directions-to-prototype transition, prototype block, productionize gate, and malformed workflow files. Existing Knowledge Platform and Flutter CI must remain green.

## OpenCode Operating Model

A user can say: `Start a new project for ABC Furniture using the standard agency workflow.` OpenCode reads `AGENTS.md`, initializes/reads the client workspace, asks the router for the next legal stage, reads the corresponding workflow file, loads only named inputs, executes, validates, updates state, and writes results back to GitHub.

## Scope Boundaries

Included: workflows, templates, client initializer, state, router, transition validation, OpenCode routing instructions, CI validation.

Excluded: Flutter components, runnable prototype composer, screenshot/AI vision automation, backend integrations, production deployment.

## Success Criteria

The system can initialize a client, determine the next valid stage without a hand-written prompt, load stage-specific instructions, validate outputs, update state deterministically, prevent skipping, stop at unavailable future subsystems, and preserve decisions/state in GitHub.
