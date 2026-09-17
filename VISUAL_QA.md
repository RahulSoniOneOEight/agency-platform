# Visual QA Policy

## Purpose

Code inspection alone is not sufficient for UI approval. Meaningful UI work must be rendered and visually reviewed before it is considered complete.

Milestone D turns this policy into an automated, reproducible QA subsystem: deterministic screenshot capture (D.1), provider-neutral Visual AI QA with structured `QAFinding` records (D.2), governed golden regression coverage (D.3), and orchestration that connects capture, golden comparison, AI review, reviewer promotion, refinement, and re-check (D.4).

## Authority model

| Concern | Authority |
|---|---|
| Automated QA findings | `QAFinding` (`apps/prototype_app/lib/qa/`) — the **sole** automated QA finding authority |
| Human review / feedback | `FeedbackRecord` (C.4) — the human review authority |
| Refinement | `RefinementBatch` (C.7) |
| Approval | `ApprovalSnapshot` (C.5) |
| QA orchestration | `QaCoordinator` |
| Review/refinement orchestration | `ReviewCoordinator` |
| Design rules | Design Contract / B.1D / B.1E (tokens, components, bindings, themes) |
| Runtime | Read-only to QA |

Visual AI may propose findings only. It must never approve or reject an experience, change review status, resolve feedback, create refinement batches, mutate runtime, update baselines, or change approval history.

## Component review

Use `apps/widgetbook/` for reviewing:

- components
- states
- variants
- themes
- density
- responsive behavior at component/pattern level

## Full-screen review

Use `apps/prototype_app/` for reviewing:

- direction A/B/C
- complete screen/pattern composition
- navigation and primary journeys
- responsive layouts
- transaction-model differences
- interactions dependent on real composition

Flutter Web supports stable review URLs:

```text
/?client=<client-id>&direction=a
/?client=<client-id>&direction=b
/?client=<client-id>&direction=c
```

## Standard viewports

Capture/review:

- 360 × 800
- 390 × 844
- 430 × 932
- 768 × 1024
- 1440 × 900

Arbitrary dimensions are allowed only as explicit additional capture jobs, never as silent defaults.

## Screenshot manifest (v2)

`client-projects/<client>/prototype/qa/screenshot-manifest.yaml` is the machine-readable capture plan. Version 2 jobs carry enough information to reproduce a capture exactly:

```yaml
version: 2
client_id: prototype-demo
fixture_version: demo-v1
jobs:
  - surface: prototype          # prototype | widgetbook
    screen: commerce.home       # governed pattern id (prototype jobs)
    state: default              # deterministic fixture/state selector
    direction: b                # a | b | c
    mix_ref: review-state-v2    # optional C.3 mix reference
    viewport: { name: mobile-medium }
    device_scale_factor: 1
```

Widgetbook jobs identify `story` instead of `screen`. v1 manifests (`directions` × `viewports`) still load and are normalized into v2 jobs; new writes are v2 only.

Every artifact records a stable identity: client, surface, screen/story, state, direction/mix, viewport, device scale factor, fixture version, source commit, and a `sha256:` capture id derived from that canonical input (never wall-clock time), plus a content hash of the produced image.

### Capture runner

```text
python -m tooling.prototype.capture_screenshots \
  --manifest client-projects/<client>/prototype/qa/screenshot-manifest.yaml \
  --base-url http://localhost:8080 \
  --commit <sha> \
  --out build/visual-qa/screenshots
```

Add `--dry-run` to print resolved jobs without capturing. Capture writes only under `--out`; a failed capture publishes no PNG and no sidecar metadata.

The transport-only headless-browser adapter is `tooling/screenshots/capture_web.mjs`. It uses a locally installed Node browser driver when available, and otherwise a system Chromium/Chrome/Edge binary (`CHROME_PATH`). Optional higher-fidelity driver setup (never required by CI):

```bash
npm install --no-save playwright && npx playwright install chromium
```

## Structured findings

Two contracts coexist:

1. **Canonical (D.2):** `client-projects/<client>/prototype/qa/findings/<finding-id>.json`, validated against `client-projects/schema/qa-finding.schema.json` (see `templates/qa-finding.json`).

   A `QAFinding` records: stable id, status, severity, category, surface, screen/story, state, direction/mix, section, normalized region, screenshot reference, source commit, `rule_source`/`rule_ref`, baseline reference, summary, evidence, confidence, a stable `dedupe_key`, the promoted `feedback_id`, and an append-only `history`.

   - **Lifecycle:** `detected → triaged → promoted | dismissed | accepted_risk`. History is append-only.
   - **Severity:** `info | minor | major | blocker`. Severity describes QA impact only; it never sets C.4 blocking status.
   - **Deduplication:** repeated discovery of the same issue links evidence to the existing active finding instead of creating duplicates. The dedupe identity excludes severity, confidence, evidence, and source commit.

2. **Legacy (retained):** `client-projects/<client>/prototype/qa/visual-findings.yaml` remains readable for the workflow runtime (`severity` low/medium/high/critical; `status` open/resolved/accepted) and is validated where required. Unresolved critical legacy findings block client review.

## Authority hierarchy for review

Visual AI evaluates in this order, and a lower layer may never override a higher one:

```text
1. Approved experience / current governed review decision
2. Design Contract + generated tokens + governed component rules
3. Accepted golden / prior accepted visual baseline
4. Explicitly linked client/reference screenshots
5. General visual-quality heuristics
```

An approved dense layout is not a defect merely because a generic model prefers more whitespace. Every finding records its provenance (`rule_source`, `rule_ref`, baseline/reference identity, evidence). A single overall "design quality score" is never produced.

## Reviewer promotion

Automated findings do not become client-review state on their own:

```text
ScreenshotArtifact → Visual AI / golden → QAFinding → reviewer promotion → FeedbackRecord
```

Promotion is explicit, reviewer-only, transactional, and idempotent; it preserves the originating `QAFinding` id on the feedback record. Promotion never resolves, reopens, or reclassifies feedback, and QA severity never becomes blocking — the reviewer owns blocking classification.

## Golden policy

Use golden tests for stable, deterministic, high-value surfaces:

- shared components with multiple visual states;
- governed sections/patterns;
- selected representative prototype screens;
- known regression-prone layouts.

Coverage is selective — do not golden every permutation. Goldens live beside their tests (`apps/widgetbook/test/golden/`) and compare against committed baselines. A golden mismatch fails the deterministic QA check, produces diff/evidence metadata, and may produce a `QAFinding` — but it **never** auto-updates the baseline. Baseline creation/update is an explicit reviewer-controlled action (`flutter test --update-goldens` run deliberately by a human/reviewer, reviewed and committed).

## Persistence boundaries

```text
client-projects/<client>/prototype/qa/
  screenshot-manifest.yaml
  findings/<finding-id>.json
  baselines/baseline-index.yaml
  runs/<run-id>.json
```

Generated PNGs/diffs are build/CI artifacts (see `.gitignore`). Governed baselines, baseline metadata, findings, and run records that require version history are committed. Core domain APIs never expose arbitrary mutable map/file access.

## Required loop

```text
OpenCode changes Flutter/config
→ render prototype / Widgetbook
→ deterministic capture from the governed manifest
→ golden comparison + Visual AI structured review
→ QAFinding (deduplicated, provenance recorded)
→ reviewer triage (dismiss / accept risk / promote)
→ FeedbackRecord → C.7 RefinementBatch → OpenCode fix
→ targeted re-capture of affected surfaces + re-check
→ QA evidence appended; unpromoted findings closed when no longer reproducible
→ reviewer resolves/reopens FeedbackRecord (C.4 authority)
```

Targeted re-check maps changed governed screens/sections to affected capture jobs and re-captures only those surfaces.

## CI policy

**Hard deterministic gates** — CI may fail on:

- invalid screenshot manifest;
- capture failure for required canonical jobs;
- golden mismatch where the baseline policy marks the surface as gating;
- invalid QA schemas/contracts (including non-reproducible dedupe keys);
- stale generated Design Contract bindings/themes;
- failing Flutter tests/analyze/build.

**Visual AI policy** — Visual AI findings are surfaced as structured QA output. They do not automatically fail or merge-block solely because a model emitted a finding, and routine PR validation never requires an AI provider secret. A project may configure explicit, deterministic, reviewable policy that promotes certain rule-backed categories to blocking QA gates, but never an opaque model score threshold.

## Completion rule

Do not declare meaningful UI work visually complete solely because Dart analysis or unit tests pass. Required visual artifacts must exist, deterministic QA must pass, and no unresolved critical findings may remain.

## Relationship to AGENTS.md

`AGENTS.md` is the master control file. Agents completing meaningful shared or client UI work must read and follow this policy before completion. The binding design authority is `docs/superpowers/specs/2026-09-17-milestone-d-automated-visual-qa-design.md`.
