# Workflow Runtime Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repository-driven workflow runtime that lets OpenCode initialize client workspaces, determine the next legal stage, load stage-specific instructions, validate outputs, and persist workflow state in GitHub.

**Architecture:** `AGENTS.md` routes OpenCode into small stage contracts stored in `workflows/`. `workflow-state.yaml` is the machine-readable checkpoint, while `tooling/workflow/` owns initialization, routing, state transitions, and validation. The runtime consumes the existing Knowledge Platform and explicitly blocks prototype/visual-QA stages until Milestone B exists.

**Tech Stack:** Python 3.12, YAML, JSON Schema, GitHub Actions, existing Knowledge Platform contracts.

**Spec:** `docs/superpowers/specs/2026-09-14-workflow-runtime-design.md`

## Global Constraints

- GitHub is the source of truth.
- OpenCode is the executor/orchestrator.
- `workflow-state.yaml` is the canonical per-client checkpoint.
- `workflows/*.md` are stored stage contracts, not free-form prompt dumps.
- Never infer stage completion from prose alone; required artifacts must exist and validate.
- Optional stages may only be skipped explicitly with a reason.
- Prototype and visual-QA stages must return structured blocked reasons until Milestone B exists.
- Productionization cannot begin without a valid `approved-experience.yaml`.
- Existing Knowledge Platform and Flutter CI must remain green.

---

### Task 1: Define Workflow Runtime Contract Tests

**Files:**
- Create: `tooling/validation/test_workflow_runtime.py`
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- Consumes: existing Knowledge Platform client-profile validation.
- Produces: executable behavior contract for initializer, router, state transitions, workflow validation, and Milestone-B blocking.

- [ ] Write failing tests for exact client initialization structure, overwrite refusal, initial routing, profile completion routing, optional resource skip, directions-to-prototype transition, prototype blocked reason, productionize gate, and malformed workflow files.
- [ ] Run `python -m unittest tooling.validation.test_workflow_runtime -v` and confirm failure is caused by missing runtime modules.
- [ ] Extend CI to run runtime tests and `python -m tooling.workflow.validate_workflow` after Knowledge Platform validation.
- [ ] Commit as `test: define workflow runtime contract`.

### Task 2: Add Workflow State Model and Router

**Files:**
- Create: `tooling/workflow/__init__.py`
- Create: `tooling/workflow/state.py`
- Create: `tooling/workflow/router.py`
- Create: `templates/workflow-state.yaml`

**Interfaces:**
- Produces: `load_state(path)`, `save_state(path, state)`, `initial_state(client_id)`, `next_stage(root, client_dir, state)`, and structured blocked results.

- [ ] Implement minimal state helpers to satisfy initial-state tests.
- [ ] Implement ordered stages: `client-intake`, `resolve-intelligence`, `resource-research`, `generate-directions`, `build-prototype`, `visual-qa`, `client-review`, `productionize`.
- [ ] Make the router require validated artifacts before advancing.
- [ ] Return `blocked: prototype-platform-not-installed` at `build-prototype` while Milestone B files are absent.
- [ ] Run runtime tests and commit as `feat: add workflow state router`.

### Task 3: Add Client Workspace Initializer

**Files:**
- Create: `tooling/workflow/initialize_client.py`
- Create: `templates/client-profile.yaml`

**Interfaces:**
- Consumes: `initial_state()`.
- Produces: `initialize_client(root, client_id, display_name=None)` and CLI entry point.

- [ ] Create exact skeleton: `brief.md`, `client-profile.yaml`, `workflow-state.yaml`, and `.gitkeep` files under `references/`, `resources/`, `directions/`, `fixtures/`.
- [ ] Refuse if `client-projects/<client_id>` already exists.
- [ ] Validate safe client IDs before filesystem writes.
- [ ] Run initializer tests and commit as `feat: add client workflow initializer`.

### Task 4: Add Stored Stage Workflows and Templates

**Files:**
- Create: `workflows/01-client-intake.md`
- Create: `workflows/02-resolve-intelligence.md`
- Create: `workflows/03-resource-research.md`
- Create: `workflows/04-generate-directions.md`
- Create: `workflows/05-build-prototype.md`
- Create: `workflows/06-visual-qa.md`
- Create: `workflows/07-client-review.md`
- Create: `workflows/08-productionize.md`
- Create: `templates/direction.yaml`
- Create: `templates/direction-comparison.yaml`
- Create: `templates/approved-experience.yaml`

**Interfaces:**
- Each workflow must contain `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, `NEXT`.
- Templates define canonical output fields for OpenCode.

- [ ] Add the eight stage contracts with explicit read/write boundaries from the spec.
- [ ] Ensure `04-generate-directions.md` requires 6–10 candidates, scoring, strategic diversity, and no forced Discovery/Search/Trade output.
- [ ] Ensure prototype/visual-QA workflows explicitly reference their Milestone-B block.
- [ ] Add canonical direction/comparison/approved-experience templates.
- [ ] Run workflow-file structure tests and commit as `feat: add stored agency workflows`.

### Task 5: Add Runtime Validation and Transition Rules

**Files:**
- Create: `tooling/workflow/validate_workflow.py`

**Interfaces:**
- Produces: `validate_runtime(root) -> list[str]`, `validate_client(root, client_dir) -> list[str]`, and module CLI exit status.

- [ ] Validate all eight workflow files and required sections.
- [ ] Validate required templates exist.
- [ ] Validate workflow-state shape and legal stage names/status values.
- [ ] Validate completed stages have required artifacts.
- [ ] Validate skipped resource-research entries include a reason.
- [ ] Validate directions A/B/C plus comparison before prototype routing.
- [ ] Validate approved-experience before productionization.
- [ ] Run runtime tests and module validator; commit as `feat: validate workflow runtime`.

### Task 6: Wire OpenCode Routing Rules

**Files:**
- Modify: `AGENTS.md`
- Create: `docs/workflow-runtime.md`
- Modify: `docs/platform-status.md`

**Interfaces:**
- OpenCode must read client `workflow-state.yaml`, ask the router for the next legal stage, load only the matching workflow file plus its declared inputs, execute, validate, and update state.

- [ ] Add master workflow routing rules to `AGENTS.md`.
- [ ] Document standard command flow and examples in `docs/workflow-runtime.md`.
- [ ] Update platform status to mark Workflow Runtime implemented while Milestone B remains pending.
- [ ] Run all repository, Knowledge Platform, workflow runtime, and Flutter checks.
- [ ] Commit as `docs: wire OpenCode to workflow runtime`.

### Task 7: Final Verification and PR

**Files:** No new production files.

- [ ] Run `python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime -v`.
- [ ] Run `python tooling/validation/validate_repo.py`.
- [ ] Run `python -m tooling.knowledge.validate_knowledge`.
- [ ] Run `python -m tooling.workflow.validate_workflow`.
- [ ] Confirm Flutter CI passes on the PR head.
- [ ] Open/update a PR with scope, validation evidence, and dependency on Milestone A.
