# Milestone E — Workflow Hardening — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-e-workflow-hardening` (do not work on `main`; do not merge)
- Base: `main` at `ba28242` (Milestone D merged, PR #21); branch point `21eb01f`
- Spec: `docs/superpowers/specs/2026-09-17-milestone-e-workflow-hardening-design.md` (`93df214`)
- Plan: `docs/superpowers/plans/2026-09-17-milestone-e-workflow-hardening-implementation.md` (`21eb01f`)
- Execution model: exactly 3 cycles (Cycle 1 = state/contracts/manifests; Cycle 2 = idempotency/
  lease/resume/audit; Cycle 3 = runner/CI/E2E).
- Mode: TDD, fresh implementer + fresh independent reviewer per cycle, final whole-branch review.
- Started: 2026-09-17

## Resume protocol

1. `git branch --show-current` — confirm `milestone-e-workflow-hardening`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first cycle not marked `ACCEPTED`; re-run its focused tests first.

## Preflight consistency scan

### Verified

- `git fetch` — `origin/milestone-e-workflow-hardening` carries the E design (`93df214`) + plan
  (`21eb01f`) on top of merged Milestone D (`ba28242`).
- `git branch --show-current` → `milestone-e-workflow-hardening`.
- `git status` → only the three untracked `pubspec.lock` files; they stay uncommitted and the
  lockfile policy is unchanged.
- Both authority documents read in full.

### Existing runtime reality

| Concern | Current reality | E treatment |
|---|---|---|
| `workflow-state.yaml` | `tooling/workflow/state.py` — `STAGES` (8), `STATUSES`, `initial_state` (**version 1**), `load_state`, `save_state` (non-atomic `write_text`). `templates/workflow-state.yaml` is v1. **No client currently has a `workflow-state.yaml`** (only `client-projects/{schema,examples}` exist, both excluded from validation). | `normalize_state` accepts v1+v2; `initial_state` emits v2; `save_state_atomic` (temp + `os.replace`); template → v2. |
| v1 compatibility | `validate_workflow._validate_state` hard-requires `version == 1`. Existing tests build v1 states via `initial_state()` + dict mutation and call `validate_client`. | Validator normalizes first, then checks; v1 stays valid and is migrated on write. |
| Router/state ownership | `router.next_stage(root, client_dir, state)` reads `completed`/`skipped` + C/D artifacts; returns `{stage,status,reason}`. | Keep the return contract. Add evidence-awareness without breaking artifact-gated behaviour (RE2). |
| Stage contracts | `workflows/01..08-*.md` with `PURPOSE/READ/PROCESS/WRITE/VALIDATE/DO NOT/NEXT`. NEXT graph is strictly linear `01→02→…→07→08`, with `08` pointing at later milestones. `validate_workflow.validate_workflow_file` checks the seven sections only. | Add `workflows/contracts/*.yaml` metadata + parity validation (RE3). |
| Execution manifests | Do not exist. | New `tooling/workflow/manifests.py` + schema + `client-projects/<client>/workflow/executions/` layout (RE4). |
| Atomic write ordering | `save_state` writes in place. | Evidence first, canonical pointer second (RE5); reconciliation for orphan evidence. |
| Lease/concurrency | None. | Lease inside `workflow-state.yaml` (RE6). |
| Retry/resume | None; no attempt identity. | `IdempotencyDecision` + `RecoveryDecision` (RE7). |
| Checkpoint identity | None. | `CheckpointRecord` + `stage_state.<stage>.last_checkpoint`. |
| Validator gates | `validate_workflow.validate_client` checks artifact existence per completed stage + domain validators. | Two-tier completion evidence (RE2) + declared prerequisite/completion validators per stage contract. |
| Rulings/deviations/overrides | None. | `tooling/workflow/audit.py` + JSONL + schema (RE8). |
| CI relationship | `validate.yml` runs an explicit unittest module list + `validate_repo.py` + knowledge/workflow/prototype validators. | Add the new E test modules; `validate_workflow` stays a required gate; CI never mutates (RE9). |
| C/D boundaries | Review/QA authority lives in Dart (`apps/prototype_app/lib/{review,qa}`) and Python `tooling/visual_qa`; the workflow runtime only consumes artifacts. | Workflow modules must never mutate or absorb those authorities (RE10). |
| OpenCode runner | None (OpenCode reads `workflow-state.yaml` + `workflows/*.md` manually per AGENTS.md). | Thin `runner.py` façade (Cycle 3). |
| Interruption/recovery | None. | `recovery.py` + E2E scenarios (Cycle 2/3). |

### Plan-vs-repository conflicts and resolutions

- **`validate_workflow` requires `version == 1`, and existing tests persist v1 state.** Making v2 the
  write format would break them if the validator stayed strict. → **RE1**.
- **Existing router/validator tests set `completed` with no manifests.** Requiring manifests for every
  completed stage would break them and the artifact-gated contract. → **RE2**.
- **`templates/workflow-state.yaml` is v1 and is validated only by YAML parse.** → **RE1** (update to
  v2 while v1 remains readable).
- **No client has a live `workflow-state.yaml`.** Migration is therefore proven by fixtures and the
  template, not by a real client; recorded as a scope note.

## Rulings

- **RE1 — v2 is the canonical write format; v1 stays readable.** `initial_state` emits `version: 2`
  (superset of v1 keys: `workflow`, `run_id`, `stage_state`, `active_lease`, `last_transition`).
  `normalize_state(data, client_id=None)` returns canonical v2 from either version without mutating
  its input and raises `WorkflowStateError` for unsupported versions or invalid stages/statuses.
  `load_state` normalizes; `save_state` writes v2 atomically via `save_state_atomic`.
  `validate_workflow._validate_state` normalizes before checking, so committed v1 state remains valid.
  `templates/workflow-state.yaml` is updated to v2.
- **RE2 — Two-tier completion evidence.** Tier 1 (always): the stage's declared artifacts must exist
  and their domain validators must pass — this preserves the existing artifact-gated contract for v1
  and v2 state. Tier 2 (hardened): when `stage_state.<stage>` records a completed attempt, a frozen,
  schema-valid execution manifest must exist whose required outputs and completion validators passed.
  A `stage_state` entry claiming completion without valid manifest evidence is a validation error.
  `completed[]` alone is never treated as hardened proof, but remains valid for legacy state.
- **RE3 — Stage contracts are metadata, not instructions.** `workflows/*.md` remain the executable
  instruction authority. `workflows/contracts/<nn>-<stage>.yaml` declare only `stage`, `version`,
  `requires.stages`, `requires.artifacts`, `produces`, `validators`, `checkpoints`, `next`. Parity
  validation requires: the contract set equals `STAGES`; each contract's `next` matches the Markdown
  `NEXT` reference; every Markdown file declares all seven required sections; a Markdown/metadata
  conflict is a deterministic validation error (`StageContractConflict`), never a silent agent choice.
  No business prose may live only in YAML.
- **RE4 — Manifest and audit layout.** Manifests:
  `client-projects/<client>/workflow/executions/<run-id>/attempt-<n>.yaml` (create-only; frozen when
  completed). Audit: `client-projects/<client>/workflow/audit.jsonl` (append-only JSONL). Neither is
  globally required by `validate_repo`; both are validated when present.
- **RE5 — Ordered writes with deterministic reconciliation.** Evidence (manifest + audit) is persisted
  before the canonical state pointer. If evidence exists without a matching state pointer, recovery
  returns `RECONCILE_STATE` (re-validate evidence, then advance exactly once); if the pointer is ahead
  of valid evidence, validation fails and recovery returns `BLOCK`.
- **RE6 — The lease lives in `workflow-state.yaml`.** `active_lease` is nullable with
  `lease_id/owner/run_id/acquired_at/expires_at`. Acquisition must detect an active, unexpired,
  different-owner lease and fail with `WorkflowLeaseConflict`; expiry is deterministic
  (`now >= expires_at`); reclaim records a recovery audit event; release requires matching lease
  id + owner. The lease is coordination, never completion proof.
- **RE7 — Idempotency identity is content-based.** Input identity derives from canonical relative paths
  plus sha256 of contract-relevant bytes — never wall-clock time. `REUSE` (same inputs + already-valid
  completed outputs), `RESUME` (same run/attempt with a durable checkpoint), `NEW_ATTEMPT` (changed
  inputs or a non-resumable prior attempt, with incremented attempt number and untouched prior
  evidence).
- **RE8 — Manual overrides are human-only and audited.** `make_override` requires a non-agent actor
  (an `actor` beginning with `opencode:` is rejected), plus `affected_gate`, `reason`, `timestamp`,
  previous/requested state, and evidence. Rulings and deviations are append-only; no record is edited
  in place. An override can never mutate a C/D domain authority.
- **RE9 — CI validates, never mutates.** No CI step writes `workflow-state.yaml`, acquires a lease,
  rewrites a manifest, or performs recovery. CI adds the new E test modules and keeps
  `validate_workflow` as a required gate.
- **RE10 — C/D authorities remain separate.** No workflow module imports or mutates `ReviewState`,
  `FeedbackRecord`, `RefinementBatch`, `ApprovalSnapshot`, `QAFinding`, or `QaCoordinator` state;
  manifests may only reference their IDs/hashes/versions. An architecture test enforces this.
- **RE11 — No generic BPM engine.** The workflow graph is the fixed eight-stage linear sequence; no
  dynamic graph definition, no queue, no daemon, no distributed coordination, no autonomous approval,
  no production authorization, no deployment engine.
- **RE12 — Model routing deviation.** Only `explore` and `general` subagent types are available. Each
  cycle uses a fresh `general` implementer and a fresh independent `general` reviewer; the final
  whole-branch review uses the strongest available reasoning configuration. Recorded as a routing
  fallback per the milestone instructions.
- **RE13 — Orchestrator verification.** The orchestrator verifies every subagent deliverable by running
  the focused suites and inspecting the diff, fixes gaps directly when needed, and records any
  implementation performed outside the dispatched implementer.
- **RE14 — `run_id` format.** `wf-<client>-<yyyyMMddTHHMMSSZ>-<short>` generated from an injected clock
  so tests are deterministic; `run_id` is recorded in state and manifests.
- **RE15 — Scope guard.** No F/G/H work: no production authorization, no release/deployment engine, no
  reference-client E2E beyond the E fixtures.

## Cycle table

| Cycle | Scope | Status | Commits |
|-------|-------|--------|---------|
| 1 | State machine + stage contracts + execution manifests | PENDING | — |
| 2 | Idempotency + leases + retry/resume + audit/recovery | PENDING | — |
| 3 | OpenCode orchestration + CI hardening + E2E resumability | PENDING | — |

## Progress log

- 2026-09-17 — Preflight complete. Branch `milestone-e-workflow-hardening` at `21eb01f`; spec + plan
  present; Milestone D merged on `main`. RE1–RE15 recorded. Untracked `pubspec.lock` files
  intentionally uncommitted.
