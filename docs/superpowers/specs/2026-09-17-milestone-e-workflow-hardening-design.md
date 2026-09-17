# Milestone E — Workflow Hardening Design

**Date:** 2026-09-17

## Status

Approved architecture. This specification hardens the existing repository-driven Workflow Runtime after Milestones C and D without replacing its authority model or introducing a generic BPM engine.

## Purpose

Milestone E makes the agency delivery workflow resumable, deterministic, auditable, concurrency-safe, and safe to retry across fresh OpenCode sessions.

The target operating model is:

```text
GitHub
  ↓
workflow-state.yaml
  ↓
OpenCode stage execution
  ↓
prerequisite checks
  ↓
atomic work
  ↓
validators
  ↓
checkpoint
  ↓
resume / retry / next stage
```

## Existing authority preserved

```text
GitHub = durable rules + client state + workflow instructions + outputs
OpenCode = executor/orchestrator
workflow-state.yaml = canonical current checkpoint
workflows/*.md = executable stage contracts
validators = completion guardrails
```

Milestone E strengthens these existing boundaries rather than creating a second runtime.

## Goals

1. A fresh OpenCode session can resume a client workflow from repository state alone.
2. Re-running a stage is idempotent unless the stage explicitly creates a new immutable version.
3. Failed execution cannot silently advance the canonical checkpoint.
4. Stage completion is evidence-backed and validator-gated.
5. Agent rulings, deviations, overrides, and model/tool fallbacks become durable audit records.
6. Concurrent state-mutating workflow runs cannot both own the same client project.
7. Interrupted work can resume from the last completed atomic step.
8. CI validates workflow state and artifacts but never becomes the workflow authority.
9. Milestones C and D remain independent authorities for review, approval, refinement, and QA.

## Non-goals

- No generic BPM/workflow product.
- No distributed queue or orchestration service.
- No autonomous client approval.
- No autonomous production authorization.
- No replacement of `workflows/*.md` with hidden prompts.
- No new production deployment engine.
- No redesign of C.3–C.7 or D.1–D.4 domain models.

---

# 1. Workflow state authority

`client-projects/<client>/workflow-state.yaml` remains the canonical live workflow checkpoint.

It should evolve from a simple stage pointer into an explicit workflow execution record while remaining human-readable and repository-native.

Conceptual schema:

```yaml
version: 2
client_id: example-client
workflow: standard-agency
current_stage: visual-qa
status: in_progress
run_id: wf-...

completed:
  - client-intake
  - resolve-intelligence
  - generate-directions
  - build-prototype

stage_state:
  visual-qa:
    attempt: 2
    status: in_progress
    started_at: ...
    last_checkpoint: capture-complete
    artifact_manifest_ref: ...

active_lease:
  lease_id: ...
  owner: ...
  acquired_at: ...
  expires_at: ...

last_transition:
  from: build-prototype
  to: visual-qa
  at: ...
  actor: ...
```

Exact field names may be adjusted during implementation, but the authority rules below are binding.

## State rules

- State is not proof of completion; completion requires validator-backed evidence.
- `current_stage` may advance only after the current stage's declared completion gate passes.
- Invalid/failed execution cannot mutate the canonical stage pointer.
- A new stage attempt must be distinguishable from a previous attempt.
- State transitions are explicit and auditable.
- State write operations must be atomic from the workflow runtime's perspective.
- Existing version-1 state should remain readable through deterministic migration/normalization where practical.

---

# 2. Stage contracts

`workflows/*.md` remain executable stage contracts and must continue to declare:

- `PURPOSE`
- `READ`
- `PROCESS`
- `WRITE`
- `VALIDATE`
- `DO NOT`
- `NEXT`

Milestone E adds machine-readable metadata for runtime hardening without making the Markdown contracts secondary.

A stage definition may have a companion machine-readable contract containing:

```yaml
stage: visual-qa
version: 1
requires:
  stages:
    - build-prototype
  artifacts:
    - prototype/prototype-manifest.yaml

produces:
  - prototype/qa/...

validators:
  - visual-qa-contract

checkpoints:
  - capture-complete
  - findings-complete
  - validation-complete

next:
  - client-review
```

The companion contract exists to make prerequisites and gates deterministic. It must not become a hidden parallel source of business instructions that contradicts the workflow Markdown.

## Contract precedence

1. Approved milestone/design contracts and domain authorities
2. `workflows/*.md` human-readable stage contract
3. machine-readable stage metadata
4. OpenCode execution plan/ruling

A conflict between 2 and 3 is a validation error, not an invitation for the agent to choose silently.

---

# 3. Artifact and checkpoint manifests

Every state-mutating stage execution must produce a durable execution manifest.

Conceptual record:

```yaml
run_id: wf-...
stage: visual-qa
attempt: 2
source_commit_sha: ...
started_at: ...
completed_at: ...

inputs:
  - path: ...
    hash: ...

outputs:
  - path: ...
    hash: ...
    authority: qa

checkpoints:
  - name: capture-complete
    at: ...

validators:
  - name: validate_visual_qa
    status: passed
    evidence_ref: ...

rulings: []
deviations: []
```

## Manifest rules

- Inputs and outputs must be explicitly attributable to a stage attempt.
- Hashing is used for identity/change detection, not as a security guarantee.
- Immutable domain records (e.g. approvals) are referenced, not rewritten into workflow state.
- Generated build artifacts may be referenced without being committed when repository policy says they are ephemeral.
- A completed stage manifest is append-only/frozen except for explicitly permitted operational indexing.

---

# 4. Atomic execution and failure semantics

A stage execution follows:

```text
validate prerequisites
→ acquire client workflow lease
→ create attempt
→ execute atomic step(s)
→ validate outputs
→ persist attempt evidence
→ commit checkpoint transition
→ release lease
```

## Failure rule

```text
failure before completion gate
→ canonical stage pointer unchanged
→ last known-good checkpoint preserved
→ failure evidence recorded
→ retry/resume possible
```

No operation may report a stage as completed merely because files were partially written.

Where the repository/file system cannot provide a true multi-file transaction, the runtime must use ordered writes and reconciliation rules that preserve recoverability.

---

# 5. Idempotency

The runtime must distinguish three behaviors:

### 5.1 Reconcile/reuse
If inputs and outputs already satisfy the same stage contract and validators, rerun may return the existing successful result.

### 5.2 Resume
If an earlier attempt stopped after a recognized checkpoint, resume from that checkpoint when safe.

### 5.3 Restart
If evidence is inconsistent, inputs changed materially, or the previous attempt is not safely resumable, create a new attempt while retaining prior history.

## Idempotency rules

- Initializers must continue refusing destructive overwrite.
- A completed stage cannot silently duplicate immutable artifacts.
- Existing immutable records are reused or versioned according to their domain rules.
- A retry uses stable run/attempt semantics and never masquerades as the original successful attempt.
- Idempotency decisions are recorded in the execution manifest.

---

# 6. Client workflow lease / concurrency protection

Only one state-mutating workflow execution may own a client project at a time.

The runtime introduces a lightweight repository-native lease.

Conceptually:

```yaml
lease_id: ...
client_id: ...
owner: opencode-session-...
run_id: ...
acquired_at: ...
expires_at: ...
```

## Lease rules

- State-mutating execution requires a valid lease.
- Read-only inspection does not require ownership.
- Lease acquisition must detect an active conflicting lease.
- Stale leases may be reclaimed only through deterministic expiry/recovery rules.
- Forced/manual lease override requires an audited human override record.
- The lease is workflow coordination, not a distributed-consensus system.

---

# 7. Resume and recovery

A fresh OpenCode session must be able to answer, using repository state only:

1. What client workflow is active?
2. What stage is current?
3. What has completed?
4. What attempt was last running?
5. What checkpoint was last durable?
6. What validators passed/failed?
7. What files/artifacts were produced?
8. What rulings/deviations were made?
9. Is another execution lease active?
10. What is the next legal action?

The runtime should expose a deterministic `resume`/`inspect` operation that produces a machine-readable recommendation such as:

```text
resume stage visual-qa from checkpoint findings-complete
```

or:

```text
restart visual-qa because source inputs changed
```

or:

```text
advance to client-review because the completion gate already passed
```

OpenCode may execute that recommendation but must not infer workflow status from conversation history.

---

# 8. Rulings and deviations

Agent decisions must not disappear into chat history.

## Ruling

A ruling records an ambiguity resolved during execution.

```yaml
id: ruling-...
stage: ...
attempt: ...
actor: ...
at: ...
decision: ...
reason: ...
cost_if_wrong: ...
```

## Deviation

A deviation records execution differing from the preferred path without changing the approved architecture.

Examples:

- preferred reviewer subagent unavailable
- fallback model used
- provider adapter unavailable, offline fixture used
- optional tooling not installed

```yaml
id: deviation-...
expected: ...
actual: ...
reason: ...
impact: ...
```

Rulings and deviations are append-only audit entries within the stage attempt/manifests.

---

# 9. Manual overrides

Manual override is allowed only when unavoidable and must be explicit.

Required fields:

- actor
- timestamp
- affected stage/gate/lease
- reason
- previous state
- requested new state/action
- evidence or acknowledgement of risk

Overrides must never silently edit immutable domain authorities such as ApprovalSnapshot, QAFinding history, FeedbackRecord history, or ProductionAuthorization.

---

# 10. Validation gates

Every stage has explicit prerequisite and completion validators.

The runtime must distinguish:

```text
prerequisite validator
→ determines whether execution may start

step/checkpoint validator
→ determines whether intermediate output can be considered durable

completion validator
→ determines whether stage may advance
```

A validator result should be structured:

```yaml
name: validate_visual_qa
status: passed
at: ...
source_commit_sha: ...
evidence_ref: ...
```

## Validator authority

Validators prove structural/technical conditions. They do not replace human authorities.

Examples:

- C.5 ApprovalSnapshot remains approval authority.
- D `QAFinding` remains automated QA authority.
- reviewer remains promotion/blocking/resolve authority.
- later ProductionAuthorization remains release-permission authority.

---

# 11. CI relationship

CI validates repository integrity and workflow contracts.

CI may fail when:

- state schema is invalid
- stage metadata conflicts with workflow contract
- immutable manifests are malformed
- required validator declarations are missing
- workflow transition graph is invalid
- committed reference-client state is inconsistent

CI does not:

- advance `workflow-state.yaml`
- acquire runtime ownership on behalf of OpenCode
- close review rounds
- approve experiences
- grant production authorization

CI is evidence, not authority.

---

# 12. OpenCode orchestration contract

OpenCode should operate from a deterministic runtime interface rather than manually editing workflow YAML.

Conceptual operations:

```text
inspect(client)
next(client)
start_stage(client, stage)
checkpoint(run, name)
complete_stage(run)
fail_stage(run, error)
resume(client)
release(client)
record_ruling(run, ...)
record_deviation(run, ...)
override(...)
```

Exact function names are implementation details.

The important boundary is:

```text
OpenCode decides/executes work
Workflow Runtime validates and persists workflow transitions
```

OpenCode must not directly write a fake `completed` state around runtime guardrails.

---

# 13. Integration with Milestones C and D

Milestone E orchestrates but does not absorb domain authorities.

```text
Workflow Runtime
   │
   ├─ build-prototype → Flutter/runtime authority
   ├─ visual-qa → QaCoordinator / QAFinding authority
   ├─ client-review → ReviewCoordinator / FeedbackRecord authority
   ├─ refinement → RefinementBatch authority
   └─ approval → ApprovalSnapshot authority
```

The workflow manifest may reference IDs/hashes/versions from these systems, but must not duplicate their mutable business state.

---

# 14. Workflow evolution toward later stages

The hardened runtime must leave clean extension seams for:

```text
F. End-to-End Reference Client
G. Production Authorization
H. Productionization
```

Specifically:

- F can exercise the whole state/resume model as a canonical regression fixture.
- G can add a production-authorization gate without treating approval as release permission.
- H can add staging/release steps without bypassing workflow evidence.

Milestone E itself does not implement F/G/H.

---

# 15. Error model

Use stable typed workflow-domain errors rather than free-form failure strings.

Representative errors:

```text
InvalidWorkflowState
InvalidStageTransition
StagePrerequisiteFailed
StageCompletionGateFailed
WorkflowLeaseConflict
WorkflowLeaseExpired
CheckpointConflict
ArtifactManifestMismatch
ResumeNotSafe
ManualOverrideRequired
StageContractConflict
```

Errors must be deterministic enough for tests and orchestration logic to branch safely.

---

# 16. Testing strategy

## Domain tests

- state normalization/versioning
- legal/illegal transitions
- typed errors
- lease lifecycle
- checkpoint lifecycle
- attempt lifecycle
- idempotent reruns
- resume/restart decisions
- rulings/deviations
- override audit

## Repository/persistence tests

- atomic write/reconciliation behavior
- stale lease recovery
- append-only completed manifests
- hash/change detection
- crash/interruption fixtures

## Integration tests

Prove at least:

```text
initialize client
→ intake
→ resolve intelligence
→ directions
→ prototype
→ visual QA
→ simulated interruption
→ fresh-session inspect
→ resume from checkpoint
→ complete QA
→ client review
```

Also prove:

```text
active lease
→ competing mutation rejected
→ lease expires/recovered
→ execution resumes safely
```

and:

```text
stage completes
→ same inputs rerun
→ existing valid result reconciled
→ no duplicate immutable artifact
```

## Regression

All existing workflow, knowledge, prototype, C, and D validators/tests remain green.

---

# 17. Implementation packaging

Milestone E should be executed in three large SDD cycles.

## Cycle 1 — State Machine + Contracts

- workflow state v2 / normalization
- stage attempts
- machine-readable stage contracts
- prerequisites/completion gates
- execution/artifact manifests
- typed errors

## Cycle 2 — Idempotency + Recovery

- leases/concurrency protection
- checkpointing
- resume/restart/reconcile decisions
- failure recovery
- rulings/deviations
- manual overrides

## Cycle 3 — OpenCode Integration + Hardening

- runtime orchestration API/CLI
- stage-contract/validator integration
- CI validators
- end-to-end interruption/resume tests
- existing workflow migration/docs
- final architecture/regression review

Each cycle uses TDD, a fresh implementer, an independent reviewer, and fix/re-review before acceptance.

---

# 18. Acceptance criteria

Milestone E is complete when:

1. `workflow-state.yaml` remains canonical and supports hardened execution state.
2. Existing client state is deterministically readable/migratable.
3. Stage transitions require explicit validated prerequisites/completion gates.
4. Every state-mutating stage run has an identifiable attempt and execution manifest.
5. Failed attempts cannot advance the canonical workflow checkpoint.
6. Safe retry/reconcile/resume behavior is deterministic.
7. One active state-mutating lease per client is enforced.
8. Stale lease recovery is deterministic and audited.
9. Rulings and deviations persist outside chat history.
10. Manual overrides are explicit and audited.
11. OpenCode uses runtime operations rather than bypassing state guardrails.
12. CI validates contracts/state but cannot advance workflow state.
13. C.3–C.7 and D.1–D.4 authorities remain unchanged.
14. End-to-end tests prove interruption → fresh-session resume.
15. Full existing validation suite remains green.
16. No generic workflow/BPM platform is introduced.

## Final authority model

```text
GitHub
= durable institutional state

workflow-state.yaml
= live workflow checkpoint authority

workflow attempt/manifests
= workflow execution/audit evidence

workflows/*.md
= stage instruction authority

OpenCode
= executor/orchestrator

validators
= technical completion evidence

C/D domain records
= review / approval / refinement / QA authorities
```
