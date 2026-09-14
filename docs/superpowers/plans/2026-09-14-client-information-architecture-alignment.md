# Client Information Architecture Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make client workspaces and workflow gates follow the canonical 20-stage operating table while preserving the existing Knowledge Platform, eight-stage Workflow Runtime, and shared Flutter Prototype Platform.

**Architecture:** Introduce canonical `input/` and `derived/` client layers plus a shared path resolver. The eight executable workflow files remain the runtime control plane, but each explicitly maps to its corresponding detailed stages from the 20-stage operating flow. Existing downstream direction/prototype/approval contracts remain unchanged.

**Tech Stack:** Python 3.12, YAML, Flutter/Dart, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-14-client-information-architecture-alignment-design.md`

## Global Constraints

- Client-supplied facts must live under `input/`; OpenCode-derived interpretations must live under `derived/`.
- New writes use canonical paths; limited legacy reads are allowed only for migration compatibility.
- Preserve the eight workflow files and existing Workflow Runtime stage names.
- Preserve the Knowledge Platform and shared Flutter Prototype Platform architecture.
- Production integrations/release infrastructure remain outside this change.

---

### Task 1: Define canonical client workspace contract

**Files:**
- Modify: `tooling/validation/test_workflow_runtime.py`
- Create: `tooling/workflow/client_paths.py`
- Modify: `tooling/workflow/initialize_client.py`

**Interfaces:**
- `ClientPaths.for_client(client_dir: Path) -> ClientPaths`
- canonical properties include `client_input`, `client_profile`, `resolved_presets`, `intelligence_map`, `capability_map`, `gaps`, `resource_requirements`, and `resource_selection`.

- [ ] Update initializer tests to require `input/client-input.yaml`, attachment subfolders, the six `derived/*.yaml` artifacts, resources/directions markers, brief, and workflow state.
- [ ] Add tests that canonical path properties resolve to the new structure and legacy reads can locate old root-level client profile/intelligence files when present.
- [ ] Run workflow runtime tests and verify RED against the current flat initializer.
- [ ] Implement `client_paths.py` and update `initialize_client.py` to seed canonical files with empty/explicitly unresolved values.
- [ ] Run workflow runtime tests and verify GREEN.

### Task 2: Enforce detailed intelligence/resource gates

**Files:**
- Modify: `tooling/workflow/router.py`
- Modify: `tooling/workflow/validate_workflow.py`
- Modify: `tooling/validation/test_workflow_runtime.py`

**Interfaces:**
- client-intake completion requires canonical client input + derived profile.
- resolve-intelligence completion requires resolved presets + intelligence map + capability map + gaps.
- resource-research completion requires resource requirements + resource selection unless skipped with a reason.

- [ ] Add failing tests for each missing canonical gate artifact.
- [ ] Update router path reads to use `ClientPaths`.
- [ ] Update runtime validator required artifacts to use canonical paths.
- [ ] Verify workflow runtime tests and prototype/workflow integration tests pass.

### Task 3: Point prototype tooling at canonical derived profile

**Files:**
- Modify: `tooling/prototype/build_prototype.py`
- Modify: `tooling/validation/test_prototype_platform.py`

**Interfaces:**
- `compose_prototype` reads `derived/client-profile.yaml` via `ClientPaths` and retains legacy read fallback only for migration fixtures.

- [ ] Update composer test fixture to create canonical derived profile.
- [ ] Verify test fails before implementation.
- [ ] Update composer to use shared path resolution.
- [ ] Verify prototype tests pass and generated manifest/fixture paths remain unchanged.

### Task 4: Align stored workflows with the 20-stage model

**Files:**
- Modify: `workflows/01-client-intake.md`
- Modify: `workflows/02-resolve-intelligence.md`
- Modify: `workflows/03-resource-research.md`
- Modify: `workflows/04-generate-directions.md`
- Modify: `workflows/05-build-prototype.md`
- Modify: `workflows/06-visual-qa.md`
- Modify: `workflows/07-client-review.md`
- Modify: `workflows/08-productionize.md`

**Interfaces:**
- 01 maps stages 1–2; 02 maps 3–4; 03 maps 5–6; 04 maps 7–8; 05 maps 9–13; 06 maps 14–15; 07 maps 16–17; 08 maps 18–20.

- [ ] Update READ/WRITE/VALIDATE sections to canonical paths and explicit stage outputs.
- [ ] Preserve required workflow section headings so runtime workflow validation remains green.
- [ ] Ensure productionize documents reusable-learning promotion and final QA/release gates without pretending those production capabilities are implemented.

### Task 5: Add templates and migrate reference client

**Files:**
- Create: `templates/client-input.yaml`
- Create: `templates/resolved-presets.yaml`
- Create: `templates/intelligence-map.yaml`
- Create: `templates/capability-map.yaml`
- Create: `templates/gaps.yaml`
- Create: `templates/resource-requirements.yaml`
- Move/replace reference client profile into: `client-projects/examples/prototype-demo/derived/client-profile.yaml`
- Create remaining reference `input/` and `derived/` artifacts under `client-projects/examples/prototype-demo/`.

**Interfaces:**
- Templates provide structurally valid empty contracts; example client demonstrates populated canonical layout.

- [ ] Add template validation expectations to runtime validator/tests.
- [ ] Seed example client input and derived intelligence without inventing unsupported client facts.
- [ ] Keep existing directions/prototype/approval artifacts unchanged.

### Task 6: Make the 20-stage table canonical documentation

**Files:**
- Create: `docs/operating-flow.md`
- Modify: `AGENTS.md`
- Modify: `docs/workflow-runtime.md`
- Modify: `docs/prototype-platform.md`
- Modify: `docs/platform-status.md`

**Interfaces:**
- `docs/operating-flow.md` is the canonical detailed consulting/delivery flow.
- `AGENTS.md` routes client work through input → derived → resources/directions → prototype/QA → approval.

- [ ] Document all 20 stages with inputs, read/write locations, actor, and gate.
- [ ] Explain the mapping from 20 detailed stages to eight runtime workflow files.
- [ ] Update all path examples to canonical structure.
- [ ] Correct Milestone B status to merged via PR #6.

### Task 7: Final verification

**Files:**
- Modify only as needed from verification failures.

- [ ] Run Repository Validation: repository structure, Knowledge Platform, Workflow Runtime, Prototype Platform, integration contracts.
- [ ] Run Flutter CI: analyze/tests across initialized packages/apps and Flutter Web prototype build.
- [ ] Confirm legacy flat paths are not produced for newly initialized clients.
- [ ] Open PR with exact verification evidence and leave unmerged for review.