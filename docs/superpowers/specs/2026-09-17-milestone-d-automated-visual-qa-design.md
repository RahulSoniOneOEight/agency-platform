# Milestone D — Automated Visual QA Design

## Purpose

Milestone D turns the existing Visual QA policy into an automated, reproducible QA subsystem that works with the Flutter prototype, Widgetbook, the Design Contract, and the C.4–C.7 review/refinement system.

The milestone contains:

- D.1 deterministic screenshot automation;
- D.2 provider-neutral Visual AI QA and structured `QAFinding` records;
- D.3 expanded Widgetbook and high-value golden regression coverage;
- D.4 orchestration that connects capture, golden comparison, AI review, reviewer triage, feedback promotion, refinement, and re-check.

The design extends the repository’s existing `VISUAL_QA.md` contract. It does not create a parallel review system or replace human approval.

## Governing Principles

1. Rendered Flutter output is the object of QA; code inspection alone is insufficient.
2. `QAFinding` is the sole automated-QA finding authority.
3. `FeedbackRecord` remains the human review/feedback authority.
4. Visual AI may propose findings; it may not approve, reject, resolve, reopen, alter blocking status, or mutate approval records.
5. Baselines are explicit and reviewer-controlled. Automated failures never rewrite goldens or accepted screenshots.
6. The existing B.1D/B.1E Design Contract and generated tokens remain the design-rule authority.
7. Runtime bundles remain read-only from the QA subsystem.
8. CI can enforce deterministic failures, but Visual AI is not an opaque merge oracle.

## End-to-End Architecture

```text
Flutter prototype / Widgetbook
        ↓
Deterministic render fixture
        ↓
Screenshot Capture
        ↓
┌──────────────────────────────┐
│ Golden comparison            │
│ Visual AI structured review  │
└──────────────────────────────┘
        ↓
QAFinding
        ↓
Reviewer triage
   ├─ dismiss
   ├─ accept risk
   └─ promote
        ↓
FeedbackRecord
        ↓
RefinementBatch
        ↓
OpenCode implementation
        ↓
Re-capture + re-check
```

## D.1 — Deterministic Screenshot Automation

### Capture authority

D.1 implements the existing screenshot-manifest contract under client `prototype/qa/`. Capture jobs are deterministic inputs, not ad-hoc browser actions.

A capture job identifies at minimum:

```yaml
client_id: prototype-demo
surface: prototype
screen: commerce.home
state: default
direction: b
mix_ref: review-state-v2
viewport:
  width: 390
  height: 844
device_scale_factor: 1
fixture_version: demo-v1
source_commit_sha: abc123
```

Widgetbook jobs identify component/story/state instead of full-screen route composition.

### Governed viewport presets

Retain the standard viewport set already defined in `VISUAL_QA.md`:

- 360 × 800
- 390 × 844
- 430 × 932
- 768 × 1024
- 1440 × 900

Clients may select a relevant subset. Arbitrary dimensions are allowed only as explicit additional capture jobs, never as silent defaults.

### Determinism requirements

Capture must control or normalize:

- fixture/demo data;
- route/screen/state;
- direction and C.3 mix state;
- viewport and device-scale factor;
- fonts and local assets required for rendering;
- animation settling;
- loading/async completion where deterministic fixtures are used;
- locale/text scaling when applicable;
- source commit identity.

Network-dependent content must not make canonical captures nondeterministic. Canonical QA uses deterministic fixtures or stable local test doubles.

### Screenshot identity

Every screenshot artifact has stable metadata including:

- client;
- surface (`prototype` or `widgetbook`);
- screen/story/state;
- direction/mix identity;
- viewport;
- fixture version;
- source commit;
- capture timestamp;
- content/artifact hash where available.

Generated screenshots are QA/build artifacts. Only governed baselines and metadata that require version history belong in Git.

### Capture failure

A failed capture returns a typed capture error and produces no successful screenshot record. Partial or stale images must not be presented as current evidence.

## D.2 — Visual AI QA

### Separate automated finding model

Visual AI creates `QAFinding`, not `FeedbackRecord`.

Canonical promotion flow:

```text
Visual AI
→ QAFinding
→ reviewer accepts/promotes
→ FeedbackRecord
→ RefinementBatch
```

This prevents automated QA noise from becoming authoritative client-review state.

### QAFinding model

A finding records at minimum:

```yaml
id: qa-001
status: detected
severity: major
category: spacing
screen: commerce.home
section: home.product-grid
viewport: 390x844
screenshot_ref: capture-...
source_commit_sha: abc123
rule_source: design_contract
rule_ref: spacing.card.gap
summary: "Product-card spacing is inconsistent with the governed token."
evidence:
  - region: {x: 0.10, y: 0.42, width: 0.80, height: 0.24}
confidence: 0.91
history: []
```

### Finding lifecycle

```text
detected
→ triaged
→ promoted | dismissed | accepted_risk
```

History is append-only. Promotion stores the resulting `FeedbackRecord` ID and must be idempotent.

### Severity

Use structured QA severity:

```text
info
minor
major
blocker
```

Severity describes QA impact. It does not automatically set C.4 blocking status. When a finding is promoted, the reviewer owns feedback blocking classification; existing C.4 defaults may apply.

### Comparison authority hierarchy

Visual AI evaluates in this order:

```text
1. Approved experience / current governed review decision
2. Design Contract + generated tokens + governed component rules
3. Accepted golden / prior accepted visual baseline
4. Explicitly linked client/reference screenshots
5. General visual-quality heuristics
```

A lower-level heuristic may not override an intentional higher-level approved decision. For example, an approved dense layout is not a defect merely because a generic model prefers more whitespace.

Every finding records its provenance through `rule_source`, `rule_ref`, baseline/reference identity, and evidence.

### Visual AI responsibilities

Visual AI may detect concrete issues such as:

- clipping/overflow;
- text wrapping defects;
- spacing/alignment inconsistencies;
- hierarchy problems;
- inconsistent component sizing;
- image aspect/cropping problems;
- responsive breakage;
- density drift;
- design-token/design-contract violations;
- icon/typography inconsistency;
- obvious accessibility presentation problems;
- mismatch with explicitly linked approved/reference visuals.

It must not produce a single overall “design quality score.” Findings must be concrete, scoped, and evidence-backed.

### Provider-neutral Visual AI interface

Define a provider-neutral review interface. The first implementation may use OpenAI vision, but core records must not depend on OpenAI-specific payloads.

Conceptually:

```text
VisualQaProvider.review(
  screenshot,
  context,
  authority_bundle,
) -> List<QAFindingCandidate>
```

Provider output must be schema-validated before persistence. Free-form model prose is not the system of record.

## Finding Deduplication

Repeated execution should not generate endless duplicate findings.

Use a stable deduplication identity derived from relevant fields such as:

- client;
- screen/story;
- rule source/ref;
- issue category;
- normalized region/section;
- active baseline/reference identity.

When the same issue is rediscovered, the run links new evidence to the existing non-terminal finding or creates a recurrence event according to repository rules.

## D.3 — Widgetbook + Golden Expansion

### Widgetbook role

Widgetbook remains the governed component/state review surface for:

- components;
- states;
- variants;
- themes;
- density;
- responsive component/pattern behavior.

D.3 expands coverage only where it protects reusable/high-risk UI. Do not create stories or goldens for every possible permutation.

### Golden policy

Use golden tests for stable, deterministic, high-value surfaces such as:

- shared components with multiple visual states;
- governed sections/patterns;
- selected representative prototype screens;
- known regression-prone layouts.

Golden comparison is deterministic regression detection, not aesthetic judgment.

A golden mismatch:

- fails the deterministic QA check according to CI policy;
- produces diff/evidence artifacts;
- may produce a `QAFinding` through D.4;
- never auto-updates the baseline.

### Baseline governance

Baseline creation/update is an explicit reviewer-controlled action. Baselines are versioned and tied to the surface/state/viewport they represent.

Accepted baselines must retain enough metadata to identify:

- capture identity;
- source commit;
- fixture version;
- viewport;
- review/approval context where applicable.

## D.4 — QA Orchestration

### QaCoordinator

Introduce a thin orchestration layer responsible for cross-domain QA flow.

```text
QA runner / CI / reviewer UI
        ↓
QaCoordinator
   ├─ ScreenshotCapture
   ├─ GoldenComparator
   ├─ VisualQaProvider
   ├─ QAFindingRepository
   └─ ReviewCoordinator (promotion boundary only)
```

`QaCoordinator` does not replace `ReviewCoordinator`.

Responsibilities include:

- execute governed capture jobs;
- validate screenshot metadata;
- run configured golden comparisons;
- run configured Visual AI checks;
- normalize/deduplicate findings;
- persist QA evidence;
- expose reviewer triage operations;
- promote a finding to `FeedbackRecord` transactionally;
- re-run affected checks after refinement.

### Promotion into C.4

Promotion is explicit and reviewer-controlled.

```text
QAFinding(promoted)
     ↕ atomic link
FeedbackRecord(origin_qa_finding_id=...)
```

Promotion must be idempotent. Repeating the same promotion cannot create multiple feedback records.

`QAFinding` remains the automated QA record; `FeedbackRecord` becomes the authoritative human review item after promotion.

### Re-check after refinement

When a C.7 refinement batch changes a relevant screen/component:

1. identify affected capture jobs;
2. recapture affected screenshots;
3. rerun relevant golden/AI checks;
4. append new QA evidence;
5. mark unpromoted findings as no longer reproducible when appropriate;
6. never auto-resolve promoted `FeedbackRecord` items — C.4 reviewer authority remains intact.

## Persistence Boundaries

Use separate QA records/repositories:

```text
ScreenshotManifest / capture metadata
QAFindingRepository
Golden baseline metadata
QA run metadata
```

A practical client layout may be:

```text
client-projects/<client>/prototype/qa/
  screenshot-manifest.yaml
  findings/
    qa-001.json
  baselines/
    baseline-index.yaml
  runs/
    run-001.json
```

Generated PNGs/diffs may live in build/CI artifact storage unless explicitly promoted to governed baseline/reference evidence.

Core domain APIs must not expose arbitrary mutable map/file access.

## CI Policy

### Hard deterministic gates

CI may fail on deterministic issues such as:

- invalid screenshot manifest;
- capture failure for required canonical jobs;
- golden mismatch where the baseline policy marks the surface as gating;
- invalid QA schemas/contracts;
- stale generated Design Contract bindings/themes;
- failing Flutter tests/analyze/build.

### Visual AI policy

Visual AI findings are surfaced as structured QA output. They do not automatically fail/merge-block solely because a model emitted a finding.

A project may configure explicit policy that promotes certain rule-backed categories to blocking QA gates, but that policy must be deterministic and reviewable; it must not be an opaque model score threshold.

## Error Handling

Use typed machine-readable errors, including equivalents of:

```text
InvalidCaptureJob
CaptureFailed
CaptureNotDeterministic
InvalidScreenshotMetadata
GoldenBaselineMissing
GoldenMismatch
InvalidQaFinding
InvalidQaTransition
VisualQaProviderFailure
VisualQaSchemaInvalid
DuplicateFindingPromotion
QaFindingNotPromotable
QaEvidenceMissing
```

Invalid operations are transactional:

```text
failure
→ no false successful capture
→ no partial finding promotion
→ no baseline rewrite
→ no ReviewState mutation
→ no FeedbackRecord mutation unless promotion fully succeeds
```

## Testing Strategy

### D.1 tests

Cover:

- manifest parsing/validation;
- governed viewport resolution;
- stable capture identity;
- deterministic fixture/state selection;
- invalid route/state/direction rejection;
- capture failure semantics;
- screenshot metadata serialization.

### D.2 tests

Cover:

- schema-valid provider output;
- malformed provider output rejection;
- authority hierarchy/provenance recording;
- normalized evidence regions;
- finding lifecycle;
- severity semantics;
- deduplication;
- provider neutrality;
- no direct FeedbackRecord mutation.

### D.3 tests

Cover:

- Widgetbook representative states;
- golden baseline identity;
- deterministic golden comparison;
- diff/evidence generation;
- baseline update authorization;
- no automatic baseline rewrite.

### D.4 tests

Cover:

- full QA run orchestration;
- finding persistence/deduplication;
- explicit idempotent promotion into `FeedbackRecord`;
- re-check after refinement;
- unpromoted-finding closure/no-longer-reproducible behavior;
- promoted feedback remains reviewer-controlled;
- C.4–C.7 regression behavior remains intact.

### End-to-end scenario

```text
render selected/mixed C.3 experience
→ deterministic capture
→ golden + AI checks
→ QAFinding created
→ reviewer promotes finding
→ FeedbackRecord created
→ reviewer creates C.7 refinement batch
→ OpenCode fixes
→ validation passes
→ recapture
→ QA checks pass
→ QA finding no longer reproducible / triaged accordingly
→ reviewer resolves FeedbackRecord
```

## Implementation Packaging

Implement in three large cycles:

```text
Cycle 1 — D.1 Screenshot Automation
  deterministic capture contract + runner + metadata + tests

Cycle 2 — D.2 Visual AI QA
  QAFinding + provider-neutral review + provenance + dedupe + tests

Cycle 3 — D.3 + D.4
  Widgetbook/golden expansion + QA orchestration + C.4–C.7 integration + CI hardening
```

Each cycle uses TDD, an independent reviewer gate, and a final whole-branch review.

## Non-Goals

Milestone D does not implement:

- autonomous client approval;
- automatic feedback resolution;
- automatic blocking downgrade;
- automatic golden/baseline rewriting;
- a single visual-quality score;
- generic issue-tracker synchronization;
- production deployment;
- full design generation;
- a generic workflow engine;
- E/H production workflow concerns beyond the integration seam required by D.

## Success Criteria

Milestone D is complete when:

1. required Flutter/Widgetbook surfaces can be captured reproducibly from governed manifests;
2. screenshot evidence is identity-rich and traceable to source state/commit;
3. deterministic golden regressions are detected without automatic baseline rewriting;
4. Visual AI outputs schema-valid, provider-neutral `QAFinding` records with explicit provenance;
5. automated findings remain separate from `FeedbackRecord` until reviewer promotion;
6. promotion is explicit, transactional, idempotent, and traceable;
7. existing C.4–C.7 authority boundaries remain intact;
8. refinement can trigger targeted re-capture/re-check without automatic feedback resolution;
9. CI distinguishes deterministic hard gates from reviewer-triaged AI findings;
10. all D.1–D.4 flows are covered by focused and end-to-end tests.
