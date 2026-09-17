# Visual QA

## PURPOSE
Run deterministic capture, golden comparison, and structured visual review on rendered direction prototypes and Widgetbook surfaces, and record findings that a reviewer can triage.

## READ
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/qa/screenshot-manifest.yaml`
- `client-projects/<client>/prototype/qa/baselines/baseline-index.yaml` (when present)
- `VISUAL_QA.md`
- `docs/superpowers/specs/2026-09-17-milestone-d-automated-visual-qa-design.md`
- direction configs and selected resources

## PROCESS
1. Build or serve `apps/prototype_app` for Flutter Web.
2. Capture the governed v2 jobs (A/B/C at 360×800, 390×844, 430×932, 768×1024, 1440×900) with `python -m tooling.prototype.capture_screenshots`; every artifact carries a stable `sha256:` capture id and the source commit.
3. Compare each capture against its governed baseline (`flutter test` goldens for Widgetbook; baseline index metadata for prototype screens). A mismatch produces diff/evidence metadata and never rewrites a baseline.
4. Run the configured Visual AI review through the provider-neutral seam; provider output is schema-validated into `QAFinding` candidates.
5. Deduplicate findings by their stable `dedupe_key`, then let a reviewer triage each finding (`dismiss`, `accept risk`, or `promote`).
6. Promote only the findings the reviewer wants tracked; promotion creates a `FeedbackRecord` carrying `origin_qa_finding_id`.
7. Re-render affected screens after fixes and re-capture only the affected governed surfaces; append the new QA evidence.

## WRITE
- generated PNGs/diffs under `build/visual-qa/` or `client-projects/<client>/prototype/screenshots/` (build/CI artifacts, not committed)
- `client-projects/<client>/prototype/qa/findings/<finding-id>.json` (canonical `QAFinding` records)
- `client-projects/<client>/prototype/qa/runs/<run-id>.json` (QA run metadata)
- `client-projects/<client>/prototype/qa/baselines/baseline-index.yaml` (reviewer-controlled baseline metadata)
- `client-projects/<client>/prototype/qa/visual-findings.yaml` (retained legacy compatibility artifact)
- promoted findings become `FeedbackRecord`s through `QaCoordinator`/`ReviewCoordinator`

## VALIDATE
- `python -m tooling.prototype.validate_visual_qa client-projects/<client>` passes (manifest + v2 findings + legacy findings).
- `python -m tooling.validation.validate_repo` passes.
- Golden tests pass; no baseline was modified by a failing comparison.
- No unresolved critical legacy findings remain before client review.
- Promoted `FeedbackRecord`s remain reviewer-controlled; QA never resolves them.

## DO NOT
- Do not declare UI complete from static analysis alone.
- Do not hide unresolved critical findings.
- Do not let Visual AI approve, reject, resolve, reclassify, or block anything.
- Do not treat QA severity as C.4 blocking.
- Do not auto-update goldens or baselines after a failure.
- Do not require an AI provider secret for routine PR validation.
- Do not change the client strategy merely to make visual QA easier.

## NEXT
`07-client-review.md`

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/06-visual-qa.yaml`.
