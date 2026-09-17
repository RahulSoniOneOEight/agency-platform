# Milestone D — Automated Visual QA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build deterministic screenshot capture, provider-neutral Visual AI QA with `QAFinding`, governed golden regression, and QA orchestration that integrates cleanly with the existing C.4–C.7 review/refinement authority model.

**Architecture:** Python tooling owns deterministic browser/capture automation and repository-level QA validation; Dart owns reviewer-facing QA domain state, promotion into `FeedbackRecord`, and the `QaCoordinator` boundary with `ReviewCoordinator`. The two sides exchange schema-validated JSON records/artifact metadata. `QAFinding` remains separate from `FeedbackRecord` until explicit reviewer promotion.

**Tech Stack:** Python 3.12, PyYAML, Flutter 3.47+/Dart 3.13+, Flutter Web/Chrome, Dart/Flutter tests, GitHub Actions, existing Design Contract tooling, existing C.4–C.7 review subsystem.

**Spec:** `docs/superpowers/specs/2026-09-17-milestone-d-automated-visual-qa-design.md`

## Global Constraints

- Work only on `milestone-d-visual-qa`; do not implement on `main`.
- Preserve C.3 selection/mix authority and C.4–C.7 review/refinement authority.
- `QAFinding` is automated-QA authority; `FeedbackRecord` remains human-review authority.
- Visual AI must never approve/reject experience, resolve/reopen feedback, alter blocking, mutate approval snapshots, or rewrite runtime state.
- `QaCoordinator` orchestrates QA; `ReviewCoordinator` remains the only cross-domain review/refinement authority.
- Design Contract/B.1D/B.1E are higher authority than generic AI aesthetic heuristics.
- Screenshot/golden baselines are never auto-rewritten after failure.
- AI findings alone do not become an opaque CI merge oracle.
- Canonical viewports remain 360×800, 390×844, 430×932, 768×1024, and 1440×900.
- Do not add D-stage behavior that belongs to E workflow hardening, G production authorization, or H productionization.
- Do not commit the existing untracked `pubspec.lock` files or introduce a lockfile-policy change.
- Use TDD for every behavior change; each task ends in a focused green test set and a logical commit.

---

## File Structure and Responsibilities

### Python capture/automation

- Create `tooling/visual_qa/__init__.py` — package boundary.
- Create `tooling/visual_qa/errors.py` — typed Python QA exceptions.
- Create `tooling/visual_qa/capture_models.py` — normalized viewport/job/artifact metadata models and stable IDs.
- Create `tooling/visual_qa/capture_runner.py` — capture backend protocol + process-backed browser capture orchestration.
- Create `tooling/visual_qa/qa_contracts.py` — JSON contract validation helpers shared by QA outputs.
- Create `tooling/visual_qa/visual_provider.py` — provider-neutral command/provider contract and strict structured-output parsing.
- Create `tooling/visual_qa/golden_compare.py` — deterministic baseline/diff metadata and comparison policy helpers.
- Modify `tooling/prototype/screenshot_manifest.py` — emit/validate v2 deterministic capture manifests while preserving v1 read compatibility.
- Modify `tooling/prototype/capture_screenshots.py` — compatibility CLI/wrapper that delegates to the new capture package.
- Modify `tooling/prototype/validate_visual_qa.py` — validate v2 QA artifacts/findings and legacy files where required.
- Create `tooling/validation/test_visual_qa_capture.py` — D.1 tests.
- Create `tooling/validation/test_visual_qa_contracts.py` — D.2/D.4 Python contract tests.

### Browser capture adapter

- Create `tooling/screenshots/capture_web.mjs` — a narrow headless-browser adapter invoked by Python; input and output are JSON lines/files, not business logic.
- Create `tooling/screenshots/package.json` only if the implementation needs a local browser dependency; keep dependency surface limited to capture execution.
- Generated PNGs/diffs remain ignored build/CI artifacts; governed baseline metadata stays versioned.

### Dart QA domain and integration

- Create `apps/prototype_app/lib/qa/qa_domain_error.dart` — typed QA domain errors.
- Create `apps/prototype_app/lib/qa/qa_finding.dart` — immutable finding + append-only lifecycle/history.
- Create `apps/prototype_app/lib/qa/qa_finding_repository.dart` — repository abstraction.
- Create `apps/prototype_app/lib/qa/memory_qa_finding_repository.dart` — tests/runtime prototype adapter.
- Create `apps/prototype_app/lib/qa/persistence/file_qa_finding_repository.dart` — file-backed persistence matching the governed client layout.
- Create `apps/prototype_app/lib/qa/visual_qa_provider.dart` — provider-neutral Dart-side contract for normalized candidate input.
- Create `apps/prototype_app/lib/qa/qa_coordinator.dart` — triage, dedupe/promotion orchestration, re-check state transitions.
- Create `apps/prototype_app/lib/qa/review_qa_panel.dart` — reviewer-facing triage surface.
- Modify `apps/prototype_app/lib/review/feedback_record.dart` only to add an optional immutable `originQaFindingId` provenance field.
- Modify `apps/prototype_app/lib/review/review_coordinator.dart` only as needed to expose the existing validated feedback-creation operation to `QaCoordinator`; do not duplicate C.4 rules.
- Modify `apps/prototype_app/lib/review/review_shell.dart` to expose QA triage without moving QA authority into `ReviewState`.
- Create tests under `apps/prototype_app/test/qa/` for finding model, repository, coordinator, promotion, and UI.

### Goldens / Widgetbook / CI / client contract

- Modify `apps/widgetbook/lib/widgetbook_app.dart` to expose a small representative set of high-value deterministic states.
- Create `apps/widgetbook/test/golden/` tests and governed baseline files for representative reusable surfaces.
- Add selected prototype/package golden coverage only where stable and regression-prone; do not golden every permutation.
- Modify `client-projects/examples/prototype-demo/prototype/qa/screenshot-manifest.yaml` to v2 deterministic jobs.
- Create `client-projects/schema/screenshot-manifest.schema.json`.
- Create `client-projects/schema/qa-finding.schema.json`.
- Create `templates/qa-finding.json` or equivalent schema-valid example; retain `templates/visual-qa-findings.yaml` only as a documented legacy compatibility artifact if still referenced.
- Modify `VISUAL_QA.md` and `workflows/06-visual-qa.md` to make the new D contracts canonical.
- Modify `.github/workflows/flutter-ci.yml` and/or `.github/workflows/validate.yml` for deterministic QA schema/golden checks without requiring an AI provider secret for ordinary PR validation.

---

# Cycle 1 — D.1 Deterministic Screenshot Automation

## Task 1: Upgrade the Screenshot Manifest Contract

**Files:**
- Create: `client-projects/schema/screenshot-manifest.schema.json`
- Modify: `tooling/prototype/screenshot_manifest.py`
- Modify: `client-projects/examples/prototype-demo/prototype/qa/screenshot-manifest.yaml`
- Test: `tooling/validation/test_visual_qa_capture.py`

**Interfaces:**
- Produces `normalize_manifest(data) -> dict` and `build_capture_jobs(manifest, base_url, source_commit_sha) -> list[dict]` with stable `capture_id` values.
- Consumed by Task 2 capture runner and Cycle 3 orchestration.

- [ ] **Step 1: Write failing tests for the v2 contract**

```python
def test_v2_manifest_expands_only_declared_jobs():
    manifest = {
        "version": 2,
        "client_id": "prototype-demo",
        "fixture_version": "demo-v1",
        "jobs": [{
            "surface": "prototype",
            "screen": "commerce.home",
            "state": "default",
            "direction": "b",
            "viewport": {"width": 390, "height": 844},
            "device_scale_factor": 1,
        }],
    }
    jobs = build_capture_jobs(manifest, "http://localhost:8080", "abc123")
    assert len(jobs) == 1
    assert jobs[0]["source_commit_sha"] == "abc123"
    assert jobs[0]["capture_id"]


def test_unknown_direction_is_rejected():
    manifest = valid_manifest(direction="z")
    with pytest.raises(InvalidCaptureJob):
        normalize_manifest(manifest)
```

- [ ] **Step 2: Run the focused test and confirm RED**

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_capture -v
```

Expected: failure because v2 normalization/typed errors do not yet exist.

- [ ] **Step 3: Implement v2 normalization and stable identity**

Implement canonical fields exactly from the spec: client, surface, screen/story, state, direction/mix reference, viewport, scale factor, fixture version, source commit. Retain v1 read compatibility by expanding the current `directions × viewports` shape into normalized v2 jobs; new writes are v2 only.

Stable IDs must be derived from canonical normalized input, e.g. SHA-256 over sorted JSON, not wall-clock time.

- [ ] **Step 4: Validate governed viewports and explicit custom jobs**

Canonical presets resolve to the existing five viewport sizes. Custom dimensions are accepted only when explicitly present on the job; no implicit random/default viewport.

- [ ] **Step 5: Run focused tests GREEN**

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_capture -v
py -3.12 -m tooling.prototype.validate_visual_qa client-projects/examples/prototype-demo
```

- [ ] **Step 6: Commit**

```bash
git add client-projects/schema/screenshot-manifest.schema.json tooling/prototype/screenshot_manifest.py client-projects/examples/prototype-demo/prototype/qa/screenshot-manifest.yaml tooling/validation/test_visual_qa_capture.py
git commit -m "feat: define deterministic screenshot manifest v2"
```

## Task 2: Build the Deterministic Capture Runner

**Files:**
- Create: `tooling/visual_qa/__init__.py`
- Create: `tooling/visual_qa/errors.py`
- Create: `tooling/visual_qa/capture_models.py`
- Create: `tooling/visual_qa/capture_runner.py`
- Create: `tooling/screenshots/capture_web.mjs`
- Modify: `tooling/prototype/capture_screenshots.py`
- Test: `tooling/validation/test_visual_qa_capture.py`

**Interfaces:**
- Produces `ScreenshotCaptureBackend.capture(job) -> ScreenshotArtifact`.
- Produces `CaptureRunner.run(jobs) -> list[ScreenshotArtifact]`.
- `ScreenshotArtifact` serializes client/surface/screen-or-story/state/direction-or-mix/viewport/fixture/source commit/path/hash.

- [ ] **Step 1: Add failing unit tests around a fake capture backend**

```python
def test_runner_persists_no_success_for_failed_capture(tmp_path):
    runner = CaptureRunner(backend=FailingBackend(), output_dir=tmp_path)
    with pytest.raises(CaptureFailed):
        runner.run([sample_job()])
    assert list(tmp_path.glob("*.artifact.json")) == []


def test_artifact_identity_matches_job_and_hash(tmp_path):
    artifacts = CaptureRunner(FakeBackend(PNG_BYTES), tmp_path).run([sample_job()])
    assert artifacts[0].capture_id == sample_job()["capture_id"]
    assert artifacts[0].content_hash.startswith("sha256:")
```

- [ ] **Step 2: Run RED**

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_capture -v
```

- [ ] **Step 3: Implement backend protocol and atomic artifact writes**

Capture into a temporary file, validate output exists/non-empty, hash it, then atomically publish PNG metadata. Failed/stale/partial files must not receive successful artifact metadata.

- [ ] **Step 4: Implement the browser adapter as transport only**

`capture_web.mjs` accepts a normalized job JSON, launches headless Chromium, sets exact viewport/device scale, navigates to the governed URL, waits for deterministic readiness/settling, captures PNG, and returns machine-readable success/error JSON. It must contain no QA severity, finding, review, or approval logic.

If the repository lacks a browser dependency, add the smallest local capture dependency required by the implementation and document its install command in `VISUAL_QA.md`; do not add unrelated Node tooling.

- [ ] **Step 5: Preserve the old CLI entry point**

`tooling/prototype/capture_screenshots.py` becomes a compatibility wrapper around the new runner so existing workflow references continue to work.

- [ ] **Step 6: Run focused unit + one local smoke capture**

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_capture -v
py -3.12 -m tooling.prototype.capture_screenshots --help
```

Then serve `apps/prototype_app` and capture one `prototype-demo` 390×844 job. Confirm the PNG and sidecar metadata share the same `capture_id` and source commit.

- [ ] **Step 7: Commit**

```bash
git add tooling/visual_qa tooling/screenshots tooling/prototype/capture_screenshots.py tooling/validation/test_visual_qa_capture.py
git commit -m "feat: automate deterministic Flutter web captures"
```

## Task 3: Cycle 1 Validation and Independent Review

**Files:**
- Modify if required by findings: only Cycle 1 files.
- Record execution in the plan-specific SDD ledger.

- [ ] Run:

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_capture -v
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
```

- [ ] Independently review D.1 for deterministic identity, failure atomicity, v1 read compatibility, governed viewports, no QA business logic in browser adapter, and no committed generated PNG noise.
- [ ] Fix blocker/major findings and rerun focused tests.
- [ ] Record Cycle 1 commit range, tests, findings, rulings, and deviations in the SDD ledger.

**Cycle 1 exit:** required capture jobs are reproducible, identity-rich, source-commit traceable, and a failed capture cannot masquerade as successful evidence.

---

# Cycle 2 — D.2 Visual AI QA + QAFinding

## Task 4: Implement the QAFinding Domain and Repository

**Files:**
- Create: `client-projects/schema/qa-finding.schema.json`
- Create: `apps/prototype_app/lib/qa/qa_domain_error.dart`
- Create: `apps/prototype_app/lib/qa/qa_finding.dart`
- Create: `apps/prototype_app/lib/qa/qa_finding_repository.dart`
- Create: `apps/prototype_app/lib/qa/memory_qa_finding_repository.dart`
- Create: `apps/prototype_app/lib/qa/persistence/file_qa_finding_repository.dart`
- Test: `apps/prototype_app/test/qa/qa_finding_test.dart`
- Test: `apps/prototype_app/test/qa/qa_finding_repository_test.dart`

**Interfaces:**
- `QaFindingStatus = detected | triaged | promoted | dismissed | acceptedRisk`.
- `QaSeverity = info | minor | major | blocker`.
- Repository exposes typed `get`, `list`, `create`, `save` behavior without arbitrary map mutation.

- [ ] **Step 1: Write lifecycle/history tests first**

```dart
test('finding lifecycle preserves append-only history', () {
  final finding = sampleFinding();
  final triaged = finding.triage(actor: reviewer, at: t1);
  final dismissed = triaged.dismiss(actor: reviewer, at: t2, reason: 'not reproducible');
  expect(dismissed.status, QaFindingStatus.dismissed);
  expect(dismissed.history.map((e) => e.event), ['detected', 'triaged', 'dismissed']);
});

test('severity does not imply review blocking', () {
  expect(sampleFinding(severity: QaSeverity.blocker).blocking, isNull);
});
```

- [ ] **Step 2: Run RED**

```bash
cd apps/prototype_app
flutter test test/qa/qa_finding_test.dart
```

- [ ] **Step 3: Implement immutable model + typed transitions**

Require non-empty provenance, screenshot ref, source commit, summary, valid normalized evidence region if supplied, and append-only transition history. Invalid transitions throw typed `QaDomainError` variants.

- [ ] **Step 4: Implement memory and file repositories**

File layout is `client-projects/<client>/prototype/qa/findings/<finding-id>.json`. Use complete candidate validation before persistence. Do not overwrite terminal-history semantics silently.

- [ ] **Step 5: Run GREEN**

```bash
flutter test test/qa/qa_finding_test.dart test/qa/qa_finding_repository_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add client-projects/schema/qa-finding.schema.json apps/prototype_app/lib/qa apps/prototype_app/test/qa
git commit -m "feat: add structured QA finding lifecycle"
```

## Task 5: Implement Provider-Neutral Visual QA Contracts and Deduplication

**Files:**
- Create: `tooling/visual_qa/qa_contracts.py`
- Create: `tooling/visual_qa/visual_provider.py`
- Create: `tooling/validation/test_visual_qa_contracts.py`
- Create: `apps/prototype_app/lib/qa/visual_qa_provider.dart`
- Add tests under: `apps/prototype_app/test/qa/visual_qa_provider_test.dart`

**Interfaces:**
- Python provider boundary: `VisualQaProvider.review(screenshot, context, authority_bundle) -> list[dict]`.
- Dart-side normalized candidate input is provider-neutral and maps to `QaFinding` only after schema/domain validation.
- Stable dedupe key derives from client + surface/screen/story + rule source/ref + category + governed section/normalized region + baseline/reference identity.

- [ ] **Step 1: Write failing schema/provenance tests**

```python
def test_provider_output_without_rule_source_is_rejected():
    with pytest.raises(VisualQaSchemaInvalid):
        validate_candidate({"summary": "overflow", "severity": "major"})


def test_same_issue_produces_same_dedupe_key():
    assert dedupe_key(candidate_a) == dedupe_key(candidate_b_with_new_confidence)
```

- [ ] **Step 2: Run RED**

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_contracts -v
```

- [ ] **Step 3: Implement the authority bundle explicitly**

The provider request must present authorities in this order: approved/current governed experience, Design Contract/tokens, accepted baseline, explicitly linked references, then general visual heuristics. Lower layers cannot be serialized as if they supersede higher authority.

- [ ] **Step 4: Implement strict structured-output transport**

Use a provider-neutral adapter boundary. If a live model adapter is included, isolate it behind this interface; ordinary tests/CI must run using fixture/fake output without external network or secrets. Reject malformed/free-form output rather than persisting prose.

- [ ] **Step 5: Add Dart mapping tests**

Verify normalized candidate JSON becomes a valid `QaFinding`, while malformed evidence/provenance fails with typed QA errors and never creates `FeedbackRecord`.

- [ ] **Step 6: Run GREEN**

```bash
py -3.12 -m unittest tooling.validation.test_visual_qa_contracts -v
cd apps/prototype_app
flutter test test/qa/visual_qa_provider_test.dart test/qa/qa_finding_test.dart
```

- [ ] **Step 7: Commit**

```bash
git add tooling/visual_qa tooling/validation/test_visual_qa_contracts.py apps/prototype_app/lib/qa apps/prototype_app/test/qa
git commit -m "feat: add provider-neutral visual QA contract"
```

## Task 6: Cycle 2 Validation and Independent Review

- [ ] Run focused Python and Flutter QA-domain suites.
- [ ] Run `flutter test test/review` to prove C.4–C.7 authority remains green.
- [ ] Independent reviewer verifies: no direct AI→FeedbackRecord path, no overall quality score, correct authority hierarchy, severity not equal to blocking, append-only history, dedupe stability, provider neutrality, and no network requirement in ordinary CI.
- [ ] Fix blocker/major findings, rerun tests, and record the cycle in the SDD ledger.

**Cycle 2 exit:** model/provider output can only become schema-valid `QAFinding` records with explicit provenance; reviewer authority remains untouched.

---

# Cycle 3 — D.3 Golden Expansion + D.4 QA Orchestration

## Task 7: Add Governed Golden Baselines and Widgetbook Coverage

**Files:**
- Modify: `apps/widgetbook/lib/widgetbook_app.dart`
- Create/modify: `apps/widgetbook/test/golden/`
- Create selected golden tests in `packages/agency_flutter_ui/test/` and/or `apps/prototype_app/test/` only for stable high-value surfaces.
- Create: `tooling/visual_qa/golden_compare.py`
- Extend: `tooling/validation/test_visual_qa_contracts.py`

**Interfaces:**
- `GoldenComparison` records baseline ID, candidate capture ID, result, diff/evidence refs.
- Baseline updates require an explicit update command/action; normal test failure never rewrites baseline.

- [ ] **Step 1: Add one representative failing golden per chosen high-value surface**

Use stable fixtures/Ahem test rendering and explicit fixed surface size. Start with representative shared component/pattern states, not all permutations.

- [ ] **Step 2: Run RED before accepting baseline**

```bash
cd apps/widgetbook
flutter test test/golden
```

Expected: missing-baseline failure for the newly declared golden.

- [ ] **Step 3: Generate/review initial baselines explicitly**

Use Flutter’s explicit golden update path only after inspecting the intended rendered states. Commit approved baselines as governed files.

- [ ] **Step 4: Add deterministic comparison metadata tests**

A mismatch produces evidence/diff metadata and never writes a replacement baseline by itself.

- [ ] **Step 5: Run GREEN**

```bash
flutter test test/golden
cd ../../packages/agency_flutter_ui
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add apps/widgetbook packages/agency_flutter_ui tooling/visual_qa/golden_compare.py tooling/validation/test_visual_qa_contracts.py
git commit -m "test: add governed visual golden coverage"
```

## Task 8: Implement QaCoordinator and Reviewer Promotion

**Files:**
- Create: `apps/prototype_app/lib/qa/qa_coordinator.dart`
- Create: `apps/prototype_app/lib/qa/review_qa_panel.dart`
- Modify: `apps/prototype_app/lib/review/feedback_record.dart`
- Modify: `apps/prototype_app/lib/review/review_coordinator.dart`
- Modify: `apps/prototype_app/lib/review/review_shell.dart`
- Test: `apps/prototype_app/test/qa/qa_coordinator_test.dart`
- Test: `apps/prototype_app/test/qa/review_qa_panel_test.dart`
- Extend: `apps/prototype_app/test/review/review_architecture_test.dart`

**Interfaces:**
- `QaCoordinator.triageFinding(...)` handles QA-only lifecycle.
- `QaCoordinator.promoteFinding(...) -> FeedbackRecord` calls the existing validated ReviewCoordinator feedback creation seam.
- `FeedbackRecord.originQaFindingId` is optional, immutable provenance and does not affect C.4 lifecycle semantics.

- [ ] **Step 1: Write the promotion transaction tests**

```dart
test('promotion is explicit and idempotent', () async {
  final first = await qa.promoteFinding(findingId: 'qa-1', reviewer: reviewer);
  final second = await qa.promoteFinding(findingId: 'qa-1', reviewer: reviewer);
  expect(second.id, first.id);
  expect(second.originQaFindingId, 'qa-1');
});

test('failed feedback creation leaves finding unpromoted', () async {
  await expectLater(
    qa.promoteFinding(findingId: 'qa-1', reviewer: reviewer),
    throwsA(isA<QaDomainError>()),
  );
  expect((await qaFindings.get('qa-1'))!.status, QaFindingStatus.triaged);
});
```

- [ ] **Step 2: Run RED**

```bash
cd apps/prototype_app
flutter test test/qa/qa_coordinator_test.dart
```

- [ ] **Step 3: Implement promotion without duplicating C.4 validation**

`QaCoordinator` validates promotability/idempotency, then delegates feedback creation to `ReviewCoordinator`. Only after successful feedback creation does it persist the promoted finding link. If atomic rollback cannot be guaranteed by current repository adapters, use create-first-with-idempotency plus deterministic recovery and document the ordering ruling in the ledger; never create two feedback records for one finding.

- [ ] **Step 4: Implement reviewer triage UI**

The QA panel shows structured findings and explicit Promote / Dismiss / Accept risk operations. It must not expose Resolve Feedback, Change Blocking, Approval, or baseline auto-update actions as QA shortcuts.

- [ ] **Step 5: Extend architecture tests**

Assert `ReviewState` contains no `QAFinding` collection, `QaCoordinator` does not mutate approval/runtime, and `ReviewCoordinator` remains the feedback lifecycle authority.

- [ ] **Step 6: Run GREEN**

```bash
flutter test test/qa
flutter test test/review
```

- [ ] **Step 7: Commit**

```bash
git add apps/prototype_app/lib/qa apps/prototype_app/lib/review apps/prototype_app/test/qa apps/prototype_app/test/review/review_architecture_test.dart
git commit -m "feat: integrate QA findings with governed review promotion"
```

## Task 9: Implement Re-check Orchestration and QA Run Records

**Files:**
- Extend: `apps/prototype_app/lib/qa/qa_coordinator.dart`
- Create: `apps/prototype_app/lib/qa/qa_run.dart`
- Create repository adapter(s) for QA run metadata if required by current persistence conventions.
- Extend: `apps/prototype_app/test/qa/qa_coordinator_test.dart`
- Extend Python QA contract tests as needed.

**Interfaces:**
- `QaRun` records exact capture IDs/checks/provider/baseline identities/results/source commit.
- Recheck maps changed screens/sections to affected governed capture jobs.

- [ ] **Step 1: Write failing recheck tests**

```dart
test('recheck does not resolve promoted feedback', () async {
  await qa.recordSuccessfulRecheck(findingId: 'qa-1', run: passingRun);
  expect((await qaFindings.get('qa-1'))!.isNoLongerReproducible, isTrue);
  expect((await feedback.get('feedback-1'))!.status, isNot(FeedbackStatus.resolved));
});
```

- [ ] **Step 2: Run RED**

```bash
flutter test test/qa/qa_coordinator_test.dart
```

- [ ] **Step 3: Implement targeted affected-job selection**

Use governed screen/section metadata and capture manifest references. Do not recapture every permutation when a batch only touched one governed surface.

- [ ] **Step 4: Implement no-longer-reproducible semantics**

Unpromoted findings may be marked no longer reproducible/terminal according to QA history. Promoted findings retain the linked `FeedbackRecord`; QA evidence may update but C.4 reviewer still resolves/reopens.

- [ ] **Step 5: Run GREEN and commit**

```bash
flutter test test/qa
```

```bash
git add apps/prototype_app/lib/qa apps/prototype_app/test/qa
git commit -m "feat: add targeted visual QA recheck loop"
```

## Task 10: Make the D Contracts Canonical in Docs, Workflow, Validators, and CI

**Files:**
- Modify: `VISUAL_QA.md`
- Modify: `workflows/06-visual-qa.md`
- Modify: `tooling/prototype/validate_visual_qa.py`
- Modify: `templates/visual-qa-findings.yaml` or replace references with the new canonical QA finding example/schema.
- Modify: `.github/workflows/flutter-ci.yml`
- Modify: `.github/workflows/validate.yml`
- Modify: `tooling/validation/test_prototype_platform.py`
- Modify: `tooling/validation/test_validate_repo.py`

**Interfaces:**
- CI validates manifest/schema/goldens deterministically without requiring Visual AI credentials.
- Optional live Visual AI execution is a separate configured step and cannot silently become a hard merge gate.

- [ ] **Step 1: Write validator tests that fail on legacy-only assumptions**

Add fixtures proving v2 manifest/finding contracts pass and malformed/ambiguous records fail.

- [ ] **Step 2: Run RED**

```bash
py -3.12 -m unittest tooling.validation.test_prototype_platform tooling.validation.test_validate_repo -v
```

- [ ] **Step 3: Update docs/workflow/validators together**

`VISUAL_QA.md` becomes consistent with the D spec: `QAFinding` lifecycle/severity, reviewer promotion, baselines, deterministic vs AI CI behavior, recheck loop. `workflows/06-visual-qa.md` writes findings under the new repository layout rather than treating one mutable YAML file as the new authority.

- [ ] **Step 4: Update CI**

Run schema/manifest validators and governed Flutter golden tests on the canonical runner. Do not require an AI API key for routine PRs. Preserve existing Flutter tests/analyze/build gates.

- [ ] **Step 5: Run GREEN**

```bash
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.prototype.validate_visual_qa client-projects/examples/prototype-demo
```

- [ ] **Step 6: Commit**

```bash
git add VISUAL_QA.md workflows/06-visual-qa.md tooling/prototype/validate_visual_qa.py templates .github/workflows tooling/validation
git commit -m "ci: govern automated visual QA workflow"
```

## Task 11: End-to-End D.1–D.4 Regression and Final Review

**Files:**
- Create: `apps/prototype_app/test/qa/qa_d1_d4_end_to_end_test.dart`
- Extend only if needed: architecture/regression tests in `apps/prototype_app/test/review/`.
- Record final evidence in SDD ledger.

- [ ] **Step 1: Implement the exact governed integration test**

Prove:

```text
C.3 selected/mixed experience
→ deterministic capture metadata
→ golden/AI candidate
→ QAFinding
→ reviewer triage
→ explicit promotion
→ FeedbackRecord(originQaFindingId)
→ C.7 refinement batch
→ successful validation/addressed
→ targeted recheck
→ QA finding no longer reproducible
→ FeedbackRecord still awaits reviewer resolution
```

The test may use fake capture/provider backends; browser/network execution is verified separately by D.1 smoke capture.

- [ ] **Step 2: Run the complete Flutter verification**

```bash
cd apps/prototype_app
flutter test test/qa
flutter test test/review
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

- [ ] **Step 3: Run repository verification**

```bash
cd ../..
py -3.12 -m unittest discover tooling/validation
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 -m tooling.prototype.validate_prototype client-projects/examples/prototype-demo
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
py -3.12 -m tooling.design_contract.generate_resolved_themes --check
```

Use the repository’s actual canonical invocation if a validator takes different arguments; record the exact command/result in the ledger.

- [ ] **Step 4: Final whole-branch reviewer**

Review `git diff <C.4-C.7-base>...HEAD` using the strongest available reasoning model. Explicitly verify:

1. no direct Visual AI → FeedbackRecord path;
2. QAFinding is sole automated finding identity authority;
3. FeedbackRecord lifecycle authority remains C.4;
4. severity does not silently become blocking;
5. authority hierarchy is preserved;
6. screenshot identity is deterministic and source-traceable;
7. failed capture cannot create successful evidence;
8. baselines never auto-update;
9. golden hard gates are deterministic;
10. AI findings are not opaque merge-oracle scores;
11. provider output is schema validated;
12. provider/model specifics do not leak into core QA records;
13. dedupe is stable;
14. promotion is explicit/idempotent;
15. QA cannot resolve promoted feedback;
16. targeted recheck does not bypass reviewer authority;
17. ReviewState contains no parallel QA state model;
18. QaCoordinator does not replace ReviewCoordinator;
19. runtime remains read-only from QA;
20. B.1D/B.1E remain design authority;
21. C.3 Select + Mix still passes;
22. C.4–C.7 end-to-end still passes;
23. no E/G/H scope creep;
24. no lockfile-policy change.

- [ ] **Step 5: One fix round if necessary, then final re-review**

Target: 0 blockers / 0 majors. Record accepted minors/deviations explicitly.

- [ ] **Step 6: Final commit/PR preparation**

Commit final test/docs/ledger changes, push `milestone-d-visual-qa`, and open a PR against the appropriate integration base. Do not merge without explicit user authorization.

---

## Self-Review Checklist for This Plan

- Spec coverage: D.1 capture, D.2 QAFinding/provider/dedupe, D.3 Widgetbook/goldens, D.4 orchestration/promotion/recheck/CI are all mapped to concrete tasks.
- Authority check: `QAFinding`, `FeedbackRecord`, `QaCoordinator`, `ReviewCoordinator`, Design Contract, and runtime responsibilities do not overlap.
- Compatibility check: current v1 screenshot manifest is read-compatible; new writes are v2.
- Dependency check: browser capture dependency is isolated to the transport adapter; ordinary domain/CI tests do not require live AI credentials.
- Transaction check: failed capture, failed promotion, malformed provider output, and baseline mismatch cannot create false successful state.
- Scope check: E workflow hardening, G production authorization, and H productionization are explicitly excluded.
- Placeholder scan: no TBD/TODO/“implement later” steps remain.
- Type consistency: `QaFinding`, `QaFindingStatus`, `QaSeverity`, `QaCoordinator`, `originQaFindingId`, `ScreenshotArtifact`, and capture/provider interfaces are named consistently across tasks.
