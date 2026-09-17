# Milestone D — Automated Visual QA Design

## Purpose

Milestone D turns the repository's existing visual-QA policy into an automated, governed quality system without creating a second review authority. It adds deterministic screenshot capture, golden regression checks, provider-neutral Visual AI review, structured QA findings, Widgetbook/golden expansion, and orchestration into the existing C.4–C.7 review/refinement flow.

The governing rule is:

```text
Flutter / Widgetbook
  ↓
Deterministic Screenshot Capture
  ↓
Golden Regression + Visual AI Review
  ↓
QAFinding
  ↓ reviewer promotion
FeedbackRecord
  ↓
RefinementBatch
  ↓
OpenCode refinement
  ↓
Re-capture + re-check
```

Visual QA may detect and describe problems. It must not self-approve client experience, mutate review authority, or silently rewrite baselines.

## Existing Repository Contract

This milestone extends the existing repository behavior rather than replacing it:

- `VISUAL_QA.md` already requires rendered review, standard viewports, structured findings, re-render after fixes, and golden coverage where stable and valuable.
- `workflows/06-visual-qa.md` already defines screenshot manifests, capture outputs, structured visual findings, and a visual-QA gate before client review.
- `apps/prototype_app/` remains the full-screen review surface.
- `apps/widgetbook/` remains the component/state/variant review surface.
- Runtime, B.1D Design Contract bindings, and B.1E theme/token outputs remain product implementation authorities.
- C.4–C.7 remain review, approval, visual-feedback, and refinement authorities.

Milestone D strengthens these contracts with automation and explicit domain boundaries.

## Scope

Milestone D contains four connected capabilities:

```text
D.1 Screenshot Automation
D.2 Visual AI QA
D.3 Widgetbook + Golden Expansion
D.4 QA Orchestration
```

Recommended implementation packaging is three large cycles:

```text
Cycle 1 — D.1 Screenshot Automation
Cycle 2 — D.2 Visual AI QA
Cycle 3 — D.3 + D.4 Golden Expansion + Orchestration + hardening
```

## Authority Model

Milestone D introduces one new authority:

```text
QAFinding
  → machine/human QA observation authority before promotion
```

Existing authorities remain unchanged:

```text
ReviewState
  → live review decisions/status

FeedbackRecord
  → authoritative review feedback identity + lifecycle

RefinementBatch
  → implementation/refinement execution record

ApprovalSnapshot
  → immutable approved-experience record

Runtime / B.1D / B.1E
  → product implementation authority
```

A `QAFinding` is intentionally weaker than `FeedbackRecord`. A Visual AI or deterministic QA check may create a finding, but only reviewer promotion turns that observation into governed review feedback.

## D.1 — Deterministic Screenshot Automation

### Goal

Produce reproducible screenshots of governed prototype and Widgetbook surfaces from explicit machine-readable capture jobs.

### Capture Inputs

Each screenshot job must resolve an explicit capture context including:

- client ID;
- surface type: prototype or Widgetbook;
- route/screen/story/state;
- direction or mixed-decision context where relevant;
- fixture/data-set version;
- theme/preset identity where relevant;
- viewport preset;
- device-pixel ratio when controlled;
- source commit SHA;
- capture manifest version.

The existing client screenshot manifest under `prototype/qa/` remains the machine-readable job source for prototype captures. Widgetbook receives an equivalent governed capture manifest/registry rather than ad-hoc script arguments.

### Standard Viewports

Retain the existing governed viewports unless a later policy change explicitly replaces them:

```text
360 × 800
390 × 844
430 × 932
768 × 1024
1440 × 900
```

Not every screen must use every viewport. The manifest determines required coverage. The standard set prevents arbitrary viewport proliferation.

### Determinism Requirements

Capture is valid only when the rendered state is deterministic enough for comparison. The runner must control or neutralize, where applicable:

- fixture/demo data;
- animations/transitions;
- timers;
- random values;
- timestamps that affect visible output;
- remote/network-dependent content;
- font loading;
- image loading;
- route/state selection;
- viewport dimensions;
- locale/text direction if surfaced;
- known browser/device scale settings.

A capture should wait for the application-defined settled state rather than relying on a blind arbitrary sleep where a deterministic readiness signal is available.

### Screenshot Identity

Each captured artifact has stable metadata independent of its physical file path. Conceptual identity:

```yaml
capture_id: prototype-demo__home__mixed-v2__390x844__abc123
client_id: prototype-demo
surface: prototype
screen: commerce.home
state: default
experience_ref: review-state-hash-or-approval-ref
viewport:
  width: 390
  height: 844
fixture_version: demo-v3
source_commit_sha: abc123
manifest_version: 2
artifact_ref: ...
```

The exact naming convention may follow repository norms, but identity fields must remain explicit.

### Storage Policy

Generated screenshots are build/QA artifacts by default. Git should contain only artifacts that require governed history, such as:

- golden baselines;
- capture manifests;
- baseline metadata;
- small deterministic test fixtures.

Bulk transient captures should not be committed merely because they were generated.

### Capture Failure

A failed capture returns a typed deterministic result such as:

```text
CaptureJobInvalid
SurfaceNotReady
CaptureTimedOut
ArtifactWriteFailed
UnsupportedViewport
```

Capture failure does not create a false visual finding; it creates QA execution evidence and fails the appropriate deterministic QA gate.

## D.2 — Visual AI QA

### Goal

Use visual reasoning for semantic UI inspection while keeping results structured, attributable, reviewable, and subordinate to explicit product/design authority.

### Provider-Neutral Boundary

Define a provider-neutral Visual AI interface. The core QA domain must not depend on one model/provider.

Conceptually:

```text
VisualQAProvider
  review(VisualQARequest)
  → VisualQAResult
```

The first implementation may use OpenAI vision through the available execution environment, but provider/model details belong in adapter metadata rather than domain semantics.

### Comparison Authority Hierarchy

Visual AI evaluates the rendered screenshot against authority in this order:

```text
1. Approved Experience / active review decision
2. Design Contract + tokens + governed component rules
3. Explicit accepted baseline / golden
4. Explicitly linked client/reference screenshots
5. General visual-quality heuristics
```

Lower layers may not override higher layers. A generic aesthetic preference cannot create a valid contradiction against an intentionally approved experience choice.

Each finding must identify the authority that supports it.

Conceptual examples:

```yaml
rule_source: design_contract
rule_ref: component.product-card.spacing
```

or:

```yaml
rule_source: approved_experience
rule_ref: approval-v2
```

or:

```yaml
rule_source: golden_regression
baseline_ref: home-mobile-v3
```

### Visual AI Review Categories

Visual AI may inspect concrete visual/UX properties such as:

- clipping/overflow;
- unexpected text wrapping;
- alignment and spacing inconsistency;
- visual hierarchy;
- card/tile sizing inconsistency;
- image crop/aspect problems;
- typography hierarchy drift;
- icon inconsistency;
- density mismatches;
- responsive-layout degradation;
- obvious accessibility concerns visible from rendering;
- design-contract/token drift;
- explicitly linked reference mismatch;
- interaction-state clarity when the rendered state provides evidence.

Visual AI should not invent hidden product behavior from screenshots.

### No Overall Design Score

Do not produce a single design-quality score, winner, or opaque pass/fail based only on model judgment. Visual AI emits concrete findings tied to evidence, scope, rule source, and confidence.

## QAFinding Domain Model

### Purpose

`QAFinding` is the structured QA observation produced by deterministic visual checks, Visual AI, or a human QA review before governed promotion into C.4 feedback.

Conceptual shape:

```yaml
id: qa-001
client_id: prototype-demo
source: visual_ai
severity: major
status: detected
screen: commerce.home
section: home.product-grid
capture_ref: capture-123
viewport:
  width: 390
  height: 844
rule_source: design_contract
rule_ref: component.product-card.spacing
summary: Product-card spacing is inconsistent in the second row
region:
  x: 0.10
  y: 0.35
  width: 0.80
  height: 0.22
confidence: 0.91
source_commit_sha: abc123
created_at: ...
history: []
```

### Severity

Use a structured severity vocabulary for QA triage:

```text
info
minor
major
blocker
```

This is QA severity. It does not automatically become C.4 `blocking: true|false`.

When a finding is promoted into `FeedbackRecord`, the reviewer controls the C.4 blocking classification. Existing C.4 defaults may still apply if the reviewer does not explicitly override them.

### Lifecycle

Canonical lifecycle:

```text
detected
→ triaged
→ promoted
   OR dismissed
   OR accepted_risk
```

History is append-only. Repeated automated runs should not create endless duplicate active findings for the same issue.

### Deduplication

A deterministic deduplication key should combine enough stable identity to recognize a recurring issue, conceptually:

```text
client + surface + screen/state + rule_source + rule_ref + normalized region/signature
```

If the same issue is observed again, the system links a new observation/evidence event to the active finding rather than blindly creating another independent record. Materially different issues remain distinct.

### Promotion to FeedbackRecord

Promotion is explicit reviewer action:

```text
QAFinding
→ reviewer promotes
→ FeedbackRecord
```

Rules:

- promotion is idempotent;
- the `FeedbackRecord` records the originating `QAFinding` ID;
- a finding cannot silently create multiple feedback records;
- QA severity does not directly set C.4 blocking authority;
- `FeedbackRecord` remains the authoritative review-feedback lifecycle after promotion;
- later QA reruns may attach evidence but may not resolve/reopen the promoted feedback automatically.

## Visual AI Structured Output Contract

The provider must return a validated schema rather than free-form prose as system-of-record.

A result includes at minimum:

- capture identity;
- provider/model metadata;
- comparison authorities supplied;
- findings list;
- each finding's rule source/reference;
- severity;
- summary/detail;
- optional normalized region;
- confidence/evidence metadata;
- run timestamp/version.

Free-form model explanation may be stored as non-authoritative evidence, but workflow logic consumes only validated structured fields.

Malformed output produces a typed provider/validation failure, not a guessed finding.

## D.3 — Widgetbook + Golden Expansion

### Widgetbook Role

Widgetbook remains the governed component/state review surface for:

- reusable components;
- variants;
- states;
- themes;
- density;
- responsive behavior;
- governed patterns where isolated inspection is meaningful.

Milestone D expands coverage only where it provides high-value regression protection. It does not require exhaustive stories for every internal widget.

### Golden Strategy

Use golden tests for deterministic, high-value visual surfaces. Priority candidates include:

- shared design-system components with meaningful variants;
- high-risk responsive patterns;
- previously regressed layouts;
- governed prototype screens/states where pixel-level stability is valuable;
- accepted states that are costly to inspect manually every change.

Do not make every possible screen/state permutation a golden.

### Baseline Authority

Golden baselines are explicit versioned review assets. A baseline must never silently update because a test failed.

Baseline change flow:

```text
intentional UI change
→ generate candidate baseline
→ inspect diff
→ reviewer accepts baseline update
→ commit new governed baseline
```

Automatic `--update-goldens` behavior must not be part of ordinary CI acceptance.

### Golden Failure

A golden mismatch:

- fails the deterministic golden gate;
- records diff/evidence artifacts where supported;
- may generate/update a `QAFinding` with `rule_source: golden_regression`;
- never rewrites the baseline automatically.

## D.4 — QA Orchestration

### QA Coordinator

Introduce a thin QA orchestration service/coordinator. It coordinates but does not absorb domain authority.

Conceptually:

```text
QA Workflow / CI / OpenCode
  ↓
QACoordinator
  ├─ Capture service
  ├─ Golden comparator
  ├─ VisualQAProvider
  ├─ QAFindingRepository
  └─ ReviewCoordinator promotion boundary
```

Responsibilities include:

- resolve governed capture jobs;
- invoke deterministic capture;
- run golden comparisons where configured;
- invoke Visual AI where configured;
- validate provider output;
- deduplicate/persist QAFindings;
- provide reviewer promotion operation into `FeedbackRecord` through the governed C.4 boundary;
- re-run affected checks after refinement;
- produce machine-readable QA run summaries.

It must not:

- mutate runtime bundles;
- change `ReviewState` decisions;
- resolve/reopen C.4 feedback automatically;
- change C.4 blocking classification;
- update golden baselines automatically;
- create approval snapshots;
- grant production authorization.

## Re-check After Refinement

When C.7 completes a refinement batch affecting visual output:

```text
RefinementBatch ready_for_review/completed
→ determine affected capture jobs
→ re-capture
→ rerun applicable golden checks
→ rerun applicable Visual AI checks
→ update/link QAFinding observations
```

If the original QA issue is no longer reproducible, the QA finding may be marked as such through its QA lifecycle/history, but any promoted `FeedbackRecord` still requires reviewer resolution/reopen according to C.4 authority.

## CI Policy

### Deterministic Gates

The following may hard-fail CI when configured as required:

- invalid screenshot/capture manifest;
- capture runner failure for required jobs;
- golden regression mismatch;
- schema/contract validation failure;
- repository/design-contract freshness failures.

### Visual AI Findings

Visual AI should not become an opaque merge oracle.

AI-generated findings are surfaced as structured QA evidence. They may participate in a blocking policy only when the repository explicitly defines a deterministic policy mapping (for example, reviewer-promoted blocking feedback or an agreed required rule class). Confidence alone must not determine merge/approval.

### Provider Availability

Where Visual AI provider execution is unavailable, deterministic QA checks still run. The workflow must distinguish:

```text
AI review passed with no findings
AI review produced findings
AI review unavailable/skipped under policy
AI review execution failed
```

These states must not be collapsed into a false pass.

## Persistence

Introduce a dedicated repository abstraction:

```text
QAFindingRepository → QAFinding
```

Initial storage may be file-backed and client-scoped, following repository conventions, for example:

```text
client-projects/<client>/prototype/qa/
  screenshot-manifest.yaml
  qa-run-index.json
  findings/
    qa-001.json
```

The exact physical format should follow implementation conventions. Record identity and lifecycle semantics matter more than YAML vs JSON.

Generated bulk screenshots and image diffs may live as CI/local artifacts referenced from records.

## Typed Domain Errors

Use stable machine-readable errors, including equivalents of:

```text
InvalidCaptureManifest
CaptureJobInvalid
CaptureTimedOut
SurfaceNotReady
GoldenBaselineMissing
GoldenMismatch
InvalidQAProviderResult
UnsupportedQAProvider
InvalidQAFindingTransition
DuplicateQAFindingPromotion
QAFindingNotPromotable
InvalidQAFindingRegion
InvalidRuleAuthority
```

Invalid cross-domain operations are transactional: no half-written promotion, no baseline mutation, no silent lifecycle mutation.

## Transactional Guarantees

Key operations must validate the complete candidate before committing authoritative state.

Examples:

### Finding persistence

```text
validate structured finding
→ compute dedupe identity
→ resolve existing/open record or new record
→ persist observation/history atomically where storage permits
```

### Promotion

```text
validate finding promotable
→ validate target FeedbackRecord candidate
→ create feedback through ReviewCoordinator
→ persist promotion link/idempotency marker
```

A failure must not leave multiple feedback records or a finding falsely marked promoted.

### Baseline change

```text
candidate golden generated
→ reviewer acceptance
→ baseline update
```

No automated comparison failure may directly mutate the baseline.

## Interaction with C.4–C.7

Milestone D must preserve these boundaries:

```text
QAFinding
  = QA observation

FeedbackRecord
  = governed review feedback

RefinementBatch
  = implementation/refinement work

ApprovalSnapshot
  = immutable approved experience
```

Promotion links D into C.4. Re-check links C.7 back into D. No circular mutation of authority is permitted.

Visual QA may read approval/current-review context as comparison authority, but it does not edit those records.

## Design Contract Integration

Visual QA reads generated/current B.1D/B.1E authority rather than duplicating rules.

Examples of inputs may include:

- governed component bindings;
- allowed density/variant information;
- generated theme/token values;
- screen/section registry;
- approved/current decision tree.

If an AI finding claims a design-contract violation, it must identify a real contract rule/reference supplied to the review job.

## Reference Image Handling

Client/reference screenshots are optional secondary comparison authority.

Rules:

- a reference must be explicitly linked to a screen/state or governed comparison context;
- Visual AI must not search arbitrary references and infer the intended target automatically;
- reference identity is stored with the QA request/finding;
- references never outrank explicit approved experience or design-contract authority.

## Security and Privacy Boundary

Visual QA artifacts may contain client UI or synthetic/demo data. The system should avoid capturing secrets, credentials, admin tokens, or unrelated personal data in screenshots.

Provider adapters receive only the artifacts/context needed for the configured QA job. Production/customer-sensitive data integration belongs to later productionization policy.

## Testing Strategy

### D.1 Capture tests

Cover:

- capture-manifest schema;
- governed viewport validation;
- deterministic capture identity;
- route/state/direction resolution;
- stable fixture selection;
- invalid job failures;
- settled-state timeout behavior;
- artifact metadata generation.

### D.2 Visual AI / QAFinding tests

Cover:

- provider-neutral request/result mapping;
- strict structured-output validation;
- authority hierarchy preservation;
- normalized region validation;
- severity/status validation;
- deduplication;
- lifecycle transitions;
- idempotent reviewer promotion;
- provider inability to mutate FeedbackRecord directly;
- no automatic C.4 blocking change.

### D.3 Golden tests

Cover:

- high-value Widgetbook component states;
- selected responsive patterns;
- baseline lookup;
- mismatch failure;
- candidate diff evidence;
- no automatic baseline rewrite.

### D.4 Coordinator/integration tests

Cover:

- manifest → capture → golden/AI → QAFinding;
- repeated run dedupe;
- reviewer promotion → FeedbackRecord;
- refinement → re-capture/re-check;
- fixed QA issue does not auto-resolve promoted feedback;
- deterministic CI failures remain distinct from AI provider unavailable/failure states;
- C.3–C.7 regression behavior remains intact.

### End-to-End Scenario

Prove at least this path:

```text
C.3 mixed experience
→ deterministic mobile + desktop capture
→ golden comparison
→ Visual AI review
→ QA finding for governed issue
→ reviewer triage/promotes
→ C.4 FeedbackRecord created
→ reviewer creates C.7 RefinementBatch
→ OpenCode fixes
→ required validation passes
→ re-capture
→ golden passes
→ Visual AI no longer reproduces issue
→ QAFinding records successful re-check
→ reviewer resolves promoted feedback
→ normal C.5 approval rules continue unchanged
```

## Workflow Integration

Update the existing visual-QA workflow contract rather than creating a parallel workflow.

`workflows/06-visual-qa.md` should evolve from a largely manual process into the orchestrated D flow while retaining its position before client review.

The workflow should explicitly distinguish:

- deterministic capture/golden failures;
- structured AI findings;
- triage state;
- promoted feedback;
- re-check results;
- completion gate.

## Non-Goals

Milestone D does not implement:

- autonomous client approval;
- automatic C.4 feedback resolution;
- automatic C.4 blocking downgrade;
- automatic golden baseline rewriting;
- a generic issue-tracking system;
- a generic computer-vision platform;
- production deployment;
- production authorization;
- production observability;
- client-data backend integration;
- a single visual quality score;
- arbitrary provider/model-specific logic in the core domain.

## Success Criteria

Milestone D is complete when:

1. governed Flutter/Widgetbook screenshots can be captured deterministically from machine-readable jobs;
2. capture identity records client/surface/state/viewport/source commit/fixture context;
3. high-value golden baselines are explicit and never auto-updated;
4. Visual AI runs through a provider-neutral structured contract;
5. comparison authority prioritizes approved experience and Design Contract over generic aesthetics;
6. Visual AI creates `QAFinding`, not `FeedbackRecord`;
7. `QAFinding` has stable identity, severity, lifecycle, provenance, evidence, and deduplication;
8. reviewer promotion to C.4 feedback is explicit, transactional, and idempotent;
9. AI/provider execution cannot resolve feedback, change blocking, mutate ReviewState, alter approvals, or rewrite baselines;
10. refinement-triggered re-checks rerun affected capture/golden/AI jobs;
11. deterministic CI gates and AI-provider states are represented distinctly;
12. Widgetbook/golden coverage expands selectively around high-value regression surfaces;
13. the existing `VISUAL_QA.md` and `workflows/06-visual-qa.md` contracts are upgraded rather than bypassed;
14. C.3–C.7 authority and regression tests remain intact.

## Downstream Boundary

The already approved roadmap after D is:

```text
E. Workflow Hardening
→ F. End-to-End Reference Client
→ G. Production Authorization
→ H. Productionization
```

Those stages may consume D's durable QA artifacts and findings, but Milestone D does not implement their production/release responsibilities.
