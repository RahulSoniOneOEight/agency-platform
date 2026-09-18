# Milestone F — End-to-End Reference Client Design

**Date:** 2026-09-18

## Status

Approved architecture pending written-spec review.

## Purpose

Milestone F proves that the capabilities delivered across Milestones B through E operate as one coherent agency delivery system by running a realistic, deterministic reference client through the complete workflow.

Milestone F does **not** introduce a new platform authority or a new generic subsystem. It creates a canonical executable regression fixture that exercises the existing authorities, contracts, workflows, validators, review model, visual QA, and workflow-hardening runtime end to end.

The target proof is:

```text
Client intake
  ↓
Product / UX contract
  ↓
Resource and reference intelligence
  ↓
3 experience directions
  ↓
Flutter prototype
  ↓
Compare / Select / Mix
  ↓
Client review
  ↓
Feedback + visual annotation
  ↓
RefinementBatch
  ↓
ApprovalSnapshot v1
  ↓
Automated visual QA
  ↓
Workflow completion
  ↓
Post-approval change scenarios
  ├─ contract-impacting → new review + ApprovalSnapshot v2
  └─ implementation-only → QA/regression rerun without unnecessary reapproval
```

## Goals

1. Prove the full B–E platform against one realistic client fixture.
2. Make the complete agency workflow reproducible from repository state alone.
3. Exercise both B2C and B2B commerce flows using synthetic deterministic data.
4. Prove three meaningful experience directions, not cosmetic theme variants.
5. Exercise comparison, selection, and mixed-direction review decisions.
6. Exercise blocking and non-blocking feedback, visual annotations, refinement batches, and approval.
7. Exercise Milestone D screenshot/golden/visual-QA flows.
8. Exercise Milestone E resume, retry, checkpoint, evidence, and validator semantics.
9. Prove correct behavior for both contract-impacting and implementation-only post-approval changes.
10. Produce machine-readable and human-readable end-to-end evidence without introducing a subjective overall score.

## Non-goals

- No real client data or PII.
- No live production deployment.
- No new approval authority.
- No new release authorization authority; that belongs to Milestone G.
- No production backend replacement; that belongs to Milestone H.
- No autonomous client approval.
- No generic test-case management platform.
- No generic BPM engine.
- No second review or QA model parallel to Milestones C and D.
- No redesign of the existing Flutter runtime, design contract, workflow runtime, or domain authorities unless a blocking defect is discovered while proving the reference client.

---

# 1. Reference client profile

Milestone F uses one synthetic B2C + B2B commerce client as the canonical reference fixture.

The client should be realistic enough to exercise the agency platform but bounded enough to remain deterministic and maintainable.

Recommended profile:

```text
Reference client: synthetic commerce business
Channels: B2C + B2B
Catalogue: multi-category physical products
Commercial modes:
  - standard retail purchase
  - bulk / trade purchase
  - quotation / RFQ
  - credit-aware B2B ordering
```

All names, products, customers, prices, inventory, promotions, quotes, limits, orders, and other records must be synthetic.

## Required experience scope

The canonical reference client must cover at least:

- Home
- PLP / category
- Search
- PDP
- Cart
- Checkout
- B2B quotation / RFQ
- B2B credit or account visibility
- B2B order conversion

Optional secondary flows may be added only where they materially prove an existing platform capability.

---

# 2. Deterministic fixture data

The reference client is a regression fixture, so its data must be deterministic and versioned.

The fixture should include enough data to prove:

- categories and collections
- products and variants
- stock/inventory states
- standard retail prices
- B2B pricing or quantity breaks
- promotions
- customer/account types
- credit limits / available credit
- quotations / RFQs
- carts and orders
- representative validation/error states

## Fixture rules

- No random runtime data unless a fixed seed is part of the fixture contract.
- Fixture version must be explicit.
- A given fixture version + source commit + workflow input must reproduce the same expected state.
- Fixture changes that alter approved experience behavior are treated as contract-impacting until reviewed.
- Fixtures must be reusable across Flutter runtime tests, screenshot capture, visual QA, and end-to-end assertions where practical.

---

# 3. Experience directions

The reference client must exercise three materially different experience directions while staying within the same shared design system and Flutter implementation.

## Direction A — Efficient Commerce

Intent:
- compact presentation
- search/category led navigation
- high information density
- fast repeat-purchase flow

## Direction B — Premium Discovery

Intent:
- editorial home
- larger imagery
- curated collections
- stronger visual storytelling

## Direction C — Trade First

Intent:
- B2B-oriented merchandising
- MOQ / bulk cues
- quotation and credit visibility
- efficiency-focused ordering

## Direction rules

- Directions are implemented as controlled variants/pattern choices, not duplicated apps.
- Differences must be meaningful enough to make Compare / Select / Mix useful.
- All directions remain governed by the same Design Contract, tokens, components, patterns, and runtime authorities.
- A direction may influence content density, merchandising emphasis, component variants, section composition, and workflow emphasis.
- A direction must not silently introduce an unsupported business capability merely to create visible differentiation.

---

# 4. Canonical authority boundaries

Milestone F preserves all previously established authorities.

```text
workflow-state.yaml
  = canonical current workflow checkpoint

ReviewState
  = current live review decisions/status

FeedbackRecord
  = human review feedback authority

RefinementBatch
  = refinement execution/audit authority

ApprovalSnapshot
  = immutable approved experience authority

QAFinding
  = automated visual-QA finding authority

Design Contract / B.1D / B.1E
  = design-rule and theme authority

Reference Client Fixture
  = regression scenario + deterministic evidence only
```

The reference client fixture must never become a second source of truth for review, approval, QA, runtime, or workflow state.

---

# 5. Reference client repository structure

The canonical client should live under one normal client-project directory and use the same structures as real projects.

Recommended structure:

```text
client-projects/reference-commerce/
├── intake/
├── intelligence/
├── directions/
├── prototype/
├── review/
├── approval/
├── workflow-state.yaml
└── reference-e2e/
    ├── scenario.yaml
    ├── assertions.yaml
    ├── evidence/
    └── report/
```

The exact directory names may follow current repository conventions during implementation, but these authority rules are binding:

- Existing domain locations remain authoritative.
- `reference-e2e/` contains scenario orchestration, assertions, and evidence references only.
- It must not copy or rewrite domain records into parallel formats when a canonical record already exists.

---

# 6. End-to-end scenario

The canonical scenario must exercise the normal agency flow in order.

## 6.1 Intake and product contract

The scenario begins with a realistic client brief and structured intake sufficient to drive:

- client context
- B2C / B2B requirements
- target users
- primary journeys
- required screens
- brand/experience constraints
- selected reference/resource inputs

The Product / UX Contract must be generated or resolved using the normal platform flow rather than hard-coded downstream shortcuts.

## 6.2 Resource and reference intelligence

The reference client should exercise the existing resource intelligence / normalization process using curated, approved reference inputs.

The scenario must prove:

- provenance is preserved
- unsuitable references do not enter the client implementation directly
- selected patterns/components are normalized into the agency design system

## 6.3 Directions and Flutter prototype

The system must produce three directions and render them through the existing configurable Flutter prototype runtime.

The prototype must support the reference client's required screens and B2B/B2C paths with deterministic fixture data.

## 6.4 Compare / Select / Mix

The scenario must use the actual review decision model:

- compare directions
- select an overall direction
- apply at least one valid screen-level override
- apply at least one valid governed section-level override where supported

The resulting mixed experience must remain representable by the existing C.3 decision hierarchy.

## 6.5 Feedback and refinement

The scenario must create representative feedback covering:

- at least one blocking FeedbackRecord
- at least one non-blocking FeedbackRecord
- at least one visual annotation
- at least one contract-impacting refinement item
- at least one implementation-only refinement item across the full milestone scenario

Feedback lifecycle must remain controlled by the existing C.4–C.7 rules.

## 6.6 Approval v1

After blocking review feedback is resolved and the round is explicitly closed, the client flow must create a valid ApprovalSnapshot v1 using the existing approval rules.

The snapshot must pin the required review state identity and source commit evidence.

## 6.7 Automated visual QA

The approved/refined experience must pass through the Milestone D QA flow:

```text
Flutter / Widgetbook
  ↓
deterministic capture
  ↓
golden and/or provider-neutral visual QA
  ↓
QAFinding
  ↓
reviewer triage / promotion where applicable
```

The scenario should include at least one representative QA finding path so that the QA-to-review boundary is exercised rather than merely skipped.

## 6.8 Workflow hardening

The scenario must execute under Milestone E workflow semantics, including:

- prerequisites
- client lease where state mutation applies
- attempt identity
- artifact manifest/evidence
- validators
- checkpoint advancement
- deterministic resume from repository state

At least one controlled interruption/retry/resume path must be tested to prove that a fresh OpenCode session can continue safely from the last known-good checkpoint.

---

# 7. Post-approval change scenarios

Milestone F must explicitly prove both sides of the approval boundary.

## 7.1 Contract-impacting change

After ApprovalSnapshot v1, introduce one deterministic change that alters the approved experience contract.

Examples:
- selected direction/mix change
- governed screen/section behavior change
- approved user journey change

Expected behavior:

```text
approved v1
  ↓
contract-impacting change
  ↓
new review round required
  ↓
blocking review rules apply
  ↓
new explicit final review close
  ↓
ApprovalSnapshot v2
```

The prior approval remains immutable and historically valid for its pinned source state.

## 7.2 Implementation-only change

Introduce one deterministic implementation change that does not alter the approved experience contract.

Examples:
- internal refactor
- non-visible bug fix preserving approved behavior
- implementation hardening under existing contract

Expected behavior:

```text
approved experience unchanged
  ↓
implementation-only change
  ↓
relevant tests / QA rerun
  ↓
no unnecessary new approval version
```

If the implementation-only classification is uncertain, the safer classification is contract-impacting.

---

# 8. Machine-readable scenario and assertions

The reference client must have a machine-readable scenario definition and deterministic assertions.

Conceptual `scenario.yaml`:

```yaml
version: 1
client_id: reference-commerce
fixture_version: 1
scenarios:
  - id: normal-happy-path
  - id: contract-change-reapproval
  - id: implementation-only-change
  - id: resume-after-interruption
```

Conceptual assertions may include:

- expected workflow stage transitions
- expected direction IDs
- expected selected/mixed review decisions
- expected feedback lifecycle outcomes
- expected approval version count
- expected approval source SHA/hash relationships
- expected QA finding lifecycle outcomes
- expected validator outcomes
- expected artifact/evidence references

Assertions must inspect canonical domain records rather than rely on duplicate state copied into the E2E fixture.

---

# 9. Evidence and reports

Milestone F produces two complementary reports.

## 9.1 Machine E2E report

Machine-readable report containing at least:

- client ID
- fixture version
- scenario IDs
- source commit SHA
- workflow attempt IDs
- validator outcomes
- artifact/evidence refs
- review round identities
- approval versions
- QA outcomes
- assertion pass/fail results

The machine report must not collapse the programme into an overall subjective design score.

## 9.2 Human reference report

Human-readable report summarizing:

- client context
- B2C/B2B scope
- three directions
- chosen direction/mix
- feedback/refinement story
- ApprovalSnapshot v1
- QA flow
- contract-impacting change and ApprovalSnapshot v2
- implementation-only change behavior
- resume/retry proof
- screenshots/evidence references
- known limitations and intentionally unproven areas

The human report is explanatory evidence, not a replacement for machine assertions.

---

# 10. Workflow and CI integration

Milestone F is a canonical regression fixture and should be runnable in a deterministic validation mode.

CI should be able to validate the machine-readable fixture and assertions without requiring a human client session.

CI may:

- validate fixture/schema integrity
- run deterministic scenario assertions
- run relevant Flutter/unit/integration tests
- run screenshot/golden checks appropriate to normal CI
- validate workflow manifests/state

CI must not:

- create ApprovalSnapshots autonomously in production/client workflows
- mutate live workflow state as an authority
- grant production authorization
- update golden baselines automatically
- require live Visual AI credentials for ordinary deterministic validation

Where scenario setup needs approval/feedback records, use deterministic test fixtures or controlled test orchestration that preserves the same domain invariants.

---

# 11. Error and failure semantics

The reference scenario must fail loudly when the platform violates an authority boundary or expected invariant.

Representative errors should cover:

- invalid fixture version
- missing required fixture data
- invalid direction contract
- invalid review decision tree
- unresolved blocking feedback at approval
- approval version mismatch
- QA evidence missing
- unexpected workflow transition
- validator failure
- stale or mismatched source commit
- forbidden duplicate authority record
- non-deterministic scenario output

A failed scenario must preserve evidence sufficient to identify the failing stage and must not silently mark the workflow complete.

---

# 12. Testing strategy

Milestone F testing is layered.

## 12.1 Fixture and schema tests

Validate:
- deterministic fixture content
- schema compliance
- stable IDs
- versioning
- required B2C/B2B coverage

## 12.2 Domain regression tests

Re-run existing authoritative tests for:
- C.3 selection/mixing
- C.4–C.7 feedback/refinement/approval
- D QAFinding/QA coordination
- E workflow runtime/hardening

## 12.3 End-to-end scenario tests

Prove:
- happy path
- contract-change reapproval
- implementation-only no-reapproval
- interruption/resume

## 12.4 Flutter/visual tests

Run relevant:
- Flutter tests
- Widgetbook coverage
- screenshot capture
- golden checks
- selected visual-QA fixture tests

## 12.5 Repository validation

Existing repository, workflow, prototype, design-binding, and resolved-theme validators remain required.

---

# 13. Implementation cycles

Milestone F should be executed in three SDD cycles.

## Cycle F.1 — Reference Client Foundation

Build:
- client fixture and deterministic data
- intake/product contract
- curated references/resource provenance
- three experience directions
- Flutter prototype coverage for required B2C/B2B screens
- machine scenario skeleton

Exit criteria:
- the reference client can be generated/rendered reproducibly
- all three directions are materially distinct but use the same runtime/design system
- fixture/schema validation passes

## Cycle F.2 — Review → Approval → QA

Build/prove:
- Compare / Select / Mix
- blocking + non-blocking feedback
- visual annotation
- refinement batch
- explicit round closure
- ApprovalSnapshot v1
- D automated visual QA
- representative QAFinding triage/promotion path

Exit criteria:
- complete normal review/approval/QA journey passes using canonical authorities

## Cycle F.3 — Change, Resume, and Regression Proof

Build/prove:
- contract-impacting post-approval change
- new review round
- ApprovalSnapshot v2
- implementation-only change without unnecessary reapproval
- controlled interruption/resume
- final machine E2E report
- final human reference report
- CI/regression integration

Exit criteria:
- B–E platform is proven as one reproducible regression fixture
- final whole-branch architectural review reports zero blockers/majors or any residuals are explicitly ruled and documented

---

# 14. Acceptance criteria

Milestone F is complete when all of the following are true:

1. One canonical synthetic B2C+B2B reference client exists in normal client-project structure.
2. Fixture data is deterministic and versioned.
3. Three meaningful experience directions exist.
4. The shared Flutter runtime renders required B2C/B2B flows.
5. Compare / Select / Mix is exercised.
6. Blocking and non-blocking feedback are exercised.
7. Visual annotation is exercised.
8. RefinementBatch is exercised.
9. ApprovalSnapshot v1 is produced under normal approval invariants.
10. Milestone D automated visual QA is exercised.
11. Milestone E workflow/checkpoint/evidence semantics are exercised.
12. A contract-impacting post-approval change creates a new review/approval cycle.
13. ApprovalSnapshot v2 is produced without mutating v1.
14. An implementation-only change reruns required checks without unnecessary reapproval.
15. Controlled interruption/resume is proven from repository state.
16. Machine-readable assertions validate canonical records rather than copied state.
17. Human-readable reference evidence is produced.
18. No new competing domain authority is introduced.
19. Existing B–E regressions remain green.
20. No production authorization or production deployment is introduced.

---

# 15. Core principle

> Milestone F does not add another major platform capability. It proves, with one deterministic reference client, that everything built in Milestones B through E forms one coherent, resumable, reviewable, visually validated, and regression-testable delivery system.
