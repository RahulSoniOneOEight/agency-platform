# Milestone F — End-to-End Reference Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one deterministic synthetic B2C+B2B reference client that proves the complete B–E agency workflow end to end, including directions, Flutter prototype, Compare/Select/Mix, feedback/refinement, ApprovalSnapshot v1/v2, automated visual QA, and interruption/resume evidence.

**Architecture:** Reuse all existing domain authorities and workflow runtime. Add a canonical reference client under `client-projects/reference-commerce/` plus narrow Python orchestration/validation under `tooling/reference_client/`. The fixture may create deterministic test records through existing public domain seams, but it must never create a second review, approval, QA, workflow, or runtime authority.

**Tech Stack:** Python 3.12, YAML/JSON schemas, existing Flutter prototype app, existing C.3–C.7 review/approval/refinement domain, Milestone D visual-QA tooling, Milestone E workflow runtime, GitHub Actions validation.

**Spec:** `docs/superpowers/specs/2026-09-18-milestone-f-reference-client-design.md`

## Global Constraints

- Use only synthetic deterministic data; no PII.
- `workflow-state.yaml` remains the workflow checkpoint authority.
- `ReviewState`, `FeedbackRecord`, `RefinementBatch`, `ApprovalSnapshot`, `QAFinding`, `QaCoordinator`, and `ReviewCoordinator` remain the existing domain authorities.
- The reference fixture is scenario/evidence only; it must not duplicate canonical domain state.
- Three experience directions must be materially different, not theme-only variants.
- The same Flutter runtime and design system must render all directions.
- CI must run deterministically without live Visual AI credentials.
- CI must not auto-create production/client approvals, mutate live workflow state as authority, grant production authorization, or update golden baselines.
- Contract-impacting changes require a new review round and new approval version.
- Implementation-only changes must not force unnecessary reapproval when the approved experience contract is unchanged.
- If change classification is uncertain, classify as contract-impacting.
- Do not implement ProductionAuthorization in Milestone F.
- Do not change `pubspec.lock` policy.
- TDD is mandatory: failing test first, prove failure, implement minimum, prove pass, then commit.

---

# File Structure

Create or extend these focused areas:

```text
client-projects/reference-commerce/
  input/
    client-input.yaml
  derived/
    client-profile.yaml
  directions/
    direction-a.yaml
    direction-b.yaml
    direction-c.yaml
    comparison.yaml
  prototype/
    prototype-manifest.yaml
    qa/
  review/
  approval/
  workflow-state.yaml
  reference-e2e/
    fixture.yaml
    scenario.yaml
    assertions.yaml
    evidence/
    report/

tooling/reference_client/
  __init__.py
  fixture.py
  scenario.py
  assertions.py
  change_scenarios.py
  report.py
  validate_reference_client.py

client-projects/schema/
  reference-client-fixture.schema.json
  reference-client-scenario.schema.json
  reference-client-report.schema.json

tooling/validation/
  test_reference_client_fixture.py
  test_reference_client_scenario.py
  test_reference_client_review_approval.py
  test_reference_client_change_scenarios.py
  test_reference_client_resume_e2e.py
```

Do not move existing C/D/E authorities into this area. `tooling/reference_client/` is orchestration and deterministic assertion logic only.

---

# Cycle F.1 — Reference Client Foundation

## Task 1: Deterministic Reference Fixture Contract

**Files:**
- Create: `client-projects/schema/reference-client-fixture.schema.json`
- Create: `tooling/reference_client/__init__.py`
- Create: `tooling/reference_client/fixture.py`
- Create: `tooling/validation/test_reference_client_fixture.py`
- Create: `client-projects/reference-commerce/reference-e2e/fixture.yaml`

**Interfaces:**
- Produces: `load_fixture(path: Path) -> dict[str, Any]`
- Produces: `validate_fixture(root: Path, client_dir: Path) -> list[str]`
- Produces: stable fixture identity from `client_id + fixture_version + canonical fixture content`
- Later tasks consume the validated fixture only; they must not read ad-hoc random data.

- [ ] **Step 1: Write the failing fixture validation tests**

```python
from pathlib import Path
from tooling.reference_client.fixture import load_fixture, validate_fixture


def test_reference_fixture_is_versioned_and_deterministic(repo_root: Path):
    client = repo_root / "client-projects" / "reference-commerce"
    fixture = load_fixture(client / "reference-e2e" / "fixture.yaml")
    assert fixture["client_id"] == "reference-commerce"
    assert fixture["fixture_version"] == 1
    assert fixture["seed"] == "reference-commerce-v1"
    assert validate_fixture(repo_root, client) == []


def test_reference_fixture_covers_b2c_and_b2b(repo_root: Path):
    fixture = load_fixture(repo_root / "client-projects/reference-commerce/reference-e2e/fixture.yaml")
    assert fixture["coverage"]["b2c"] is True
    assert fixture["coverage"]["b2b"] is True
    assert len(fixture["products"]) >= 12
    assert len(fixture["accounts"]) >= 4
```

- [ ] **Step 2: Run tests and prove failure**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_fixture -v`

Expected: FAIL because the fixture module/schema/client fixture does not exist yet.

- [ ] **Step 3: Implement the fixture contract**

`fixture.yaml` must contain deterministic synthetic data for:
- at least 4 categories/collections
- at least 12 products
- variants and inventory states
- retail price
- B2B quantity breaks
- promotions
- consumer and trade accounts
- credit limits and available credit
- at least 2 RFQs/quotations
- carts/orders
- validation/error states

`fixture.py` must canonicalize mappings/lists deterministically and reject duplicate IDs, missing required entities, invalid credit values, and unknown fixture versions.

- [ ] **Step 4: Run focused tests and repository fixture validation**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_fixture -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client-projects/schema/reference-client-fixture.schema.json tooling/reference_client client-projects/reference-commerce/reference-e2e/fixture.yaml tooling/validation/test_reference_client_fixture.py
git commit -m "feat: add deterministic reference commerce fixture"
```

## Task 2: Canonical Intake, Client Profile, Resources, and Directions

**Files:**
- Create: `client-projects/reference-commerce/input/client-input.yaml`
- Create: `client-projects/reference-commerce/derived/client-profile.yaml`
- Create: `client-projects/reference-commerce/directions/direction-a.yaml`
- Create: `client-projects/reference-commerce/directions/direction-b.yaml`
- Create: `client-projects/reference-commerce/directions/direction-c.yaml`
- Create: `client-projects/reference-commerce/directions/comparison.yaml`
- Create: `client-projects/reference-commerce/resources/reference-selection.yaml`
- Test: `tooling/validation/test_reference_client_scenario.py`

**Interfaces:**
- Consumes: existing client-input, client-profile, resource-selection, and direction schemas/validators.
- Produces three direction IDs: `efficient-commerce`, `premium-discovery`, `trade-first`.
- Produces selected resource provenance consumable by existing prototype generation tooling.

- [ ] **Step 1: Write failing contract tests**

```python
def test_reference_client_has_three_material_directions(repo_root):
    client = repo_root / "client-projects/reference-commerce"
    ids = []
    for name in ("direction-a.yaml", "direction-b.yaml", "direction-c.yaml"):
        data = load_yaml(client / "directions" / name)
        ids.append(data["id"])
    assert ids == ["efficient-commerce", "premium-discovery", "trade-first"]
    assert len(set(ids)) == 3


def test_reference_resource_selection_preserves_provenance(repo_root):
    data = load_yaml(repo_root / "client-projects/reference-commerce/resources/reference-selection.yaml")
    assert all(item.get("source") for item in data["selected"])
    assert all(item.get("normalized_into") for item in data["selected"])
```

- [ ] **Step 2: Run and prove failure**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_scenario -v`

Expected: FAIL because canonical reference-client inputs/directions do not yet exist.

- [ ] **Step 3: Create the client contract and three directions**

Direction semantics must be explicit:
- `efficient-commerce`: compact, search/category led, high density, repeat purchase
- `premium-discovery`: editorial, larger imagery, curated collections, storytelling
- `trade-first`: MOQ/bulk cues, quotation, credit visibility, fast trade ordering

The comparison file must document behavioral/component/composition differences, not only colors.

- [ ] **Step 4: Validate with existing canonical validators**

Run:
`py -3.12 -m tooling.workflow.validate_workflow`
`py -3.12 -m tooling.prototype.validate_prototype`
`py -3.12 -m unittest tooling.validation.test_reference_client_scenario -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client-projects/reference-commerce/input client-projects/reference-commerce/derived client-projects/reference-commerce/resources client-projects/reference-commerce/directions tooling/validation/test_reference_client_scenario.py
git commit -m "feat: add reference client intake resources and directions"
```

## Task 3: Flutter Runtime Coverage for Reference B2C+B2B Journeys

**Files:**
- Modify only existing runtime fixture/data seams under `apps/prototype_app/` required to load `reference-commerce`.
- Modify only existing shared components when a required already-approved capability is missing.
- Test: add/extend focused prototype tests under `apps/prototype_app/test/`.

**Interfaces:**
- Consumes: reference fixture + existing direction/runtime bundle contract.
- Produces deterministic renderability for Home, PLP/category, Search, PDP, Cart, Checkout, B2B RFQ/quotation, credit/account visibility, and order conversion.
- Must use the same Flutter runtime for all directions.

- [ ] **Step 1: Add failing render/navigation tests for the required screens**

Example assertion pattern:

```dart
testWidgets('trade-first exposes quotation and credit paths', (tester) async {
  await pumpReferenceClient(tester, direction: 'trade-first');
  expect(find.text('Request quote'), findsWidgets);
  expect(find.text('Available credit'), findsWidgets);
});
```

- [ ] **Step 2: Run focused Flutter tests and prove failure**

Run from `apps/prototype_app`:
`flutter test test/reference_client`

Expected: FAIL for missing reference fixture/runtime wiring or missing approved flow coverage.

- [ ] **Step 3: Implement only the minimum runtime/fixture wiring required**

Do not create three apps. Direction differences must flow through existing runtime decisions/tokens/pattern variants.

- [ ] **Step 4: Run focused and full prototype checks**

Run:
`flutter test test/reference_client`
`flutter test`
`flutter analyze`
`flutter build web`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/prototype_app client-projects/reference-commerce/prototype
git commit -m "feat: render reference commerce journeys in shared Flutter runtime"
```

## Task 4: Machine Scenario Skeleton and Cycle F.1 Review Gate

**Files:**
- Create: `client-projects/schema/reference-client-scenario.schema.json`
- Create: `client-projects/reference-commerce/reference-e2e/scenario.yaml`
- Create: `client-projects/reference-commerce/reference-e2e/assertions.yaml`
- Create: `tooling/reference_client/scenario.py`
- Create: `tooling/reference_client/assertions.py`
- Extend: `tooling/validation/test_reference_client_scenario.py`

**Interfaces:**
- Produces: `load_scenario(path)`, `validate_scenario(...)`, `evaluate_assertions(...)`.
- Scenario IDs must be exactly:
  - `normal-happy-path`
  - `contract-change-reapproval`
  - `implementation-only-change`
  - `resume-after-interruption`

- [ ] **Step 1: Write failing scenario/assertion tests**

```python
def test_reference_scenario_ids_are_stable(repo_root):
    scenario = load_scenario(repo_root / "client-projects/reference-commerce/reference-e2e/scenario.yaml")
    assert [x["id"] for x in scenario["scenarios"]] == [
        "normal-happy-path",
        "contract-change-reapproval",
        "implementation-only-change",
        "resume-after-interruption",
    ]
```

- [ ] **Step 2: Run and prove failure**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_scenario -v`

- [ ] **Step 3: Implement schema + loader + assertion engine**

Assertions must query canonical artifacts/records; do not duplicate review/approval/QA state into `reference-e2e`.

- [ ] **Step 4: Run all Cycle F.1 tests plus existing validators**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_fixture tooling.validation.test_reference_client_scenario -v`
`py -3.12 -m tooling.workflow.validate_workflow`
`py -3.12 -m tooling.prototype.validate_prototype`

- [ ] **Step 5: Independent reviewer gate**

Reviewer must verify:
- synthetic deterministic fixture
- three materially different directions
- same Flutter runtime
- no authority duplication
- B2C+B2B coverage
- scenario assertions inspect canonical state

Fix blocker/major findings and re-review before Cycle F.2.

---

# Cycle F.2 — Review → Approval v1 → Visual QA

## Task 5: Canonical Compare / Select / Mix Scenario

**Files:**
- Create/extend: `tooling/reference_client/scenario.py`
- Test: `tooling/validation/test_reference_client_review_approval.py`
- Reuse existing C.3 ReviewState/public coordinator interfaces; do not create replacement models.

**Interfaces:**
- Produces deterministic scenario setup with:
  - overall selected direction
  - at least one valid screen override
  - at least one valid governed section override
- Persists through existing ReviewRepository path only.

- [ ] **Step 1: Write failing scenario test**

```python
def test_reference_mix_contract_has_overall_screen_and_section_override(reference_state):
    assert reference_state.selected_direction == "premium-discovery"
    assert reference_state.screen_overrides["search"] == "efficient-commerce"
    assert reference_state.section_overrides["pdp.price"] == "trade-first"
```

Where cross-language setup is required, drive the existing Dart coordinator through a deterministic fixture/test harness and assert the persisted canonical review JSON from Python.

- [ ] **Step 2: Prove failure**

Run the focused Dart/Python test path selected by the existing review persistence seam.

- [ ] **Step 3: Implement deterministic C.3 scenario orchestration**

Do not bypass ReviewState validation or the governed section registry.

- [ ] **Step 4: Run focused C.3 regression suite**

Run from `apps/prototype_app`:
`flutter test test/review`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tooling/reference_client tooling/validation/test_reference_client_review_approval.py client-projects/reference-commerce/review
git commit -m "test: exercise reference client select and mix flow"
```

## Task 6: Feedback, Visual Annotation, Refinement, and ApprovalSnapshot v1

**Files:**
- Extend: `tooling/reference_client/scenario.py`
- Extend: `tooling/validation/test_reference_client_review_approval.py`
- Use existing file-backed review/feedback/refinement/approval repositories.

**Interfaces:**
- Must create through existing canonical seams:
  - one blocking `FeedbackRecord`
  - one non-blocking `FeedbackRecord`
  - one visual annotation feedback item
  - one `RefinementBatch`
  - explicit review round close
  - `ApprovalSnapshot` version 1

- [ ] **Step 1: Write failing acceptance tests**

Required assertions:

```text
blocking feedback prevents approval while open/addressed
successful refinement may move eligible open feedback to addressed
reviewer explicitly resolves/reopens and closes round
approval v1 exists only after ready_for_final_review
approval v1 pins source SHA and review-state hash
```

- [ ] **Step 2: Run focused review tests and prove failure**

Run:
`flutter test test/review`

plus the Python reference scenario test.

- [ ] **Step 3: Implement through ReviewCoordinator / repositories only**

Do not write approval files directly except through the existing ApprovalRepository/coordinator path.

- [ ] **Step 4: Re-run C.4–C.7 tests**

Run:
`flutter test test/review`
`flutter test test/qa`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tooling/reference_client tooling/validation/test_reference_client_review_approval.py client-projects/reference-commerce/review client-projects/reference-commerce/approval
git commit -m "test: prove reference review refinement and approval v1"
```

## Task 7: Milestone D Visual QA Path for the Reference Client

**Files:**
- Extend reference screenshot manifest under `client-projects/reference-commerce/prototype/qa/`
- Extend: `tooling/reference_client/scenario.py`
- Extend: `tooling/validation/test_reference_client_review_approval.py`
- Reuse `tooling/visual_qa/` and existing `QaCoordinator`.

**Interfaces:**
- Must prove:
  - deterministic reference capture identity
  - golden and/or fixture VisualQaProvider check
  - at least one `QAFinding`
  - reviewer triage
  - at least one explicit promotion into `FeedbackRecord`
  - no direct AI→Feedback mutation

- [ ] **Step 1: Add failing QA boundary tests**

Assertions must include:

```text
QAFinding exists before promotion
FeedbackRecord.originQaFindingId is absent before promotion
promotion is explicit and idempotent
promoted feedback does not auto-resolve
```

- [ ] **Step 2: Run QA tests and prove failure**

Run from `apps/prototype_app`:
`flutter test test/qa`

Run Python visual-QA contract tests.

- [ ] **Step 3: Implement the reference QA scenario using existing capture/provider/coordinator seams**

Normal CI must use deterministic fake/fixture provider output, not live credentials.

- [ ] **Step 4: Run Cycle F.2 full checks**

Run:
`flutter test test/review`
`flutter test test/qa`
`flutter test`
`flutter analyze`
`py -3.12 -m unittest tooling.validation.test_reference_client_review_approval -v`

- [ ] **Step 5: Independent reviewer gate**

Reviewer checks authority boundaries, approval eligibility, QA→review promotion, append-only histories, and no hidden fixture authority. Fix blockers/majors before Cycle F.3.

---

# Cycle F.3 — Change Boundaries, Resume Proof, Reports, CI

## Task 8: Contract-Impacting Reapproval and Implementation-Only No-Reapproval

**Files:**
- Create: `tooling/reference_client/change_scenarios.py`
- Create: `tooling/validation/test_reference_client_change_scenarios.py`

**Interfaces:**
- Produces deterministic functions/scenario steps:
  - `apply_contract_impacting_change(...)`
  - `apply_implementation_only_change(...)`
- Contract-impacting path must create a new review round and ApprovalSnapshot v2.
- Implementation-only path must preserve approval version count when approved contract identity is unchanged.

- [ ] **Step 1: Write failing change-boundary tests**

```python
def test_contract_change_requires_second_approval(run_reference_scenario):
    result = run_reference_scenario("contract-change-reapproval")
    assert result.approval_versions == [1, 2]
    assert result.review_rounds >= 2


def test_implementation_only_change_does_not_create_approval_v2(run_reference_scenario):
    result = run_reference_scenario("implementation-only-change")
    assert result.approval_versions == [1]
    assert result.qa_rerun_count >= 1
```

- [ ] **Step 2: Prove failure**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_change_scenarios -v`

- [ ] **Step 3: Implement using existing approval/review change-classification rules**

Uncertain classification must raise/route to contract-impacting rather than silently choosing implementation-only.

- [ ] **Step 4: Run focused plus review regression tests**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_change_scenarios -v`
`flutter test test/review`

- [ ] **Step 5: Commit**

```bash
git add tooling/reference_client/change_scenarios.py tooling/validation/test_reference_client_change_scenarios.py
git commit -m "test: prove reference client post-approval change boundaries"
```

## Task 9: Milestone E Interruption and Fresh-Session Resume Proof

**Files:**
- Create: `tooling/validation/test_reference_client_resume_e2e.py`
- Extend: `tooling/reference_client/scenario.py`
- Reuse `tooling/workflow/runner.py`, execution manifests, leases, checkpoints, and recovery APIs.

**Interfaces:**
- Scenario `resume-after-interruption` must:
  - start a state-mutating stage attempt
  - record at least one valid checkpoint
  - simulate interruption before completion
  - release/recover according to existing lease semantics
  - instantiate a fresh runner/controller with no in-memory state from the first run
  - resume deterministically from repository state
  - complete only after validators pass

- [ ] **Step 1: Write failing fresh-session resume test**

```python
def test_reference_client_resumes_from_repo_without_chat_memory(tmp_repo):
    first = start_reference_run(tmp_repo)
    first.checkpoint("reference-fixture-ready")
    simulate_process_exit(first)

    second = fresh_reference_runner(tmp_repo)
    inspection = second.resume("reference-commerce")
    assert inspection.last_checkpoint == "reference-fixture-ready"
    assert inspection.requires_chat_context is False
```

- [ ] **Step 2: Run and prove failure**

Run:
`py -3.12 -m unittest tooling.validation.test_reference_client_resume_e2e -v`

- [ ] **Step 3: Implement using Milestone E public runner/recovery seams only**

Do not add a reference-client-specific workflow-state authority.

- [ ] **Step 4: Run workflow hardening regressions**

Run:
`py -3.12 -m unittest tooling.validation.test_workflow_runner tooling.validation.test_workflow_resume_e2e tooling.validation.test_reference_client_resume_e2e -v`

- [ ] **Step 5: Commit**

```bash
git add tooling/reference_client/scenario.py tooling/validation/test_reference_client_resume_e2e.py
git commit -m "test: prove fresh-session resume for reference client"
```

## Task 10: Machine/Human Reports, Validator, and CI Integration

**Files:**
- Create: `client-projects/schema/reference-client-report.schema.json`
- Create: `tooling/reference_client/report.py`
- Create: `tooling/reference_client/validate_reference_client.py`
- Create: `client-projects/reference-commerce/reference-e2e/report/reference-report.json`
- Create: `client-projects/reference-commerce/reference-e2e/report/reference-report.md`
- Modify: `tooling/validation/validate_repo.py`
- Modify: `.github/workflows/validate.yml`
- Add/extend reference-client validation tests.

**Interfaces:**
- `build_machine_report(...) -> dict[str, Any]`
- `render_human_report(machine_report: dict[str, Any]) -> str`
- `validate_reference_client(root, client_dir) -> list[str]`

Machine report must include:
- client ID
- fixture version
- scenario IDs
- source commit SHA
- workflow attempt IDs
- validators
- evidence refs
- review round IDs
- approval versions
- QA outcomes
- assertion pass/fail results

Human report must summarize the client, directions, chosen mix, feedback/refinement, Approval v1, QA, post-approval changes, Approval v2, implementation-only path, resume proof, and known limits.

- [ ] **Step 1: Write failing report/validator tests**

```python
def test_reference_report_has_no_subjective_overall_score(report):
    assert "overall_score" not in report
    assert report["client_id"] == "reference-commerce"
    assert report["approval_versions"] == [1, 2]
```

- [ ] **Step 2: Run and prove failure**

Run the reference-client test modules.

- [ ] **Step 3: Implement report builder, validator, and CI gate**

CI command must be deterministic and credential-free, e.g.:
`python -m tooling.reference_client.validate_reference_client client-projects/reference-commerce`

- [ ] **Step 4: Run full repository verification**

Run at minimum:

```text
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 -m tooling.prototype.validate_prototype
py -3.12 -m tooling.prototype.validate_visual_qa client-projects/reference-commerce
py -3.12 -m tooling.reference_client.validate_reference_client client-projects/reference-commerce
```

From `apps/prototype_app`:

```text
flutter test test/reference_client
flutter test test/review
flutter test test/qa
flutter test
flutter analyze
flutter build web
```

From `packages/agency_flutter_ui`:

```text
flutter test
flutter analyze
```

From `apps/widgetbook`:

```text
flutter test
flutter analyze
```

Run B.1D/B.1E `--check` freshness commands exactly as defined by the existing repository tooling.

- [ ] **Step 5: Final whole-branch independent review**

Review `git diff main...HEAD` with the strongest available reasoning model.

The reviewer must explicitly verify:
1. fixture is synthetic and deterministic
2. fixture is not a second authority
3. three directions are materially different
4. one shared Flutter runtime is used
5. B2C+B2B required journeys are covered
6. Compare/Select/Mix uses C.3 authority
7. feedback uses FeedbackRecord only
8. visual annotation uses existing C.6 contract
9. refinement uses RefinementBatch only
10. Approval v1 is canonical and immutable
11. visual QA uses QAFinding only
12. QA promotion is reviewer-controlled
13. workflow state uses Milestone E authority
14. interruption resumes from repository state
15. contract-impacting change requires new round
16. Approval v2 is new immutable version
17. implementation-only change does not force reapproval
18. machine assertions inspect canonical records
19. reports contain evidence refs, not duplicate state authority
20. no overall subjective quality score
21. CI is deterministic and credential-free
22. CI does not grant approval or production authorization
23. no ProductionAuthorization implementation appears in F
24. C/D/E regressions remain green
25. no pubspec.lock policy change

Target: **0 blockers / 0 majors**. Allow one final scoped fix dispatch and re-review if needed.

- [ ] **Step 6: Commit final reports/CI/docs**

```bash
git add client-projects/reference-commerce/reference-e2e client-projects/schema tooling/reference_client tooling/validation .github/workflows/validate.yml
git commit -m "feat: complete Milestone F reference client regression fixture"
```

---

# SDD Execution Structure

Execute as three large cycles, with fresh implementation/review context per cycle:

1. **F.1 Reference Client Foundation** — Tasks 1–4
2. **F.2 Review → Approval v1 → Visual QA** — Tasks 5–7
3. **F.3 Change Boundaries + Resume + Reports/CI** — Tasks 8–10

Each cycle requires:
- fresh implementer
- implementer self-review
- independent reviewer
- blocker/major fix loop
- scoped re-review
- ledger entry with commits, commands, exact test counts, rulings, and deviations

Do not merge the Milestone F PR without explicit human authorization.
