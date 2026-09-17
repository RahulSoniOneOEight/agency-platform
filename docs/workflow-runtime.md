# Workflow Runtime

The Workflow Runtime turns the agency process into repository-driven stage contracts that OpenCode can
execute repeatably. Milestone E hardened it into a deterministic, evidence-first state machine: every
stage attempt leaves a frozen manifest, every completion is validator-gated, and only one session may
mutate a client at a time.

## Mental model

```text
GitHub                              = the rules: contracts, validators, and client state
workflow-state.yaml                 = the canonical pointer (the only authority for "where are we")
workflows/NN-<stage>.md             = the human-readable stage instruction
workflows/contracts/NN-<stage>.yaml = the machine-readable contract (requires/produces/validators/checkpoints/next)
workflow/executions/<run>/attempt-N.yaml = the frozen evidence manifest for one attempt
active_lease (inside state)         = single-owner coordination for state-mutating execution
workflow/audit.jsonl                = append-only rulings, deviations, overrides, and recovery events
tooling.workflow.runner             = the only runtime module that writes workflow-state.yaml (the initializer writes it once at creation)
```

Two tiers, never confused:

- **Evidence tier** — execution manifests and audit records. Frozen, create-only, authoritative for
  what actually happened.
- **Pointer tier** — `workflow-state.yaml`. Derived from evidence; it records where the workflow
  believes it is. It is never edited by hand and never used as proof that a stage completed.

The runner is orchestration only (RE9): it carries no client-specific business logic and never
approves review, QA, or production decisions. Evidence is persisted before the canonical pointer
(RE5), and every operation is a synchronous, deterministic function of repository state plus an
injected clock — there is no queue, daemon, or distributed machinery (RE11).

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
  workflow/executions/
```

The initializer refuses to overwrite an existing client.

## Entry points

All operations are synchronous functions in `tooling.workflow.runner`. There is no runner CLI: invoke
the Python API with `python -c`. `root` is the repository root and `client_dir` is
`client-projects/<client-id>`.

### Inspect (read-only)

```bash
python -c "from pathlib import Path; from tooling.workflow.runner import inspect_client; print(inspect_client(Path('.'), Path('client-projects/abc-furniture')))"
```

`inspect_client` loads and normalizes the state, reads the lease, computes the deterministic recovery
decision, and routes the next legal stage. It writes nothing.

### Start (or idempotently reuse/resume)

```bash
python -c "from pathlib import Path; from tooling.workflow.runner import start_stage; run = start_stage(Path('.'), Path('client-projects/abc-furniture'), actor='opencode:session', source_commit_sha='<40-hex-commit>'); print(run.status.current_stage, run.manifest.run_id, run.manifest.attempt, run.lease.lease_id if run.lease else None)"
```

`start_stage` refuses when the stage contract prerequisites are unmet, acquires the lease for a
genuinely new attempt, and writes the create-only `attempt-N.yaml`. If the current inputs already
match a completed attempt it **reuses** it; if the latest attempt is in-progress with a durable
checkpoint it **resumes** it. In both reuse/resume cases it does not create a second attempt and
a **reuse** returns `lease=None`, while a **resume** returns the lease the actor already holds, so read `run.lease` defensively.

### Checkpoint (durable atomic step)

```bash
python -c "from pathlib import Path; from tooling.workflow.runner import checkpoint_stage; run = checkpoint_stage(Path('.'), Path('client-projects/abc-furniture'), run_id='<run-id>', checkpoint='intake-complete', actor='opencode:session'); print(run.status.last_checkpoint)"
```

The checkpoint name must be declared in the stage contract, and only the lease owner may checkpoint.
The checkpointed manifest is durable before the state pointer is updated.

### Complete (only after every gate passes)

```bash
python -c "from pathlib import Path; from tooling.workflow.manifests import ValidatorEvidence; from tooling.workflow.runner import complete_stage; run = complete_stage(Path('.'), Path('client-projects/abc-furniture'), run_id='<run-id>', actor='opencode:session', validator_results=[ValidatorEvidence(name='client-input-contract', status='passed', at='2026-09-17T12:00:00Z')]); print(run.status.current_stage)"
```

`complete_stage` verifies every produced artifact exists and every contract validator passed, freezes
the manifest, and only then advances the canonical pointer and releases the lease (evidence → state →
release).

### Fail

```bash
python -c "from pathlib import Path; from tooling.workflow.runner import fail_stage; run = fail_stage(Path('.'), Path('client-projects/abc-furniture'), run_id='<run-id>', reason='validator failed', actor='opencode:session'); print(run.manifest.status)"
```

Failure evidence is durable and the canonical pointer does not advance.

### Resume

```bash
python -c "from pathlib import Path; from tooling.workflow.runner import resume_stage; run = resume_stage(Path('.'), Path('client-projects/abc-furniture'), actor='opencode:session', source_commit_sha='<40-hex-commit>'); print(run.status.recovery_action)"
```

`resume_stage` acts on the deterministic recovery decision: `resume` reuses the checkpointed attempt,
`retry` starts a fresh attempt, `reconcile_state` delegates to `reconcile_state`, and `block` raises
`WorkflowBlocked`. A foreign live lease raises `RecoveryRequired`.

### Reconcile (advance a stale pointer for already-frozen evidence)

```bash
python -c "from pathlib import Path; from tooling.workflow.runner import reconcile_state; run = reconcile_state(Path('.'), Path('client-projects/abc-furniture'), actor='opencode:session'); print(run.status.current_stage)"
```

`reconcile_state` re-applies only the pointer advance implied by a durable completed manifest. It
never re-runs a stage, and it is idempotent (nothing to reconcile means no write).

## The 10-step fresh-session loop

1. Read `AGENTS.md` and this document.
2. Read `client-projects/<client>/workflow-state.yaml`.
3. Run `inspect_client`; read the recovery decision and the routed next stage.
4. If recovery is not `none`, run `resume_stage` (or `reconcile_state`) before any new work.
5. Read only the current stage's numbered `workflows/NN-*.md` and its declared inputs.
6. `start_stage` to acquire the lease and open or reuse the attempt manifest.
7. Execute the stage; `checkpoint_stage` each durable atomic step.
8. Run the validators declared by `workflows/contracts/NN-*.yaml`.
9. `complete_stage` with passed validator evidence, or `fail_stage` with a reason.
10. Persist any ruling/deviation/override as an audit record, then stop; the next stage begins at step 1.

## Leases

- The lease lives in `workflow-state.yaml` under `active_lease`; no external service is involved.
- A state-mutating execution must own the lease. A second owner is rejected with
  `WorkflowLeaseConflict` and no files change.
- The lease is coordination only: it is never completion proof and never changes `current_stage`,
  `completed`, or `pending`.
- Expiry is inclusive (`now >= expires_at`). An expired lease is reclaimed only through the
  execution/runner reclaim path (`reclaim_expired_lease` / `acquire_execution_lease`), which appends a
  durable `recovery` audit record before ownership changes. `lease.reconcile_expired_lease` itself
  only clears the mapping; the audit is written by its callers.
- A foreign *live* lease is never cleared: `resume_stage` and `reconcile_state` raise
  `RecoveryRequired`, and `complete_attempt`/`fail_attempt` raise `WorkflowLeaseOwnershipError`.
- Completion and failure release the lease after evidence is durable.

## Idempotency, resume, and recovery

- **Idempotency** is content-based: re-running a stage with unchanged inputs reuses the completed
  attempt; changed inputs create the next attempt.
- **Resume** reuses an in-progress attempt that has a durable checkpoint.
- **Recovery** is `inspect_recovery`'s deterministic, read-only decision: `none`, `resume`, `retry`,
  `reconcile_state`, or `block`. A completed manifest with a stale pointer reconciles; a pointer ahead
  of its evidence blocks.
- CI and validators never acquire leases, never rewrite manifests, and never reconcile.

## Rulings, deviations, and overrides

Rulings, deviations, manual overrides, and recovery events are appended to `workflow/audit.jsonl` as
compact JSON lines (never rewritten in place):

- `make_ruling` — a decision taken during execution, with its rationale.
- `make_deviation` — expected vs. actual behavior, including requested/actual model or tool.
- `make_override` — a manual gate override; **requires a human actor** (an `opencode:` actor is
  rejected).
- `make_recovery_record` — an expired-lease reclaim or other recovery event.

## Never edit current_stage by hand

`workflow-state.yaml` is written **only** by `tooling.workflow.runner` (and the initializer). Editing
`current_stage`, `completed`, `pending`, or `active_lease` manually is forbidden: it manufactures a
pointer with no evidence, which `inspect_recovery` and `validate_client` treat as a lie (BLOCK /
validation error). Advance the workflow by starting, checkpointing, and completing stages through the
runner.

## Input / derived boundary

```text
input/   = client/source truth
derived/ = agency/OpenCode interpretation
```

`input/client-input.yaml` is the only mandatory structured client-input file. Detailed module files
are optional at initialization and become required only when referenced from `client-input.yaml` or
explicitly required by a workflow capability. OpenCode may normalize, classify, and infer into
`derived/`, but must never silently rewrite an inference back into `input/` as if the client supplied
it.

## Stored stages

1. `01-client-intake.md`
2. `02-resolve-intelligence.md`
3. `03-resource-research.md`
4. `04-generate-directions.md`
5. `05-build-prototype.md`
6. `06-visual-qa.md`
7. `07-client-review.md`
8. `08-productionize.md`

Every stage declares `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, and `NEXT`, and has a
matching machine-readable contract under `workflows/contracts/`.

## State rules

- State alone is not proof that a stage completed; required artifacts and a completed manifest must exist.
- `resource-research` is optional but can only be skipped with a recorded reason.
- Directions require A/B/C plus comparison before prototype routing.
- Productionization requires `approved-experience.yaml`.
- The validator rejects a `current_stage` whose contract prerequisites are not in `completed`.

## Validation

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_client_input_contract tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration tooling.validation.test_workflow_state_v2 tooling.validation.test_workflow_contracts tooling.validation.test_workflow_manifests tooling.validation.test_workflow_lease tooling.validation.test_workflow_audit tooling.validation.test_workflow_idempotency tooling.validation.test_workflow_recovery tooling.validation.test_workflow_runner tooling.validation.test_workflow_resume_e2e -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

CI validates structure and contracts but never mutates workflow authority: no CI step writes
`workflow-state.yaml`, acquires a lease, rewrites a manifest, or performs recovery.

## Current boundary

This runtime orchestrates the agency process but does not itself implement Flutter prototypes,
automated screenshots, AI visual QA, production backends, or deployment. Those remain later
milestones.
