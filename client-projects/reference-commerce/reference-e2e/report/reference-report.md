# Reference Commerce — Milestone F end-to-end reference report

This document is explanatory evidence. It does not replace the machine assertions in `reference-report.json`; those assertions are authoritative. It contains no subjective aggregate rating.

## Synthetic client profile

- Client id: `reference-commerce`
- Display name: Reference Commerce
- Business model: `b2c-b2b`
- Industry: `electronics-appliances`
- Use cases: direct-purchase, request-quote, repeat-order
- Objectives: increase-conversion, reduce-order-time, grow-trade-accounts
- Personas: consumer-shopper, trade-buyer, procurement-manager
- Jobs: discover-products, compare-prices, reorder, request-quote
- Platforms: web, mobile
- Fixture version: 1
- Fixture identity: `sha256:d52dfd83073cc4b2469932fc5750baea0a62bf0f3755bf547a467bf8f45d6835`
- Provenance: fully synthetic reference data; no client data and no PII.

## B2C scope

Consumer shoppers discover, compare, and buy direct. The reference journey exercises a search-led path (`search -> plp -> pdp -> cart -> order`) and the governed cart calls to action that represent order conversion.

## B2B scope

Trade buyers and procurement managers order on account. The reference journey exercises a dashboard-led path (`trade-dashboard -> reorder / rfq -> cart -> order`) with credit visibility and quoting.

## Three directions

### a — Efficient Commerce (`efficient-commerce`)

- Thesis: Known-item shoppers and repeat trade buyers should reach a confident purchase in the fewest steps.
- Primary journey: `search-to-order` (search -> plp -> pdp -> cart -> order)
- Density: `compact`
- Patterns: commerce.search, commerce.plp, commerce.pdp, commerce.cart
- Components: commerce.product-card, commerce.price-display, commerce.search-field

### b — Premium Discovery (`premium-discovery`)

- Thesis: Considered consumer purchases benefit from an editorial, spacious browsing experience that builds desire before price comparison.
- Primary journey: `browse-to-pdp` (home -> plp -> pdp)
- Density: `spacious`
- Patterns: commerce.home, commerce.plp, commerce.pdp
- Components: commerce.product-card

### c — Trade First (`trade-first`)

- Thesis: Existing trade accounts should manage credit, quotes, and repeat orders from a single procurement workspace.
- Primary journey: `reorder-to-order` (trade-dashboard -> reorder -> cart -> order)
- Density: `normal`
- Patterns: commerce.trade-dashboard, commerce.rfq, commerce.cart, commerce.reorder
- Components: commerce.credit-summary, commerce.quote-card, commerce.product-card

## Selected and mixed experience

- Selected direction: `b` (premium-discovery)
- Screen override: `commerce.search` -> `a`
- Section override: `commerce.pdp` / `pdp.price` -> `a`

## Blocking and non-blocking feedback

Blocking feedback:
- `feedback-blocking` (section) status=`resolved`, blocking=True

Non-blocking feedback:
- `feedback-non-blocking` (general) status=`open`, blocking=False

## Visual annotation

- `feedback-visual` on `commerce.pdp` / `pdp.price` (direction `b`), screenshot `sha256:4187fa0a2878b8298f57f293c933c880520b2014ff1279c00d029c566e16ce44`

## Refinement batch

- `batch-001` status=`completed` classification=`implementation_only` feedback=feedback-blocking

## Approval v1

- Version: 1
- Review round: 1
- Source commit: `0123456789abcdef0123456789abcdef01234567`
- Review-state reference identity: `sha256:366034b1d1f9f1b6fee921d41ac93700cd1268437200e7e1504f88399adcb981`

## QA / QAFinding journey

- Findings: 1
- Promotions: 1
- `qa-001` status=`promoted` promoted_feedback=`feedback-qa-001` blocking=False

## Contract-impacting change

- Review rounds: 2
- Approval versions: [1, 2]
- v1 immutable: True
- v2 hash differs: True
- Third approval refused: True

## Approval v2

- Version: 2
- Review round: 2
- Source commit: `89abcdef0123456789abcdef0123456789abcdef`
- Review-state reference identity: `sha256:2b4cc537379f8142b1c629cf6c3bd9b87e78d005363658e526b876e950292153`
- Supersedes: 1 (v1 remains immutable and historically valid)

## Implementation-only change (no reapproval proof)

- Classification: `implementation_only`
- Review round: 1
- Approval versions: [1] (no new version was created)
- Approved hash unchanged: True
- Still eligible for approval: True
- Uncertain changes default to: `contract_impacting`

## Interruption and resume proof

- Stage: `visual-qa`
- Attempt ids: [{'attempt': 1, 'run_id': 'wf-reference-commerce-20260918T120000Z-b997a029', 'stage': 'visual-qa'}, {'attempt': 2, 'run_id': 'wf-reference-commerce-20260918T123100Z-e5112921', 'stage': 'visual-qa'}]
- Interruption: {'lease_expired': True, 'recovery_action': 'resume'}
- Resume: same attempt, lease reclaimed and audited
- Completion advanced to: `client-review`
- Retry recovery action: `retry`
- No chat/session memory required: True
- Live workflow stage: `visual-qa`
- Completed stages: client-intake, resolve-intelligence, generate-directions, build-prototype

## Known limitations

- Checkout is a platform gap (RF13): the merged platform has no governed checkout pattern, so the reference journey represents order conversion as the terminal `order` journey step plus the governed cart calls to action; a governed checkout pattern is deferred to a later milestone.
- Two fixtures have distinct roles (RF14): `prototype/fixtures/demo.yaml` is the runtime fixture pack and `reference-e2e/fixture.yaml` is the richer scenario/E2E fixture; unifying them is deliberately out of scope.
- Determinism of the Dart review/approval/QA journey is asserted behaviourally (RF5) because the Dart domain has no injectable clock; the committed machine evidence is the authoritative record of those outcomes.
- This report is explanatory evidence; it never replaces the machine assertions and never grants an approval or a production authorization.

## Evidence references

- `client-projects/reference-commerce/reference-e2e/evidence/change-scenarios-evidence.json`
- `client-projects/reference-commerce/reference-e2e/evidence/resume-evidence.json`
- `client-projects/reference-commerce/reference-e2e/evidence/review-approval-evidence.json`

Assertions: 126/126 passed (0 failed).
