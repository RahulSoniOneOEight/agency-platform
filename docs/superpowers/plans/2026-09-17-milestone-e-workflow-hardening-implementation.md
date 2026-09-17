# Milestone E — Workflow Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the existing repository-driven Workflow Runtime so every client run is resumable, deterministic, idempotent, auditable, validator-gated, concurrency-safe, and recoverable from repository state alone.

**Architecture:** Extend the existing `tooling/workflow/` runtime rather than replacing it. `workflow-state.yaml` remains the canonical live checkpoint; `workflows/*.md` remain the executable stage contracts; machine-readable stage metadata, execution manifests, leases, rulings/deviations, and recovery helpers provide deterministic orchestration around those authorities. CI validates contracts and repository state but never becomes the workflow authority.

**Tech Stack:** Python 3.12, PyYAML, JSON Schema where already used, repository-native YAML/JSON artifacts, unittest-based validator suite, GitHub Actions, existing Flutter/C.3–C.7/D.1–D.4 validators.

**Spec:** `docs/superpowers/specs/2026-09-17-milestone-e-workflow-hardening-design.md`

## Global Constraints

- `client-projects/<client>/workflow-state.yaml` remains the canonical live workflow checkpoint.
- `workflows/*.md` remain executable stage contracts and continue to declare `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, and `NEXT`.
- Machine-readable stage metadata may make prerequisites/gates deterministic but must not become a hidden parallel business-instruction source.
- Invalid or failed execution must not advance the canonical stage pointer.
- A fresh OpenCode session must be able to resume from repository state alone.
- Re-running a stage must be idempotent unless the stage explicitly creates a new immutable version.
- Completed execution manifests are append-only/frozen except for explicitly permitted operational indexing.
- Only one state-mutating workflow execution may own a client project at a time.
- Human overrides must record actor, reason, timestamp, and affected gate.
- Agent rulings, deviations, model/tool fallbacks, and recovery decisions must be durable records.
- CI validates workflow contracts/artifacts; CI does not own workflow state transitions.
- C.3–C.7 review/refinement/approval authorities and D.1–D.4 QA authorities remain unchanged.
- Do not build a generic BPM engine, distributed queue, autonomous approval system, or production deployment engine.
- Preserve existing version-1 workflow state through deterministic read/migration compatibility where practical.
- Do not change the existing `pubspec.lock` policy.

---

## Planned File Structure

### Existing files to modify

- `tooling/workflow/state.py` — workflow-state v2 normalization, atomic writes, state invariants.
- `tooling/workflow/router.py` — route from normalized state + stage contracts without taking ownership of completion evidence.
- `tooling/workflow/validate_workflow.py` — validate v1/v2 state, stage metadata, manifests, leases, and authority consistency.
- `tooling/workflow/initialize_client.py` — initialize current workflow-state format and execution directories.
- `tooling/validation/test_workflow_runtime.py` — expand canonical runtime tests.
- `tooling/validation/validate_repo.py` — require new hardening files/schemas.
- `.github/workflows/validate.yml` — run hardened workflow validators in CI.
- `docs/workflow-runtime.md` — document resume/retry/lease/manifest operating model.
- `AGENTS.md` — point OpenCode to repository-state resume and stage-run commands where current structure permits.

### New runtime modules

- `tooling/workflow/contracts.py` — load and validate machine-readable stage contracts and compare them with Markdown stage contracts.
- `tooling/workflow/execution.py` — start/resume/complete/fail stage attempts and enforce transition ordering.
- `tooling/workflow/manifests.py` — execution manifest model, canonical hashing, freeze/validation helpers.
- `tooling/workflow/lease.py` — client workflow lease acquire/renew/release/reconcile logic.
- `tooling/workflow/audit.py` — typed ruling/deviation/override records.
- `tooling/workflow/recovery.py` — inspect incomplete attempts and derive deterministic resume/retry action.
- `tooling/workflow/runner.py` — thin orchestration façade used by OpenCode/CLI; no domain work hidden here.

### New schemas/contracts

- `client-projects/schema/workflow-state.schema.json`
- `client-projects/schema/workflow-stage-contract.schema.json`
- `client-projects/schema/workflow-execution-manifest.schema.json`
- `client-projects/schema/workflow-audit-record.schema.json`
- `workflows/contracts/01-client-intake.yaml`
- `workflows/contracts/02-resolve-intelligence.yaml`
- `workflows/contracts/03-resource-research.yaml`
- `workflows/contracts/04-generate-directions.yaml`
- `workflows/contracts/05-build-prototype.yaml`
- `workflows/contracts/06-visual-qa.yaml`
- `workflows/contracts/07-client-review.yaml`
- `workflows/contracts/08-productionize.yaml`

### New focused tests

- `tooling/validation/test_workflow_state_v2.py`
- `tooling/validation/test_workflow_contracts.py`
- `tooling/validation/test_workflow_manifests.py`
- `tooling/validation/test_workflow_lease.py`
- `tooling/validation/test_workflow_recovery.py`
- `tooling/validation/test_workflow_runner.py`
- `tooling/validation/test_workflow_resume_e2e.py`

---

# Cycle 1 — Workflow State Machine + Contracts + Manifests

### Task 1: Harden state, stage contracts, completion evidence, and transition gates

**Files:**
- Modify: `tooling/workflow/state.py`
- Modify: `tooling/workflow/router.py`
- Modify: `tooling/workflow/validate_workflow.py`
- Modify: `tooling/workflow/initialize_client.py`
- Create: `tooling/workflow/contracts.py`
- Create: `tooling/workflow/execution.py`
- Create: `tooling/workflow/manifests.py`
- Create: `client-projects/schema/workflow-state.schema.json`
- Create: `client-projects/schema/workflow-stage-contract.schema.json`
- Create: `client-projects/schema/workflow-execution-manifest.schema.json`
- Create: `workflows/contracts/01-client-intake.yaml`
- Create: `workflows/contracts/02-resolve-intelligence.yaml`
- Create: `workflows/contracts/03-resource-research.yaml`
- Create: `workflows/contracts/04-generate-directions.yaml`
- Create: `workflows/contracts/05-build-prototype.yaml`
- Create: `workflows/contracts/06-visual-qa.yaml`
- Create: `workflows/contracts/07-client-review.yaml`
- Create: `workflows/contracts/08-productionize.yaml`
- Test: `tooling/validation/test_workflow_state_v2.py`
- Test: `tooling/validation/test_workflow_contracts.py`
- Test: `tooling/validation/test_workflow_manifests.py`
- Modify: `tooling/validation/test_workflow_runtime.py`

**Interfaces:**
- Consumes: existing `STAGES`, existing v1 `workflow-state.yaml`, existing `next_stage(root, client_dir, state)`, existing numbered Markdown workflows, existing validators and domain artifacts.
- Produces: `normalize_state(data, client_id=None) -> dict`, `save_state_atomic(path, state) -> None`, `load_stage_contract(root, stage) -> StageContract`, `validate_stage_contracts(root) -> list[str]`, `ExecutionManifest`, `start_attempt(...)`, `record_checkpoint(...)`, `complete_attempt(...)`, `fail_attempt(...)`, and validator-backed completion evidence consumed by Cycles 2 and 3.

- [ ] **Step 1: Write failing v2-state compatibility tests**

Add tests that prove:

```python
class WorkflowStateV2Tests(unittest.TestCase):
    def test_v1_state_normalizes_without_losing_completed_and_skipped(self):
        state = {
            "version": 1,
            "client_id": "demo",
            "current_stage": "visual-qa",
            "status": "in_progress",
            "completed": ["client-intake", "resolve-intelligence"],
            "skipped": [{"stage": "resource-research", "reason": "not-required"}],
            "pending": [],
            "blocked": [],
            "last_updated": "2026-09-17",
        }
        normalized = normalize_state(state)
        self.assertEqual(2, normalized["version"])
        self.assertEqual("visual-qa", normalized["current_stage"])
        self.assertEqual(state["completed"], normalized["completed"])
        self.assertEqual(state["skipped"], normalized["skipped"])
        self.assertIn("stage_state", normalized)

    def test_invalid_current_stage_is_rejected(self):
        with self.assertRaises(WorkflowStateError):
            normalize_state({"version": 2, "client_id": "demo", "current_stage": "bogus"})

    def test_atomic_save_never_exposes_partial_yaml(self):
        # save to a temp directory, reload immediately, and assert exact normalized content
        ...
```

The actual test must use `tempfile.TemporaryDirectory()` rather than a placeholder body.

- [ ] **Step 2: Run the focused state test and confirm RED**

Run:

```bash
py -3.12 -m unittest tooling.validation.test_workflow_state_v2 -v
```

Expected: FAIL because `normalize_state`, `WorkflowStateError`, v2 fields, and atomic save do not exist yet.

- [ ] **Step 3: Implement workflow-state v2 normalization and atomic persistence**

In `tooling/workflow/state.py`:

```python
CURRENT_VERSION = 2
WORKFLOW_STATUSES = {"not_started", "in_progress", "blocked", "complete"}
STAGE_ATTEMPT_STATUSES = {
    "not_started", "in_progress", "blocked", "failed", "complete"
}

class WorkflowStateError(ValueError):
    pass


def normalize_state(data: dict[str, Any], client_id: str | None = None) -> dict[str, Any]:
    """Return canonical v2 state from supported v1/v2 input without mutating input."""


def save_state_atomic(path: Path, state: dict[str, Any]) -> None:
    """Write canonical YAML through a same-directory temporary file + os.replace."""
```

Canonical v2 must include at minimum:

```yaml
version: 2
client_id: demo
workflow: standard-agency
current_stage: client-intake
status: not_started
completed: []
skipped: []
pending: []
blocked: []
stage_state: {}
active_lease: null
last_transition: null
last_updated: 2026-09-17
```

Preserve current `load_state()`/`save_state()` call sites by making them normalize/delegate rather than forcing unrelated modules to change all at once.

- [ ] **Step 4: Add and test the v2 workflow-state schema**

Create `client-projects/schema/workflow-state.schema.json` with strict top-level keys, valid stage/status enums, nullable `active_lease`, `stage_state` keyed only by canonical stage names, and compatibility fields required by the runtime.

Add schema-validation tests to `test_workflow_state_v2.py` and run:

```bash
py -3.12 -m unittest tooling.validation.test_workflow_state_v2 -v
```

Expected: PASS.

- [ ] **Step 5: Write failing stage-contract parity tests**

In `test_workflow_contracts.py`, assert:

```python
self.assertEqual(set(STAGES), {c.stage for c in load_all_stage_contracts(root)})
self.assertEqual([], validate_stage_contracts(root))
```

Also test that a fixture with `next: [client-review]` while the Markdown `NEXT` points elsewhere returns a deterministic conflict error, and that missing `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, or `NEXT` in Markdown fails contract validation.

- [ ] **Step 6: Run the contract test and confirm RED**

```bash
py -3.12 -m unittest tooling.validation.test_workflow_contracts -v
```

Expected: FAIL because machine-readable contracts and parity validation do not exist.

- [ ] **Step 7: Implement `StageContract` loading and Markdown parity checks**

In `tooling/workflow/contracts.py`, define focused immutable structures:

```python
@dataclass(frozen=True)
class StageContract:
    stage: str
    version: int
    requires_stages: tuple[str, ...]
    requires_artifacts: tuple[str, ...]
    produces: tuple[str, ...]
    validators: tuple[str, ...]
    checkpoints: tuple[str, ...]
    next_stages: tuple[str, ...]


def load_stage_contract(root: Path, stage: str) -> StageContract: ...
def load_all_stage_contracts(root: Path) -> list[StageContract]: ...
def validate_stage_contracts(root: Path) -> list[str]: ...
```

The parity validator must verify metadata consistency with the corresponding numbered Markdown workflow without interpreting prose as executable code.

- [ ] **Step 8: Add all eight machine-readable stage contracts**

Encode only deterministic prerequisites/produces/validators/checkpoints/next-stage metadata already supported by the repository. Do not invent new business requirements in YAML.

For example, `workflows/contracts/06-visual-qa.yaml` should identify `build-prototype` as a prerequisite and reference the existing screenshot/visual-QA artifacts and validators introduced in Milestone D.

- [ ] **Step 9: Write failing execution-manifest tests**

In `test_workflow_manifests.py`, test:

```python
manifest = ExecutionManifest.start(
    run_id="wf-demo-001",
    client_id="demo",
    stage="visual-qa",
    attempt=2,
    source_commit_sha="a" * 40,
    inputs=[ArtifactRef(path="prototype/prototype-manifest.yaml", sha256="b" * 64)],
)
self.assertEqual("in_progress", manifest.status)
completed = manifest.with_checkpoint("capture-complete", at="2026-09-17T10:00:00Z")
self.assertEqual("capture-complete", completed.checkpoints[-1].name)
```

Also prove:
- an output path cannot appear twice with conflicting hashes;
- a completed manifest rejects further mutation;
- a completion without all required validators passing is rejected;
- hashes are deterministic for unchanged bytes.

- [ ] **Step 10: Run manifest tests and confirm RED**

```bash
py -3.12 -m unittest tooling.validation.test_workflow_manifests -v
```

- [ ] **Step 11: Implement manifest domain and hashing helpers**

In `tooling/workflow/manifests.py`, define frozen dataclasses/value objects for:

```python
ArtifactRef
CheckpointRecord
ValidatorEvidence
ExecutionManifest
```

Provide:

```python
def sha256_file(path: Path) -> str: ...
def write_manifest_create_only(path: Path, manifest: ExecutionManifest) -> None: ...
def load_manifest(path: Path) -> ExecutionManifest: ...
```

`write_manifest_create_only` must reject overwriting an existing completed manifest.

- [ ] **Step 12: Write failing transition-gate tests**

Extend `test_workflow_runtime.py` to prove:
- `current_stage` does not advance when required output is missing;
- completion does not advance when a required validator is failed/missing;
- state can record a failed attempt while preserving the previous stage pointer;
- valid completion writes evidence first and only then advances state;
- router still honors existing C/D artifact gates.

- [ ] **Step 13: Implement execution transition service**

In `tooling/workflow/execution.py`, provide a small service API:

```python
def start_attempt(root: Path, client_dir: Path, state: dict[str, Any], *, actor: str, source_commit_sha: str) -> tuple[dict[str, Any], ExecutionManifest]: ...

def record_checkpoint(manifest: ExecutionManifest, name: str, *, at: str) -> ExecutionManifest: ...

def fail_attempt(state: dict[str, Any], manifest: ExecutionManifest, *, reason: str, at: str) -> tuple[dict[str, Any], ExecutionManifest]: ...

def complete_attempt(root: Path, client_dir: Path, state: dict[str, Any], manifest: ExecutionManifest, *, validator_results: tuple[ValidatorEvidence, ...], at: str) -> tuple[dict[str, Any], ExecutionManifest]: ...
```

`complete_attempt` must validate required outputs + validators using the stage contract, freeze the manifest, and only then return the advanced state candidate. Persistence ordering must be manifest/evidence first, canonical state pointer second.

- [ ] **Step 14: Update initializer and workflow validator**

`initialize_client.py` should create canonical v2 state and the directory used for execution manifests (e.g. `workflow/executions/`) without creating fake successful runs.

`validate_workflow.py` must accept supported v1/v2 state, report migration/shape errors deterministically, validate stage contracts, and validate referenced completed manifests where present.

- [ ] **Step 15: Run Cycle 1 focused + canonical tests**

```bash
py -3.12 -m unittest \
  tooling.validation.test_workflow_state_v2 \
  tooling.validation.test_workflow_contracts \
  tooling.validation.test_workflow_manifests \
  tooling.validation.test_workflow_runtime -v
py -3.12 -m tooling.workflow.validate_workflow
```

Expected: all PASS.

- [ ] **Step 16: Commit Cycle 1 in logical commits**

Suggested commit sequence:

```bash
git add tooling/workflow/state.py client-projects/schema/workflow-state.schema.json tooling/validation/test_workflow_state_v2.py
git commit -m "feat: harden workflow state v2"

git add tooling/workflow/contracts.py workflows/contracts client-projects/schema/workflow-stage-contract.schema.json tooling/validation/test_workflow_contracts.py
git commit -m "feat: add deterministic workflow stage contracts"

git add tooling/workflow/manifests.py tooling/workflow/execution.py client-projects/schema/workflow-execution-manifest.schema.json tooling/workflow/router.py tooling/workflow/validate_workflow.py tooling/workflow/initialize_client.py tooling/validation/test_workflow_manifests.py tooling/validation/test_workflow_runtime.py
git commit -m "feat: add validator-gated workflow execution manifests"
```

- [ ] **Step 17: Independent Cycle 1 review**

Reviewer must specifically check v1 compatibility, no hidden business logic in metadata, manifest immutability, evidence-before-state ordering, router compatibility with C/D, and no stage-pointer advancement on failure. Fix all blocker/major findings and re-review before Cycle 2.

---

# Cycle 2 — Idempotency + Lease + Resume/Recovery + Audit

### Task 2: Make state-mutating executions single-owner, retry-safe, resumable, and auditable

**Files:**
- Create: `tooling/workflow/lease.py`
- Create: `tooling/workflow/audit.py`
- Create: `tooling/workflow/recovery.py`
- Modify: `tooling/workflow/execution.py`
- Modify: `tooling/workflow/manifests.py`
- Modify: `tooling/workflow/state.py`
- Create: `client-projects/schema/workflow-audit-record.schema.json`
- Test: `tooling/validation/test_workflow_lease.py`
- Test: `tooling/validation/test_workflow_recovery.py`
- Modify: `tooling/validation/test_workflow_manifests.py`
- Modify: `tooling/validation/test_workflow_runtime.py`

**Interfaces:**
- Consumes: Cycle 1 normalized v2 state, `ExecutionManifest`, stage contracts, attempt lifecycle.
- Produces: `WorkflowLease`, `acquire_lease`, `renew_lease`, `release_lease`, `reconcile_expired_lease`, `AuditRecord`, `RecoveryDecision`, `inspect_recovery`, and idempotent attempt behavior consumed by Cycle 3 runner/orchestration.

- [ ] **Step 1: Write failing lease tests**

In `test_workflow_lease.py`, prove:

```python
lease = acquire_lease(state, owner="opencode:session-a", now=NOW, ttl_seconds=1800)
self.assertEqual("opencode:session-a", lease.owner)
with self.assertRaises(WorkflowLeaseConflict):
    acquire_lease(state_with_active_lease, owner="opencode:session-b", now=NOW, ttl_seconds=1800)
```

Also test:
- same owner/run can idempotently reacquire/renew;
- expired lease can be reconciled but records a recovery/audit event;
- release requires matching lease ID/owner;
- lease timestamps are UTC ISO-8601 strings;
- no lease mutation advances the workflow stage.

- [ ] **Step 2: Run lease tests and confirm RED**

```bash
py -3.12 -m unittest tooling.validation.test_workflow_lease -v
```

- [ ] **Step 3: Implement lease domain**

In `tooling/workflow/lease.py`:

```python
@dataclass(frozen=True)
class WorkflowLease:
    lease_id: str
    owner: str
    run_id: str
    acquired_at: str
    expires_at: str

class WorkflowLeaseConflict(RuntimeError): ...
class WorkflowLeaseOwnershipError(RuntimeError): ...


def acquire_lease(state: dict, *, owner: str, run_id: str, now: datetime, ttl_seconds: int = 1800) -> tuple[dict, WorkflowLease]: ...
def renew_lease(state: dict, lease: WorkflowLease, *, now: datetime, ttl_seconds: int = 1800) -> tuple[dict, WorkflowLease]: ...
def release_lease(state: dict, lease: WorkflowLease) -> dict: ...
def reconcile_expired_lease(state: dict, *, now: datetime) -> tuple[dict, WorkflowLease | None]: ...
```

Keep lease state inside `workflow-state.yaml`; do not introduce an external coordination service.

- [ ] **Step 4: Write failing audit-record tests**

Add tests that require exact structured record kinds:

```text
ruling
deviation
override
recovery
```

Each record must include:

```text
id, kind, actor, at, stage, run_id, summary, reason
```

and kind-specific details. Overrides additionally require `affected_gate`. Deviations additionally allow requested/actual model/tool/agent metadata.

- [ ] **Step 5: Implement immutable audit records**

In `tooling/workflow/audit.py`, provide:

```python
@dataclass(frozen=True)
class AuditRecord: ...

def make_ruling(...)->AuditRecord: ...
def make_deviation(...)->AuditRecord: ...
def make_override(...)->AuditRecord: ...
def make_recovery_record(...)->AuditRecord: ...
def append_audit_record(path: Path, record: AuditRecord) -> None: ...
```

Use JSONL or an append-only per-run YAML/JSON record layout consistent with the repository; never edit an existing record in place.

- [ ] **Step 6: Add the audit-record schema and validation tests**

Create `client-projects/schema/workflow-audit-record.schema.json`. Validate actor/reason/timestamp presence and exact enum values. Ensure an override missing `affected_gate` fails.

- [ ] **Step 7: Write failing idempotency tests**

Extend manifest/runtime tests to prove all three behaviors:

1. **Reconcile/reuse** — same stage + same relevant input hashes + already valid completed outputs returns existing completion evidence and does not create a duplicate immutable result.
2. **Resume** — same run/attempt with a recognized completed checkpoint resumes from the next atomic step.
3. **New attempt** — changed relevant inputs or prior failed attempt creates a new attempt number without rewriting prior attempt evidence.

Use deterministic fixture files and hashes; do not mock the core idempotency decision itself.

- [ ] **Step 8: Implement attempt identity and idempotency decision**

Add to `execution.py`/`manifests.py`:

```python
class IdempotencyAction(str, Enum):
    REUSE = "reuse"
    RESUME = "resume"
    NEW_ATTEMPT = "new_attempt"

@dataclass(frozen=True)
class IdempotencyDecision:
    action: IdempotencyAction
    run_id: str
    attempt: int
    reason: str


def decide_idempotency(contract: StageContract, prior_manifests: Sequence[ExecutionManifest], current_inputs: Sequence[ArtifactRef]) -> IdempotencyDecision: ...
```

Input identity must derive from canonical paths + hashes relevant to the stage contract, not from wall-clock time.

- [ ] **Step 9: Write failing recovery tests**

In `test_workflow_recovery.py`, cover:
- lease expired + manifest in progress + checkpoint present => resumable;
- lease expired + manifest in progress + no safe checkpoint => retry/new attempt;
- completed manifest + stale state pointer => reconcile state forward only after re-validating evidence;
- state claims complete but manifest/evidence missing => block and do not fabricate completion;
- partial output with failed manifest => preserve failure evidence and do not treat output existence as success.

- [ ] **Step 10: Implement deterministic recovery inspection**

In `tooling/workflow/recovery.py`:

```python
class RecoveryAction(str, Enum):
    NONE = "none"
    RESUME = "resume"
    RETRY = "retry"
    RECONCILE_STATE = "reconcile_state"
    BLOCK = "block"

@dataclass(frozen=True)
class RecoveryDecision:
    action: RecoveryAction
    stage: str
    run_id: str | None
    attempt: int | None
    checkpoint: str | None
    reason: str


def inspect_recovery(root: Path, client_dir: Path, state: dict[str, Any], *, now: datetime) -> RecoveryDecision: ...
```

The function may propose reconciliation but must not silently mutate persisted state.

- [ ] **Step 11: Wire lease and audit into execution ordering**

State-mutating stage execution ordering becomes:

```text
validate prerequisites
→ reconcile/deny stale lease
→ acquire lease
→ calculate idempotency decision
→ start/resume attempt
→ execute step(s)
→ validate outputs
→ write/freeze manifest evidence
→ save canonical state transition
→ release lease
```

On failure, append failure/recovery evidence and release or expire ownership without advancing `current_stage`.

- [ ] **Step 12: Run Cycle 2 focused regression suite**

```bash
py -3.12 -m unittest \
  tooling.validation.test_workflow_lease \
  tooling.validation.test_workflow_recovery \
  tooling.validation.test_workflow_manifests \
  tooling.validation.test_workflow_runtime -v
```

Expected: all PASS.

- [ ] **Step 13: Commit Cycle 2 in logical commits**

```bash
git add tooling/workflow/lease.py tooling/validation/test_workflow_lease.py
git commit -m "feat: add client workflow execution leases"

git add tooling/workflow/audit.py client-projects/schema/workflow-audit-record.schema.json tooling/validation/test_workflow_runtime.py
git commit -m "feat: persist workflow rulings and deviations"

git add tooling/workflow/recovery.py tooling/workflow/execution.py tooling/workflow/manifests.py tooling/workflow/state.py tooling/validation/test_workflow_recovery.py tooling/validation/test_workflow_manifests.py
git commit -m "feat: add idempotent workflow resume and recovery"
```

- [ ] **Step 14: Independent Cycle 2 review**

Reviewer must test concurrency ownership, stale lease handling, recovery after interruption between evidence and state writes, no fabricated completion, append-only audit history, exact override metadata, and deterministic idempotency. Fix all blocker/major findings and re-review before Cycle 3.

---

# Cycle 3 — OpenCode Orchestration + Validator/CI Hardening + E2E Resume

### Task 3: Expose a thin resumable runner, harden repository validation, and prove fresh-session continuation

**Files:**
- Create: `tooling/workflow/runner.py`
- Modify: `tooling/workflow/router.py`
- Modify: `tooling/workflow/validate_workflow.py`
- Modify: `tooling/validation/validate_repo.py`
- Create: `tooling/validation/test_workflow_runner.py`
- Create: `tooling/validation/test_workflow_resume_e2e.py`
- Modify: `.github/workflows/validate.yml`
- Modify: `docs/workflow-runtime.md`
- Modify: `AGENTS.md`
- Modify: relevant `workflows/*.md` only where necessary to reference hardened execution commands/contracts without changing their business meaning.

**Interfaces:**
- Consumes: Cycle 1 state/contracts/manifests and Cycle 2 leases/audit/recovery/idempotency.
- Produces: a thin CLI/API used by OpenCode to inspect/start/checkpoint/fail/complete/resume stage executions and a full repository/CI gate proving the runtime can recover across fresh sessions.

- [ ] **Step 1: Write failing runner tests**

In `test_workflow_runner.py`, exercise the public orchestration surface instead of directly manipulating YAML:

```python
status = inspect_client(root, client_dir)
self.assertEqual("client-intake", status.current_stage)

started = start_stage(root, client_dir, actor="opencode:test", source_commit_sha="a" * 40)
self.assertEqual("in_progress", started.manifest.status)

status_after = inspect_client(root, client_dir)
self.assertEqual(started.manifest.run_id, status_after.active_run_id)
```

Also test deterministic errors for:
- second owner while lease active;
- starting a stage whose prerequisites are blocked;
- completing before validators pass;
- resuming after expired lease/incomplete attempt;
- requesting next stage after workflow complete.

- [ ] **Step 2: Run runner tests and confirm RED**

```bash
py -3.12 -m unittest tooling.validation.test_workflow_runner -v
```

- [ ] **Step 3: Implement thin `runner.py` façade**

Provide explicit entry points:

```python
def inspect_client(root: Path, client_dir: Path) -> WorkflowRunStatus: ...
def start_stage(root: Path, client_dir: Path, *, actor: str, source_commit_sha: str) -> StageRun: ...
def checkpoint_stage(root: Path, client_dir: Path, *, run_id: str, checkpoint: str, actor: str) -> StageRun: ...
def fail_stage(root: Path, client_dir: Path, *, run_id: str, reason: str, actor: str) -> StageRun: ...
def complete_stage(root: Path, client_dir: Path, *, run_id: str, actor: str, validator_results: tuple[ValidatorEvidence, ...]) -> StageRun: ...
def resume_stage(root: Path, client_dir: Path, *, actor: str, source_commit_sha: str) -> StageRun: ...
```

The runner orchestrates existing domain modules. It must not contain client-specific business logic or directly approve review/QA/production decisions.

Optionally expose a small argparse CLI around these exact operations if that follows existing repository conventions.

- [ ] **Step 4: Write the end-to-end interruption/resume tests first**

In `test_workflow_resume_e2e.py`, build a temporary client fixture and prove these sequences:

### Scenario A — fresh-session normal continuation

```text
initialize client
→ complete client-intake with evidence
→ discard in-memory controller objects
→ reload exclusively from repository files
→ inspect_client returns resolve-intelligence as next legal stage
```

### Scenario B — interruption after checkpoint

```text
start visual-qa
→ record capture-complete checkpoint
→ simulate process death without completion
→ expire/reconcile lease
→ fresh call to resume_stage
→ same run/attempt resumes from capture-complete
→ no duplicate successful immutable record
```

### Scenario C — interruption after completed manifest but before state save

```text
freeze valid completed manifest
→ leave workflow-state at old stage
→ fresh inspect/recovery identifies RECONCILE_STATE
→ revalidate evidence
→ reconcile canonical state exactly once
```

### Scenario D — changed inputs

```text
complete an attempt
→ modify one contract-relevant input
→ rerun
→ NEW_ATTEMPT with incremented attempt
→ old manifest remains unchanged
```

### Scenario E — concurrent ownership

```text
session A acquires lease
→ session B attempts mutation
→ deterministic conflict
→ no state/artifact mutation by B
```

- [ ] **Step 5: Run E2E tests and confirm RED**

```bash
py -3.12 -m unittest tooling.validation.test_workflow_resume_e2e -v
```

- [ ] **Step 6: Wire router/validator to hardened state without changing authority**

`router.py` should consume normalized state and continue returning deterministic readiness/block reasons. It must not declare a stage complete merely from `completed[]`; completed evidence is validated by the execution/validator layer.

`validate_workflow.py` should now check:
- schema-valid state;
- stage contract parity;
- active lease shape/expiry consistency;
- completed stage evidence/manifests;
- referenced audit records;
- no impossible stage-state combinations;
- no state pointer ahead of valid evidence.

- [ ] **Step 7: Harden repository required-path validation**

Add the new runtime modules, schemas, contracts, and tests to `tooling/validation/validate_repo.py` and its own tests. Do not require generated per-client execution manifests to exist globally.

- [ ] **Step 8: Update CI validation**

In `.github/workflows/validate.yml`, add the new workflow-hardening test modules and ensure `python -m tooling.workflow.validate_workflow` remains a required repository gate.

CI must only validate repository state; it must not acquire leases, advance client workflow state, rewrite manifests, or perform recovery mutations.

- [ ] **Step 9: Update OpenCode operating documentation**

Update `docs/workflow-runtime.md` and `AGENTS.md` so a fresh agent is instructed to:

```text
1. read workflow-state.yaml
2. run workflow inspection/recovery
3. read only the current stage contract + declared inputs
4. acquire/start/resume through the workflow runner
5. execute work
6. checkpoint durable atomic steps
7. run declared validators
8. complete through the runner only after gates pass
9. persist ruling/deviation/override records when applicable
10. never edit current_stage manually
```

Include commands using the actual implemented CLI/module entry points; do not document hypothetical commands.

- [ ] **Step 10: Update numbered workflow contracts minimally**

If needed, add a short `RUNTIME`/execution note to each `workflows/*.md` that points to hardened runner usage. Preserve the existing `PURPOSE/READ/PROCESS/WRITE/VALIDATE/DO NOT/NEXT` semantics and ensure parity tests remain green.

- [ ] **Step 11: Run Cycle 3 focused suite**

```bash
py -3.12 -m unittest \
  tooling.validation.test_workflow_runner \
  tooling.validation.test_workflow_resume_e2e \
  tooling.validation.test_workflow_runtime \
  tooling.validation.test_workflow_state_v2 \
  tooling.validation.test_workflow_contracts \
  tooling.validation.test_workflow_manifests \
  tooling.validation.test_workflow_lease \
  tooling.validation.test_workflow_recovery -v
```

Expected: all PASS.

- [ ] **Step 12: Run full canonical verification**

At repository root:

```bash
py -3.12 -m unittest discover tooling/validation -v
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 -m tooling.prototype.validate_prototype
py -3.12 -m tooling.prototype.validate_visual_qa client-projects/examples/prototype-demo
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
py -3.12 -m tooling.design_contract.generate_resolved_themes --check
```

Then run existing Flutter canonical checks because workflow hardening must not regress C/D integration:

```bash
cd apps/prototype_app
flutter test
flutter analyze
flutter build web

cd ../../packages/agency_flutter_ui
flutter test
flutter analyze

cd ../../apps/widgetbook
flutter test
flutter analyze
```

Record exact test counts and command outcomes in the SDD ledger.

- [ ] **Step 13: Commit Cycle 3 in logical commits**

```bash
git add tooling/workflow/runner.py tooling/workflow/router.py tooling/workflow/validate_workflow.py tooling/validation/test_workflow_runner.py tooling/validation/test_workflow_resume_e2e.py
git commit -m "feat: add resumable workflow orchestration runner"

git add tooling/validation/validate_repo.py .github/workflows/validate.yml docs/workflow-runtime.md AGENTS.md workflows
git commit -m "chore: harden workflow validation and operator guidance"
```

- [ ] **Step 14: Independent Cycle 3 review**

Reviewer must verify the runner remains thin, CI cannot mutate workflow state, fresh-session resume is repository-only, stage contracts retain business authority, all concurrency/recovery cases are deterministic, and C/D authority boundaries remain unchanged. Fix all blocker/major findings and re-review.

- [ ] **Step 15: Final whole-branch architectural review**

Review:

```bash
git diff main...HEAD
```

Use the strongest available reasoning model. Explicitly verify:

1. `workflow-state.yaml` remains canonical live checkpoint authority.
2. v1 state remains deterministically readable/migratable where supported.
3. stage completion requires artifact + validator evidence.
4. machine-readable contracts do not hide business instructions.
5. Markdown/metadata conflicts fail validation.
6. state pointer never advances on failed/incomplete execution.
7. manifest completion is frozen/append-only.
8. evidence is persisted before canonical pointer advancement.
9. reruns are deterministic and idempotent.
10. changed relevant inputs create a new attempt instead of mutating prior evidence.
11. safe checkpoints support resume.
12. unsafe partial work results in retry/block, not fabricated success.
13. one active state-mutating owner per client is enforced.
14. stale lease recovery is explicit and audited.
15. manual overrides record actor/reason/time/affected gate.
16. rulings/deviations/recovery are durable append-only records.
17. model/tool fallback can be recorded without becoming workflow logic.
18. OpenCode can resume from repository state without chat memory.
19. runner contains orchestration only, not domain approval logic.
20. CI validates but never owns/mutates workflow state.
21. ReviewState/FeedbackRecord/RefinementBatch/ApprovalSnapshot authority is unchanged.
22. QAFinding/QaCoordinator authority is unchanged.
23. runtime/Design Contract authorities remain unchanged.
24. no generic BPM/distributed queue introduced.
25. no autonomous approval or production authorization introduced.
26. no production deployment engine introduced.
27. no lockfile-policy change.

Target: **0 blockers / 0 majors**. Allow one final fix dispatch + scoped re-review, then adjudicate residual minors in the ledger.

- [ ] **Step 16: Prepare final PR, but do not merge**

Push `milestone-e-workflow-hardening`, open a PR against `main`, and report:

- Cycle 1/2/3 status;
- commits by cycle;
- reviewer findings/fixes;
- rulings/deviations;
- v1→v2 compatibility behavior;
- stage contract architecture;
- manifest/freeze semantics;
- lease/concurrency behavior;
- idempotency/resume/recovery behavior;
- audit/override behavior;
- exact Python/Flutter test counts;
- validator/build results;
- final branch SHA;
- PR number/URL;
- CI status;
- intentionally deferred items.

Do **not** merge without explicit authorization.

---

## Three-Cycle Exit Summary

```text
Cycle 1
workflow-state v2
+ stage contracts
+ manifests
+ validator-gated transitions

Cycle 2
leases
+ idempotency
+ retry/resume/recovery
+ rulings/deviations/overrides

Cycle 3
OpenCode runner
+ repository/CI hardening
+ interruption/resume E2E
+ final integration verification
```

Final operating invariant:

```text
GitHub state + artifacts
        ↓
workflow-state.yaml
        ↓
validated stage contract
        ↓
lease-owned execution attempt
        ↓
checkpoint + manifest evidence
        ↓
validators
        ↓
atomic state transition
        ↓
safe resume / retry / next stage
```
