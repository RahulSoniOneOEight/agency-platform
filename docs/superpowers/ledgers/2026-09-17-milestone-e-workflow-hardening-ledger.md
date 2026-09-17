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
| 1 | State machine + stage contracts + execution manifests | ACCEPTED | `02afbd9` `493b032` `99c9ee4` `146eba9` `a4d50a0` |
| 2 | Idempotency + leases + retry/resume + audit/recovery | ACCEPTED | `a28d2b3` `c36c1d1` `b86b9b8` `1fc71bd` `0196934` |
| 3 | OpenCode orchestration + CI hardening + E2E resumability | ACCEPTED | `a094d6b` `59d0507` `6397c73` `560852c` `782df58` `8e532cd` |

## Progress log
- 2026-09-17 — Preflight complete. Branch `milestone-e-workflow-hardening` at `21eb01f`; spec + plan
  present; Milestone D merged on `main`. RE1–RE15 recorded. Untracked `pubspec.lock` files
  intentionally uncommitted. Baseline: 455 Python tests OK.
- 2026-09-17 — **Cycle 1 implemented.** Commits: `02afbd9` workflow-state v2 + schema + template;
  `493b032` machine-readable stage contracts + parity validator + 8 contracts + schema; `99c9ee4`
  execution manifests + validator-gated transition service + schema + validator/router/initializer
  wiring.
  - Delivered: `state.normalize_state`/`save_state_atomic`/`initial_state` v2 (v1 read-compatible);
    `workflow-state.schema.json`; `contracts.StageContract` + `validate_stage_contracts` parity against
    the Markdown `NEXT` graph; `workflows/contracts/01..08-*.yaml`; `manifests.ExecutionManifest`
    (+`ArtifactRef`/`CheckpointRecord`/`ValidatorEvidence`, `sha256_file`,
    `write_manifest_create_only`, `load_manifest`, `validate_manifest`); `execution.start_attempt`/
    `record_checkpoint`/`fail_attempt`/`complete_attempt` (evidence-before-state);
    `validate_workflow` tier-2 manifest evidence + contract parity; `router` normalization +
    `stage_state` awareness; `initialize_client` creates `workflow/executions/`.
  - Tests: `test_workflow_state_v2` 27, `test_workflow_contracts` 19, `test_workflow_manifests` 21,
    `test_workflow_runtime` 24 → repo suite **530 tests OK**; `validate_workflow`, `validate_repo`,
    `validate_knowledge`, `validate_prototype` pass.
  - Independent review: **ACCEPT-WITH-MINORS**, 0 blockers, **1 major** — `complete_attempt` did not
    verify that the supplied manifest belonged to the state it advanced, so a directly supplied
    manifest could skip stages (`client-intake → build-prototype`) or cross clients. All 14 required
    checks PASS. 9 minors recorded.
  - Fixes (`146eba9`): added `_require_attempt_matches_state` (stage + run + client guards) to
    `complete_attempt`, the stage guard to `fail_attempt`; `normalize_state` coerces YAML
    `date`/`datetime` `last_updated` to ISO and validates `stage_state.<stage>.status`;
    `write_manifest_create_only` refuses any non-`in_progress` manifest; `ExecutionManifest.from_dict`
    rejects unknown statuses; `validate_workflow` no longer masks a broken `artifact_manifest_ref`
    with a fallback; template quoted; 6 new runtime tests + 5 state tests + 2 manifest tests.
  - Scoped re-review: **ACCEPT-WITH-MINORS — major M1 closed**; exploit reproduced pre-fix and now
    raises `IllegalStageTransition` with state byte-identical. New minors fixed immediately: stripped
    UTF-8 BOMs accidentally introduced by PowerShell `Set-Content -Encoding utf8` in three files;
    tightened the `run_id` guard (no longer skipped when `state["run_id"]` is `None`); gave
    `fail_attempt` the full stage/run/client guard via the shared helper (signature is now
    `fail_attempt(client_dir, state, manifest, *, reason, at)`).
  - Post-fix counts: `test_workflow_state_v2` 32, `test_workflow_contracts` 19,
    `test_workflow_manifests` 23, `test_workflow_runtime` 33 → repo suite **546 tests OK**.
  - **Accepted/deferred minors:** `fail_attempt` still does not persist the failed manifest (plan
    Cycle 2 Step 11 owns failure-evidence persistence); the router still routes on unverified
    `stage_state` (routing is not proof; `validate_client` remains the evidence gate); frozen
    manifests hold mutable nested ruling/deviation dicts in memory (overwrite is blocked); no
    cross-check of manifest hashes against artifact bytes (hashing is identity, not security, per
    spec §3). CI does not yet run the new E test modules — Cycle 3 Step 8 (RE9) owns that.
- 2026-09-17 — **Cycle 2 implemented.** Commits: `a28d2b3` lease domain; `c36c1d1` audit records;
  `b86b9b8` idempotency decision + recovery + failure-evidence persistence; `1fc71bd` review fixes.
  - Delivered: `lease.WorkflowLease` + `acquire/renew/release/reconcile_expired_lease/load_lease/is_expired`
    (deterministic `lease-` ids, idempotent same-owner re-acquire, `WorkflowLeaseConflict`/`Expired`/
    `OwnershipError`, never touches the stage pointer); `audit.AuditRecord` + `make_ruling`/
    `make_deviation`/`make_override`/`make_recovery_record`/`append_audit_record`/`load_audit_records`/
    `validate_audit_record` (append-only JSONL, content-derived ids, human-only overrides);
    `workflow-audit-record.schema.json`; `execution.IdempotencyAction`/`IdempotencyDecision`/
    `prior_manifests`/`decide_idempotency` (content-based identity, no wall clock);
    `recovery.RecoveryAction`/`RecoveryDecision`/`inspect_recovery` (pure read, six-row table);
    lease + audit + failure-evidence wiring into the execution ordering.
  - Tests: `test_workflow_lease` 31, `test_workflow_audit` 28, `test_workflow_idempotency` 23,
    `test_workflow_recovery` 12, `test_workflow_runtime` 41 → repo suite **650 tests OK**;
    `validate_workflow`, `validate_repo`, `validate_knowledge`, `validate_prototype` pass.
  - Independent review: **REJECT** — **1 blocker** (B1: the lease was never enforced on the
    state-mutating execution path, so a second owner could `start_attempt` and write an artifact while
    another owner held a live lease) and **1 major** (M1: the human-only override rule was enforced
    only in the factory, so a hand-built `opencode:` override could be persisted). 6 minors.
  - Fixes (`1fc71bd`): `start_attempt` now acquires the lease before writing any evidence
    (idempotent same-owner re-acquire; `WorkflowLeaseConflict` for a second owner with zero mutation;
    deterministic expired-lease reclaim that appends a durable `recovery` audit record);
    `complete_attempt` requires the owning lease and releases ownership only after evidence is durable;
    `fail_attempt` requires a lease and persists failure evidence before releasing; recovery gained a
    pointer-ahead-of-prerequisites `BLOCK` row and a corrected `_unfinished_work`; overrides are
    rejected at `from_dict`/`append_audit_record`/`validate_audit_record` and in the schema.
  - Scoped re-review: **ACCEPT-WITH-MINORS — B1 and M1 closed**; all repro probes now fail safely.
    Residual minor fixed immediately: `fail_attempt` now takes a required `actor` and enforces lease
    *ownership* (not just presence), matching `complete_attempt`; the override actor check is
    normalized (case/whitespace) and the schema-agreement cases now cover the agent-override rule.
  - **Accepted minors (recorded, non-gating):** `release_after_completion` and `renew_lease` are
    currently only test-reachable (Cycle 3's runner will use them); `_existing_attempts` is retained as
    an unused private reader; the router still routes on unverified `stage_state` (routing is not
    proof); no cross-check of manifest hashes against artifact bytes (hashing is identity, not
    security, per spec §3). CI does not yet run the new E test modules — Cycle 3 Step 8 (RE9) owns that.
  - Post-fix counts: repo suite **650 tests OK**.
- 2026-09-17 — **Cycle 3 implemented.** Commits: `a094d6b` resumable runner + runner/E2E tests;
  `59d0507` validator/CI/validate_repo hardening + docs/AGENTS/`## RUNTIME` notes; `6397c73` review fixes.
  - Delivered: `runner.py` (`inspect_client`, `start_stage`, `checkpoint_stage`, `fail_stage`,
    `complete_stage`, `resume_stage`, `reconcile_state`, `WorkflowRunStatus`, `StageRun`,
    `RecoveryRequired`/`WorkflowBlocked`); validator hardening (raw-vs-normalized state schema, lease
    key/ordering, `artifact_manifest_ref` identity, manifest schema, audit line validation,
    pointer-ahead-of-prerequisites); `validate_repo` 141 required paths; CI runs 24 explicit test
    modules with `validate_workflow` still required and no mutating step; `docs/workflow-runtime.md`
    rewritten with verified API entry points; `AGENTS.md` fresh-session loop; `## RUNTIME` notes
    appended to all eight Markdown stage contracts; `test_workflow_authority_boundaries.py`.
  - Tests: `test_workflow_runner` 13, `test_workflow_resume_e2e` 8, `test_workflow_authority_boundaries`
    4, `test_workflow_runtime` 57 → repo suite **691 tests OK**; `validate_workflow`, `validate_repo`
    (141 paths), `validate_knowledge`, `validate_prototype`, `validate_visual_qa` pass.
  - Independent review: **REJECT** — **1 blocker** (B1: the new raw-state schema check rejected
    committed v1 `workflow-state.yaml`, contradicting RE1 and acceptance criterion #2) and
    **1 major** (M1: `reconcile_state` cleared a foreign *live* lease with no ownership check and no
    audit record). 9 minors.
  - Fixes (`6397c73`): the strict raw schema check now applies only to `version == 2` files while the
    normalized state is always schema-checked (v1 stays valid); `reconcile_state` now refuses a foreign
    live lease with `RecoveryRequired`, reclaims an expired lease through the shared audited
    `reclaim_expired_lease` helper, and never clears an ownership it does not hold; the duplicated
    completion-transition and lease-reclaim logic was extracted into
    `execution.completion_state_transition` / `execution.reclaim_expired_lease` (m1/m2);
    `execution.iso_timestamp` is now public (m9); the missing C/D authority-boundary architecture test
    was added (m4); doc/AGENTS imprecisions fixed (m5/m6/m8).
  - **Accepted minors (recorded, non-gating):** the `stage_state` status validator branch in
    `validate_workflow` is unreachable because `normalize_state` raises first (the condition is still
    reported via the load-failure path); `_existing_attempts` remains an unused private reader; the
    router still routes on unverified `stage_state` (routing is not proof); no cross-check of manifest
    hashes against artifact bytes (hashing is identity, not security, per spec §3).
  - Post-fix counts: repo suite **691 tests OK**; `validate_repo` 141 required paths.
- 2026-09-17 — **Final whole-branch review** (`git diff ba28242...HEAD`, strongest available model):
  **REJECT — 0 blockers, 2 majors.** All 31 required checks except two passed; adversarial probes were
  otherwise well-guarded.
  - **M1** — completed manifests never recorded `outputs`: produced artifacts were merged into
    `inputs`, so `outputs` was always empty (violating spec §3 and required item 10).
  - **M2** — RE2 tier-2 evidence was not fully enforced: `validate_workflow` accepted a completed
    manifest with no passed validators, and `reconcile_state` re-checked only schema + status, so a
    forged validator-less completed manifest could advance the pointer.
  - **Fixes:** `complete_attempt` now records produced artifacts via `with_output` and a shared
    `execution.require_completion_evidence` re-validates the contract's outputs + validators;
    `manifests.manifest_identity` (de-duplicated inputs ∪ outputs) drives reuse detection;
    `validate_workflow` gained `_validate_completion_evidence` (produced artifacts, passed validators,
    manifest outputs present) plus a `stage_state` key allowlist (`STAGE_ATTEMPT_KEYS`) and a
    `stage_state` schema that forbids extra keys; `runner.reconcile_state` calls
    `require_completion_evidence` before advancing; `execution.start_attempt` refuses a RESUME for a
    foreign live lease; the audit schema rejects case/whitespace variants of the agent actor;
    Markdown section parity now matches headings exactly; the `start_stage` doc example and the
    state-writer claims were corrected.
  - **Accepted minors (recorded, non-gating):** contract `produces` lists are narrower than the
    Markdown `WRITE` prose (RE3 requires only `next` parity); `_existing_attempts` remains an unused
    private reader; the router still routes on unverified `stage_state` (routing is not proof); no
    cross-check of manifest hashes against artifact bytes (hashing is identity, not security, per
    spec §3); the local `main` ref is stale relative to `origin/main`, so the review base is
    `ba28242` (Milestone D merge).
  - Post-fix counts: repo suite **695 tests OK**; `validate_repo` 141 required paths; all validators
    and B.1D/B.1E freshness green.
