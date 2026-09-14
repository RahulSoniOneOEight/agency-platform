# Workflow Runtime Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repository-driven workflow runtime that lets OpenCode initialize client workspaces, determine the next legal stage, load stage-specific instructions, validate outputs, and persist workflow state in GitHub.

**Architecture:** `AGENTS.md` routes OpenCode into small stage contracts stored in `workflows/`. `workflow-state.yaml` is the machine-readable checkpoint, while `tooling/workflow/` owns initialization, routing, state transitions, and validation. The runtime consumes Milestone A and blocks prototype/visual-QA stages until Milestone B exists.

**Tech Stack:** Python 3.12, YAML, JSON Schema, GitHub Actions, existing Knowledge Platform contracts.

**Spec:** `docs/superpowers/specs/2026-09-14-workflow-runtime-design.md`

## Global Constraints
- GitHub is source of truth.
- OpenCode is executor/orchestrator.
- `workflow-state.yaml` is canonical checkpoint.
- `workflows/*.md` are stage contracts, not free-form prompt dumps.
- Required artifacts must exist and validate before transitions.
- Optional stages require explicit skip reason.
- Prototype/visual-QA return structured Milestone-B blocked reasons.
- Productionization requires valid `approved-experience.yaml`.
- Existing Knowledge Platform and Flutter CI remain green.

---

### Task 1: Define Workflow Runtime Contract Tests
**Files:** Create `tooling/validation/test_workflow_runtime.py`; modify `.github/workflows/validate.yml`.

- [ ] Write failing tests for initializer structure, overwrite refusal, initial routing, profile advancement, resource skip, directions-to-prototype, prototype blocked reason, productionize gate, malformed workflow file.
- [ ] Run the runtime test and verify RED.
- [ ] Extend CI with runtime test + module validator.
- [ ] Commit `test: define workflow runtime contract`.

### Task 2: Add Workflow State Model and Router
**Files:** Create `tooling/workflow/__init__.py`, `state.py`, `router.py`, `templates/workflow-state.yaml`.

- [ ] Implement `initial_state`, `load_state`, `save_state`.
- [ ] Implement ordered stages and artifact-aware `next_stage`.
- [ ] Implement structured `prototype-platform-not-installed` block.
- [ ] Run tests and commit `feat: add workflow state router`.

### Task 3: Add Client Workspace Initializer
**Files:** Create `tooling/workflow/initialize_client.py`, `templates/client-profile.yaml`.

- [ ] Create exact standard skeleton and initial state.
- [ ] Refuse overwrite and unsafe client IDs.
- [ ] Run tests and commit `feat: add client workflow initializer`.

### Task 4: Add Stored Stage Workflows and Templates
**Files:** Create eight `workflows/*.md`; create `templates/direction.yaml`, `direction-comparison.yaml`, `approved-experience.yaml`.

- [ ] Every workflow contains `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, `NEXT`.
- [ ] Direction workflow generates 6–10 candidates, scores and diversifies; does not force Discovery/Search/Trade.
- [ ] Prototype/visual-QA workflows describe Milestone-B blocks.
- [ ] Run structure tests and commit `feat: add stored agency workflows`.

### Task 5: Add Runtime Validation
**Files:** Create `tooling/workflow/validate_workflow.py`.

- [ ] Validate workflows/templates/state shape/stage names/status values.
- [ ] Validate completed-stage artifacts and skipped resource reasons.
- [ ] Validate direction artifacts before prototype and approved experience before productionize.
- [ ] Run tests + validator and commit `feat: validate workflow runtime`.

### Task 6: Wire OpenCode Routing Rules
**Files:** Modify `AGENTS.md`, create `docs/workflow-runtime.md`, modify `docs/platform-status.md`.

- [ ] Add router-driven OpenCode instructions.
- [ ] Document standard runtime and user command examples.
- [ ] Mark Workflow Runtime implemented and Milestone B pending.
- [ ] Run full checks and commit `docs: wire OpenCode to workflow runtime`.

### Task 7: Final Verification and PR
- [ ] Run repository + Knowledge Platform + runtime unit tests.
- [ ] Run repository validator.
- [ ] Run Knowledge Platform validator.
- [ ] Run Workflow Runtime validator.
- [ ] Confirm Flutter CI green.
- [ ] Open PR against `milestone-a-knowledge-platform` with validation evidence.
