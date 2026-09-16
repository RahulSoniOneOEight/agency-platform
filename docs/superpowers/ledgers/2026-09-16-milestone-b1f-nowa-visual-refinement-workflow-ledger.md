# Milestone B.1F — Nowa-Compatible Visual Refinement Workflow — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-b1f-nowa-visual-refinement-workflow`
- Base: B.1E merged baseline (`02d38db`, PR #15)
- Spec: `docs/superpowers/specs/2026-09-16-milestone-b1f-nowa-visual-refinement-workflow-design.md` (`29ed17c`)
- Plan: `docs/superpowers/plans/2026-09-16-milestone-b1f-nowa-visual-refinement-workflow-implementation.md` (`31fd5a7`)
- Mode: TDD, one task at a time, fresh reviewer per task, no merge.
- Started: 2026-09-16

## Resume protocol

1. `git branch --show-current` — confirm `milestone-b1f-nowa-visual-refinement-workflow`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first task not marked `ACCEPTED`; re-run its focused tests first.

## Pre-flight plan consistency scan (recorded before Task 1)

### Repository state
- `client-projects/schema/` holds `client-profile.schema.json` and `input/*` schemas.
- `tooling/prototype/` holds the B.1B/B.1E prototype tooling; `compose_runtime_bundle(root, client_dir)`
  (B.1E signature) is the runtime composer.
- `tooling/validation/validate_repo.py` exposes `generated_runtime_bundle_errors`,
  `theme_contract_errors`, `flutter_binding_errors`, and `main`.
- `tooling/knowledge/index_design_contract.build_indexes(root)` is the canonical Design Contract
  catalog index (components/patterns/journeys).
- No refinement-notes artifacts exist yet.

### Task-to-task shared files / interfaces
- Task 1 produces `load_refinement_notes(path) -> dict` and
  `validate_refinement_notes(root, path) -> list[str]`, plus
  `client-projects/schema/refinement-notes.schema.json` and `tooling/validation/test_refinement_notes.py`.
- Task 2 creates the reference note and a runtime non-authority regression in
  `tooling/validation/test_runtime_bundle.py`.
- Task 3 consumes `validate_refinement_notes` in `validate_repo.py` and tests in
  `test_validate_repo.py`.
- Task 4 produces `docs/nowa-visual-refinement-workflow.md`.
- Task 5 extends the focused tests for architecture-boundary regressions.
- Task 6 runs full verification + final review + PR.

### Producer / consumer contracts
- `validate_refinement_notes(root, path) -> list[str]` must never raise for ordinary validation
  failures and must return `sorted(set(errors))`; consumed by Task 3 and Task 5.
- The note contract is metadata only: no runtime/theme/Flutter consumer may read it.
- Repository validation discovers `client-projects/**/prototype/refinement-notes.yaml` (optional).

### Internal consistency
- Task 1's schema and Task 3's discovery path must agree on
  `client-projects/**/prototype/refinement-notes.yaml`.
- The Task 2 plan example calls `compose_runtime_bundle(client_dir)`; the branch's current
  signature is `compose_runtime_bundle(root, client_dir)` (R3).

### Conflicts with Global Constraints — resolved
- Notes must never be runtime input → Tasks 2 and 5 add explicit regressions.
- Optional note file → Task 3 must not add it to required paths.
- Deterministic ordering → `sorted(set(errors))` in Task 1 and path-then-message ordering in Task 3.
- No Nowa API/editor/runtime dependency → Task 4 is documentation only.

## Rulings

- **R1 — Schema path.** `client-projects/schema/refinement-notes.schema.json` exactly as the plan
  specifies (not under `schema/input/`).
- **R2 — Canonical ID validation.** Validate `component`/`pattern` values against
  `build_indexes(root)` existence using the existing Design Contract index; no second catalog parser.
- **R3 — Composer signature.** Use `compose_runtime_bundle(root, client_dir)` (current B.1E
  signature); the plan's single-argument example predates it.
- **R4 — Model routing deviation.** Only `explore`/`general` task subagents are available; there is
  no DeepSeek Pro/Flash or GPT-5.6 Sol routing from this session. Implementer subagents are used
  where isolation is safe; otherwise the orchestrator implements directly with strict TDD. Every
  task is reviewed by a fresh `general` reviewer, plus a final whole-branch review.
- **R5 — CI.** Add `tooling.validation.test_refinement_notes` to `.github/workflows/validate.yml`
  (consistent with B.1D/B.1E), in addition to the transitive `validate_repo.py` coverage.
- **R6 — Free-form metadata.** `screen`, `component` (value checked against catalog), `pattern`
  (value checked against catalog), `subject`, `target`, and `notes` are otherwise free-form; only
  enums, duplicate IDs, types, canonical component/pattern IDs, and unknown properties are validated.
- **R7 — Required paths.** Add the schema, validator module, and focused test module to
  `REQUIRED_PATHS`; never add the optional note file.
- **R8 — Error prefixing.** Repository-validation note errors are prefixed with the note path
  relative to root and stable-sorted (path, then message).

## Task table

| Task | Scope | Status | Commit |
|------|-------|--------|--------|
| 1 | Refinement-note schema + deterministic validator | PENDING | — |
| 2 | Governed example + runtime non-authority regression | PENDING | — |
| 3 | Repository validation integration | PENDING | — |
| 4 | Operator workflow + OpenCode reconciliation guide | PENDING | — |
| 5 | Architecture-boundary regression tests | PENDING | — |
| 6 | Full verification + final review + PR | PENDING | — |

## Progress log

- 2026-09-16 — Pre-flight complete. Ledger initialized. No tasks started.
