# Milestone D — Automated Visual QA — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-d-visual-qa` (do not work on `main`; do not merge)
- Integration base: C.4–C.7 merged baseline (`236f98e`, PR #20); branch point `774bd55`
- Spec: `docs/superpowers/specs/2026-09-17-milestone-d-automated-visual-qa-design.md` (`de132f2`)
- Plan: `docs/superpowers/plans/2026-09-17-milestone-d-automated-visual-qa-implementation.md` (`9f613dc`)
- Execution model: exactly 3 cycles (Cycle 1 = D.1; Cycle 2 = D.2; Cycle 3 = D.3 + D.4 + CI).
- Mode: TDD, fresh implementer + fresh independent reviewer per cycle, final whole-branch review.
- Started: 2026-09-17

## Resume protocol

1. `git branch --show-current` — confirm `milestone-d-visual-qa`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first cycle not marked `ACCEPTED`; re-run its focused tests first.

## Preflight consistency scan

### Preflight verification (recorded)

- `git fetch` — origin advanced; `origin/milestone-d-visual-qa` carries the D design + plan commits.
- `git branch --show-current` → `milestone-d-visual-qa` (created from `origin/milestone-d-visual-qa`,
  whose history is C.4–C.7 final `774bd55` + D docs).
- `git status` → only three untracked files: `apps/prototype_app/pubspec.lock`,
  `apps/widgetbook/pubspec.lock`, `packages/agency_flutter_ui/pubspec.lock`. These remain
  uncommitted and `.gitignore` policy for lockfiles is unchanged.
- C.4–C.7 integration baseline is present: `lib/review/**` (C.4 feedback, C.5 approval, C.6 visual,
  C.7 refinement) and the merged PR #20 (`236f98e`).
- Baseline suites: Python `unittest discover tooling/validation` = **283 tests OK**;
  `flutter test test/review` = **581 tests passing**.

### Shared interfaces checked

| Interface | Current reality | D treatment |
|-----------|-----------------|-------------|
| Screenshot manifests | v1 only: `tooling/prototype/screenshot_manifest.py` (`build_screenshot_manifest`), demo manifest `prototype/qa/screenshot-manifest.yaml` (version 1, `directions`/`viewports`/`routes`). Validator `validate_prototype.py:99–112` only asserts `directions` set == prototype direction keys. No JSON schema. | Add v2 + `normalize_manifest` + `build_capture_jobs`; v1 stays readable; `validate_prototype.py` becomes v1+v2 aware. |
| `ScreenshotArtifact` identity | Does not exist. `tooling/prototype/capture_screenshots.py` builds non-identity job dicts (`direction`, `viewport` name, `filename`). | New `tooling/visual_qa/capture_models.py` + `capture_runner.py`; stable SHA-256 `capture_id` over canonical normalized input; content hash over PNG bytes. |
| `QAFinding` ownership | Does not exist. `tooling/prototype/validate_visual_qa.py` validates a legacy single mutable `visual-findings.yaml` (severity low/medium/high/critical; status open/resolved/accepted). | New Dart `QAFinding` (sole automated QA authority) under `apps/prototype_app/lib/qa/`; legacy YAML retained (RD9). |
| `QaCoordinator` | Does not exist. | New `apps/prototype_app/lib/qa/qa_coordinator.dart`; orchestration only. |
| `FeedbackRecord` promotion | `FeedbackRecord` has 10 canonical keys; `toJson` always emits all 10. `ReviewCoordinator.createFeedback` is the only validated feedback-creation seam. `reviewStateHash` hashes only `ReviewState`, so a new feedback key cannot affect approval hashes. | Add optional immutable `originQaFindingId` (`origin_qa_finding_id`, 11th always-present key, null when absent). Update the canonical-key test. |
| `ReviewCoordinator` boundary | `createFeedback`, `allFeedback`, `loadFeedback`, resolve/reopen/setBlocking, batches, approvals. | `QaCoordinator` delegates feedback creation to `createFeedback`; never mutates ReviewState/approvals/runtime. |
| Visual AI provider interface | Does not exist. Nearest precedent: provider-neutral `VisualFeedbackProvider` + `BugDropVisualFeedbackProvider` (`lib/review/`) with `UnsupportedVisualProviderPayload`. | New provider-neutral `VisualQaProvider` seam (Python `tooling/visual_qa/visual_provider.py` + Dart `lib/qa/visual_qa_provider.dart`); offline/fake by default. |
| Golden/baseline authority | Zero `matchesGoldenFile` usages repo-wide; no `goldens/`; no golden deps. | Flutter built-in `matchesGoldenFile` only (no new dependency); committed baselines; explicit update path. |
| Widgetbook integration | `apps/widgetbook/lib/widgetbook_app.dart` (3 categories, fixed `AgencyTheme.lightDefault()`); one smoke test; no goldens. | Add a small high-value governed story set + `test/golden/` baselines. |
| CI behavior | `flutter-ci.yml` (analyze/test/build web, no path filters) and `validate.yml` (explicit unittest module list + validators). No QA schema/golden steps. | Add deterministic manifest/schema/golden validation; no AI secret required. |
| Targeted re-check after refinement | Does not exist. C.7 exposes `RefinementBatch` + `recordBatchValidation` + `reopenAddressedForRegression`. | `QaCoordinator` recheck maps changed governed surfaces → affected capture jobs → recapture/recompare; never auto-resolves promoted feedback. |

### Plan-vs-repository conflicts and resolutions

- **v1 manifest vs. composer + prototype validator.** `compose_prototype` writes the manifest via
  `build_screenshot_manifest`; `validate_prototype.py` asserts `directions`. A naive v2 rewrite breaks
  the composer tests and the prototype validator. → **RD1**.
- **`feedback_record_test.dart` pins exactly 10 canonical keys.** Adding `origin_qa_finding_id`
  requires updating that assertion. → **RD5/RD6** (test updated with the field).
- **No golden dependency exists.** `golden_toolkit`/`alchemist` are absent and `pubspec.lock` must not
  be committed/changed. → **RD7** (built-in `matchesGoldenFile`).
- **`lib/review` architecture guard forbids `dart:io` outside `persistence/`.** The new QA subsystem
  needs file persistence. → **RD3** (mirror the R1 boundary under `lib/qa`).
- **`validate_workflow.py` / `router.py` depend on legacy `visual-findings.yaml`.** Removing it would
  break the workflow runtime. → **RD9** (retain legacy; add v2 alongside).

## Rulings

- **RD1 — Screenshot manifest v2 + v1 read compatibility.** `tooling/prototype/screenshot_manifest.py`
  gains `MANIFEST_VERSION = 2`, governed `STANDARD_VIEWPORTS` (unchanged five presets),
  `normalize_manifest(data)` and `build_capture_jobs(manifest, base_url, source_commit_sha)`.
  `build_screenshot_manifest(client_id, directions, screens_by_direction=...)` now writes a **v2**
  manifest (`version`, `client_id`, `fixture_version`, `viewports`, `jobs`). v1 input
  (`directions` × `viewports`) is still accepted and normalized into v2 jobs. `validate_prototype.py`
  accepts both: for v1 it checks `directions`; for v2 it derives the direction set from `jobs`.
- **RD2 — Capture is Python-owned; the browser adapter is transport only.** `tooling/visual_qa/` owns
  models, typed errors, and the runner. `tooling/screenshots/capture_web.mjs` is a narrow JSON-in /
  JSON-out headless-browser adapter containing no QA severity, finding, review, or approval logic.
  Domain/capture tests use fake backends; live browser capture is opt-in and never required by CI.
- **RD3 — QA domain/persistence boundary mirrors R1.** `QAFinding` models, typed errors, repository
  *interfaces*, coordinator, and UI live directly under `apps/prototype_app/lib/qa/` (no file I/O).
  File-backed adapters live under `apps/prototype_app/lib/qa/persistence/`. A new
  `test/qa/qa_architecture_test.dart` pins the equivalent guards for `lib/qa` (no `dart:io` outside
  `persistence/`, no runtime/approved-experience writes).
- **RD4 — Model-routing deviation.** The available subagent types are `explore` and `general` only.
  Each cycle uses a fresh `general` implementer and a fresh independent `general` reviewer; a final
  whole-branch `general` reviewer closes the milestone. Cross-package / persistence-sensitive work
  may be implemented directly by the orchestrator with fresh independent review (mirrors C.4–C.7 R4).
- **RD5 — Promotion ordering (create-first with idempotency).** `QaCoordinator.promoteFinding` first
  looks for an existing `FeedbackRecord` whose `originQaFindingId == findingId` and returns it
  (idempotent), otherwise creates feedback through `ReviewCoordinator.createFeedback` with a
  deterministic feedback id derived from the finding id, then persists the promoted finding link.
  A failed feedback creation leaves the finding `triaged` (no partial promotion). One finding can
  never produce two feedback records.
- **RD6 — Severity never implies blocking.** QA severity is QA-only. Promotion takes an explicit
  `blocking` argument defaulting to `false`; the reviewer owns feedback blocking classification
  (C.4 `setBlocking` remains available after promotion). Severity is never mapped to blocking.
- **RD7 — Golden baselines are explicit and reviewer-controlled.** Goldens use Flutter's built-in
  `matchesGoldenFile` (no new dependency, no lockfile change). Baselines are committed under
  `apps/widgetbook/test/golden/goldens/`; they change only via an explicit `--update-goldens`
  invocation performed by a human/reviewer. Tests never rewrite a baseline on mismatch.
- **RD8 — Generated artifacts vs. governed baselines.** Capture PNGs/diffs are gitignored build/CI
  artifacts (`.gitignore` gains capture-output rules). Governed golden baselines and baseline
  metadata that require version history are committed. `pubspec.lock` policy is unchanged: still
  untracked/uncommitted, still not ignored.
- **RD9 — Legacy visual-findings retained.** `visual-findings.yaml`, `validate_visual_findings`, and
  `unresolved_critical_findings` are retained for `tooling/workflow/validate_workflow.py` and
  `tooling/workflow/router.py` and for the demo client. The new canonical QA layout is
  `prototype/qa/findings/<id>.json` (+ `baseline-index.yaml`, `runs/<run>.json`).
  `validate_visual_qa.py` gains v2 validators without removing the legacy ones.
- **RD10 — Visual AI is provider-neutral and offline in CI.** `VisualQaProvider.review(screenshot,
  context, authority_bundle) -> list[candidate]` is an interface. The default implementation is a
  deterministic fixture/fake adapter. Any live model adapter is optional, isolated behind the seam,
  and never required by ordinary tests or CI. No provider/model specifics leak into core QA records.
- **RD11 — Authority hierarchy is serialized explicitly.** The provider request carries an ordered
  `authority_bundle` (approved/current experience → design contract/tokens → accepted baseline →
  linked reference → general heuristics). A lower layer can never be represented as overriding a
  higher one. Findings record `rule_source`, `rule_ref`, and baseline/reference identity.
- **RD12 — `QaCoordinator` never replaces `ReviewCoordinator`.** `QaCoordinator` orchestrates
  capture/golden/AI/dedupe/promotion/recheck only; it delegates all feedback lifecycle to
  `ReviewCoordinator` and never mutates `ReviewState`, approval snapshots, refinement batches, or
  runtime bundles. `ReviewState` gains no QA collection.

## Cycle table

| Cycle | Scope | Status | Commits |
|-------|-------|--------|---------|
| 1 | D.1 deterministic screenshot automation (Tasks 1–3) | PENDING | — |
| 2 | D.2 Visual AI QA + `QAFinding` (Tasks 4–6) | PENDING | — |
| 3 | D.3 golden/Widgetbook + D.4 orchestration + CI (Tasks 7–11) | PENDING | — |

## Progress log

- 2026-09-17 — Preflight complete. Branch `milestone-d-visual-qa` at `9f613dc`; spec + plan present;
  C.4–C.7 baseline green (Python 283 OK, review 581 passing). RD1–RD12 recorded. Untracked
  `pubspec.lock` files intentionally uncommitted.
