# Milestone F — End-to-End Reference Client — SDD Ledger

> Superpowers subagent-driven-development progress ledger. Authoritative for resuming after
> compaction/interruption. Read this first, then re-derive reality from the repository.

## Run metadata

- Repository: `C:\Users\LENOVO\Documents\agency-platform`
- Branch: `milestone-f-reference-client` (do not work on `main`; do not merge)
- Base: `main` at `4a9a532` (Milestone E merge, PR #22); branch point `4a9a532`
- Spec: `docs/superpowers/specs/2026-09-18-milestone-f-reference-client-design.md` (`0d904c2`)
- Plan: `docs/superpowers/plans/2026-09-18-milestone-f-reference-client-implementation.md` (`a40ccf7`)
- Execution model: exactly 3 cycles (F.1 foundation; F.2 review→approval v1→QA; F.3 change/resume/reports).
- Mode: TDD, fresh implementer + fresh independent reviewer per cycle, final whole-branch review.
- Started: 2026-09-18

## Resume protocol

1. `git branch --show-current` — confirm `milestone-f-reference-client`.
2. `git log --oneline -20` — reconcile commits below with actual history.
3. Resume at the first cycle not marked `ACCEPTED`; re-run its focused tests first.

## Preflight verification

- `git fetch` → `origin/milestone-f-reference-client` exists with the F design (`0d904c2`) + plan
  (`a40ccf7`) on top of the merged E tip (`4a9a532`).
- `git merge-base HEAD origin/main` = `4a9a532` → branch contains merged Milestone E. ✔
- `git status` → only the three untracked `pubspec.lock` files; `git ls-files | grep pubspec.lock`
  is empty (no lockfile is tracked). ✔
- D and E authorities present on the branch (`tooling/visual_qa/`, `apps/prototype_app/lib/qa/`,
  `tooling/workflow/`, `apps/prototype_app/lib/review/`). ✔
- F design spec + implementation plan present. ✔

## Preflight consistency scan — binding constraints discovered

### C1. Runtime direction ids are fixed to `a`/`b`/`c` (merged B contract)

`tooling/prototype/validate_prototype.py` (`_ALLOWED_DIRECTION_IDS = {"a","b","c"}`, requires `a`
and `b`, `review.allowed_values == keys`), `tooling/prototype/build_prototype.py`
(`direction["id"] == direction_key`), `tooling/prototype/validate_runtime_bundle.py` (directions are
exactly 2–3 keys ⊆ {a,b,c}), and `tooling/prototype/approved_experience.py`
(`base_direction`/`source_direction` ∈ {a,b,c}) all fix the runtime direction vocabulary.

The plan's named ids (`efficient-commerce`, `premium-discovery`, `trade-first`) therefore **cannot**
be runtime direction ids. → **RF1**.

### C2. A non-`examples/` client is scanned by every validator

`validate_workflow.validate_runtime` skips only `{"schema","examples"}`; `validate_repo` and
`validate_prototype` glob `client-projects/**`. So `client-projects/reference-commerce/` must
satisfy, at minimum:

- `workflow-state.yaml` — valid v2 state (`normalize_state` + schema), lease/audit/pointer rules.
- `prototype/prototype-manifest.yaml` — `version: 1`, safe `client_id`, `theme.preset` ∈ approved
  presets, `default_direction`, 2–3 `directions` mapping to runtime JSONs, `fixture_pack`,
  `review.allowed_values` in key order.
- `prototype/runtime/direction-{a,b,c}.json` — must resolve through **approved Flutter bindings**
  (`validate_repo.flutter_binding_errors`), i.e. patterns ⊆ 8 bound patterns, components ⊆ 5 bound
  components, `component_variants` only `commerce.product-card × {standard,b2b}`, density supported
  per component (`spacious` only with components ⊆ {product-card}).
- `prototype/fixtures/demo.yaml` — fixture contract (`industry`, `seed`, `products[]`, `services[]`).
- `prototype/qa/screenshot-manifest.yaml` — v2 manifest whose direction set equals the manifest keys.
- `apps/prototype_app/assets/generated/reference-commerce.json` — **committed generated bundle**,
  byte-fresh per `check_resolved_bundles_fresh`, produced by
  `python -m tooling.design_contract.generate_resolved_themes --write`.

→ **RF2**, **RF10**.

### C3. Only five governed sections exist for section-level mixing

`tooling/prototype`… `apps/prototype_app/lib/review/review_section_registry.dart` registers exactly:
`home.product-grid`, `plp.product-grid`, `search.search-field`, `search.results-grid`, `pdp.price`.
→ **RF3**.

### C4. The Dart review/QA domain has no injectable clock

`ReviewCoordinator.createFeedback` and friends stamp `DateTime.now().toUtc()` internally, so
committed Dart review records cannot be byte-reproduced. Determinism must be asserted
**behaviourally** (statuses, counts, lifecycle, provenance), not byte-wise. → **RF5**.

## Rulings

- **RF1 — Runtime direction ids stay `a`/`b`/`c`; the named experience identities are metadata.**
  `direction-a.yaml` carries `name: Efficient Commerce` + `archetype: efficient-commerce`;
  `direction-b.yaml` → `Premium Discovery` / `premium-discovery`; `direction-c.yaml` →
  `Trade First` / `trade-first`. The canonical mapping `a→efficient-commerce`,
  `b→premium-discovery`, `c→trade-first` is declared once in
  `client-projects/reference-commerce/reference-e2e/scenario.yaml` (`direction_identities`) and used
  by every assertion/report. F does **not** modify the merged B direction vocabulary.
- **RF2 — The reference client is a fully valid repository client.** All artifacts listed in C2 are
  created and the client passes `validate_prototype`, `validate_workflow`, `validate_repo`, and
  `validate_visual_qa` unchanged.
- **RF3 — Section-level mixing targets a governed section.** The canonical section override uses
  `pdp.price` (screen `commerce.pdp`), and the screen override uses `commerce.search`. Source
  directions are chosen so `ReviewSectionCompatibility` allows them.
- **RF4 — The reference client is a deterministic foundation; the E2E journey runs in a temp copy.**
  Committed under `client-projects/reference-commerce/`: `input/`, `derived/`, `directions/`,
  `resources/`, `prototype/{prototype-manifest.yaml,runtime,fixtures,qa}`, `workflow-state.yaml`,
  and `reference-e2e/{fixture,scenario,assertions}.yaml` + `reference-e2e/report/*`. The C/D/E
  journey (review→approval→QA→change→resume) is executed by a Dart E2E test against a **temp copy**
  so CI never mutates live workflow authority or committed review state.
- **RF5 — Determinism is behavioural.** Because the Dart domain has no injectable clock (C4),
  determinism is proven by: (a) the fixture/scenario/bundle being byte-reproducible, and (b) the E2E
  run asserting the same statuses, counts, round numbers, approval versions, and provenance on every
  run. The machine report records assertion outcomes and artifact hashes, never a subjective score.
- **RF6 — `reference-e2e/` is evidence only.** It holds the scenario definition, assertions,
  evidence references, and reports. It never becomes a workflow/review/feedback/refinement/approval/
  QA authority and never duplicates canonical domain state.
- **RF7 — No Milestone G/H work.** No `ProductionAuthorization`, no release/deployment engine, no
  production backend.
- **RF8 — Model routing deviation.** Only `explore` and `general` subagent types are available. Each
  cycle uses a fresh `general` implementer and a fresh independent `general` reviewer; the final
  whole-branch review uses the strongest available reasoning configuration.
- **RF9 — CI never mutates authority.** CI validates the fixture/scenario/report schemas, runs the
  Python reference-client validator and the Dart E2E test (in temp workspaces), and never creates
  approvals, advances workflow state, or updates goldens.
- **RF10 — The generated bundle is committed and fresh.** `apps/prototype_app/assets/generated/
  reference-commerce.json` is produced by `python -m tooling.design_contract.generate_resolved_themes
  --write` and committed; `--check` must stay fresh.
- **RF11 — Reference fixture is synthetic.** No PII; all names/ids/prices/accounts are invented and
  documented as synthetic.
- **RF12 — Visual QA stays provider-neutral and offline.** CI uses `FixtureVisualQaProvider`; no live
  Visual AI credentials.
- **RF13 — Checkout is a platform gap, not an F deliverable.** The spec's required experience list
  names `Checkout`, but the merged B platform has **no governed checkout pattern** (no
  `design-contract/patterns/commerce-checkout.yaml`, no Flutter binding, no `PrototypeRegistry`
  branch). Adding one would create a new design-contract/pattern authority, which F explicitly must
  not do. F therefore represents order conversion as the journey's terminal `order` step plus the
  existing governed surfaces that express it: `commerce.cart` renders the B2C `Checkout` call to
  action and the B2B `Continue order` call to action, and the fixture carries `carts`, `orders`, and
  representative `validation_states`. The omission is asserted (journey + CTA + fixture coverage) and
  recorded as a known limitation in the human report. A governed checkout pattern is deferred to a
  later milestone.
- **RF14 — Two fixtures with distinct roles.** `prototype/fixtures/demo.yaml` is the runtime fixture
  pack (must satisfy the runtime fixture contract; generated by the platform composer from
  `industry: electronics-appliances`, seed 108). `reference-e2e/fixture.yaml` is the richer
  scenario/E2E fixture (categories, variants, quantity breaks, accounts, credit, RFQs, quotations,
  carts, orders, validation states). Spec §2's "reusable … where practical" is satisfied by both
  being deterministic and versioned; unifying them would require widening the runtime fixture contract
  and is deliberately out of scope.
- **RF15 — `normalized_into` is superseded by the canonical provenance contract.**
  `resources/provenance.yaml` follows `resources/registry/schema/resource-provenance.schema.json`
  (`source` + `usage_status`), which has no `normalized_into` field; normalization is proven by
  `normalize_bindings` inlining the selected resources into the prototype manifest.
- **RF17 — The review/approval/QA journey is proven in Dart, not in a Python module.** The plan
  names `tooling/validation/test_reference_client_review_approval.py`, but the C.3–C.7 and D
  authorities are Dart domain code that Python cannot drive, and CI's `validate.yml` environment
  installs only Python (no Flutter). The journey is therefore proven by
  `apps/prototype_app/test/reference_client/reference_client_{review_approval,qa}_test.dart` (run
  by `flutter-ci.yml`), and the Python side validates the **committed machine evidence**
  (`tooling/reference_client/evidence.py` + `test_reference_client_evidence.py`), which is
  Flutter-free and therefore safe for `validate.yml`. The Dart test emits evidence only when
  `--dart-define=REFERENCE_EVIDENCE_PATH=...` is supplied, so CI never mutates committed authority.
  Regeneration command: from `apps/prototype_app`,
  `flutter test test/reference_client/reference_client_review_approval_test.dart --dart-define=REFERENCE_EVIDENCE_PATH=<repo-root-relative path>`.
  The synthetic `source_commit_sha` (`0123...4567`) is a determinism fixture value, not a real commit.
- **RF16 — Assertion integrity.** `evaluate_assertions` fails loudly on an empty assertion set, and
  `fixture_integrity` pins the fixture's canonical content hash plus re-runs `validate_fixture`, so
  content tampering cannot pass silently. `no_duplicate_authority` matches `.json`/`.yaml`/`.yml`
  authority filenames.

## Cycle table

| Cycle | Scope | Status | Commits |
|-------|-------|--------|---------|
| F.1 | Reference client foundation (Tasks 1–4) | ACCEPTED | `1c1a23b` `514e120` `…` |
| F.2 | Review → Approval v1 → Visual QA (Tasks 5–7) | PENDING-REVIEW | `2a84fed` |
| F.3 | Change boundaries + resume + reports/CI (Tasks 8–10) | PENDING | — |

## Progress log

- 2026-09-18 — **Cycle F.2 implemented** (`2a84fed`). The real C/D authorities are exercised on
  the reference client in a temp workspace (RF4/RF9): Compare/Select/Mix (overall `b`, screen
  `commerce.search` → `a`, governed section `commerce.pdp`/`pdp.price` → `a`), one blocking +
  one non-blocking + one visual-annotation FeedbackRecord, a RefinementBatch that moves the
  blocking item `open` → `addressed` (never auto-resolved), explicit reviewer resolve + round
  close, ApprovalSnapshot v1 (version 1, `supersedes` null, `sha256:` review-state hash, carries
  the non-blocking feedback, byte-identical on disk), and the D visual-QA path
  (FixtureVisualQaProvider → QAFinding detected/triaged → one explicit idempotent promotion to
  FeedbackRecord(originQaFindingId), blocking false, no auto-resolve, plus a dismiss path that
  creates no feedback).
  - Delivered: `apps/prototype_app/test/reference_client/reference_client_review_approval_test.dart`,
    `reference_client_qa_test.dart`; `tooling/reference_client/evidence.py`;
    `client-projects/schema/reference-client-report.schema.json`;
    `tooling/validation/test_reference_client_evidence.py`; committed machine evidence
    `client-projects/reference-commerce/reference-e2e/evidence/review-approval-evidence.json`
    (canonical JSON, 38 passing assertions, no subjective score).
  - Tests: reference-client modules 38 (16 fixture + 12 scenario + 10 evidence) → repo suite
    **733 tests OK**; `flutter test test/reference_client` 11, `flutter test test/review` 586,
    `flutter test test/qa` 129, `flutter test` 789, `flutter analyze` clean; all validators and
    both `--check` freshness commands pass.
  - Evidence emission is opt-in: the Dart test writes into the repository only when
    `REFERENCE_EVIDENCE_PATH` is set, so CI never mutates committed authority.
  - **Accepted minors (recorded, non-gating):** the evidence carries a *derived summary* of mix
    decisions and feedback outcomes (ids, statuses, counts, history event types) rather than only
    ids/counts/refs — it never copies a full authority body, and `validate_evidence` forbids the
    full-state keys; `validate_evidence` does not yet cross-check assertion ids against
    `assertions.yaml`; the synthetic source SHA is not labelled synthetic in the schema; the
    "approval refused while a blocker is unresolved" assertion is confounded by the readiness gate
    (the blocking gate itself is covered by the C.4–C.7 suite); the runtime snapshot helper is
    shallow but the bundle-byte comparison is the strong immutability proof.
- 2026-09-18 — Preflight complete. Branch `milestone-f-reference-client` at `a40ccf7`, based on the
  merged E tip `4a9a532`. Spec + plan read in full. Preflight scan found two decisive constraints
  (C1 runtime direction ids, C2 non-`examples` validator coverage) plus C3 (five governed sections)
  and C4 (no injectable Dart clock). RF1–RF12 recorded. Untracked `pubspec.lock` files intentionally
  uncommitted.
- 2026-09-18 — **Cycle F.1 implemented.** Commits: `1c1a23b` deterministic fixture + reference client
  foundation + composer generator + committed bundle; `514e120` Flutter render coverage + scenario and
  assertion engine.
  - Delivered: `tooling/reference_client/{__init__,fixture,build,scenario,assertions}.py`;
    `client-projects/schema/{reference-client-fixture,reference-client-scenario}.schema.json`;
    `client-projects/reference-commerce/` (input, derived profile, 4 resource artifacts with
    provenance, `directions/direction-{a,b,c}.yaml` + `comparison.yaml`, `resolved-intelligence.yaml`,
    composed `prototype/{prototype-manifest.yaml,runtime/direction-{a,b,c}.json,fixtures/demo.yaml,
    qa/{screenshot-manifest.yaml,visual-findings.yaml}}`, `workflow-state.yaml`,
    `reference-e2e/{fixture,scenario,assertions}.yaml`); committed generated bundle
    `apps/prototype_app/assets/generated/reference-commerce.json`; `apps/prototype_app/test/reference_client/`.
  - Directions (RF1): `a` Efficient Commerce (compact, search-led), `b` Premium Discovery
    (spacious, editorial), `c` Trade First (normal, RFQ/credit/reorder) — distinct pattern sets,
    components, variants, and densities on one runtime.
  - Tests: `test_reference_client_fixture` 16, `test_reference_client_scenario` 12 → repo suite
    **723 tests OK**; `flutter test test/reference_client` 8, `flutter test` 784, `flutter analyze`
    clean; `validate_prototype`, `validate_workflow`, `validate_repo` (141 paths),
    `validate_visual_qa client-projects/reference-commerce`, and both `--check` freshness commands pass.
  - Bundle determinism: re-running `py -3.12 -m tooling.reference_client.build` produced byte-identical
    artifacts (identical SHA-256 for all seven derived files).
  - Independent review: **REJECT** — 0 blockers, **1 major** (required `Checkout` experience absent)
    and 12 minors.
  - Fixes: **RF13** recorded (checkout is a platform gap; order conversion is asserted via the journey
    `order` step + the governed cart `Checkout`/`Continue order` calls to action + fixture
    `carts`/`orders`/`validation_states`, and documented as a known limitation); direction `a` journey
    extended to `search→plp→pdp→cart→order` and its variant changed to `standard` to separate it from
    the trade direction; direction `c` journeys extended to the `order` step; `validate_fixture` now
    checks line-item and validation-state references; `evaluate_assertions` fails on an empty assertion
    set; new `fixture_integrity` (pinned content hash + `validate_fixture`) and `journey_contains`
    kinds added; `no_duplicate_authority` now matches `.json`/`.yaml`/`.yml` authority filenames;
    `assertions.yaml` converted to a versioned mapping; render tests now assert the B2C/B2B order
    conversion calls to action.
  - **Accepted minors (recorded, non-gating):** `resources/candidates.yaml` has no rejected candidate
    to demonstrate a rejection (RF15 records that provenance follows the canonical schema);
    `validate_repo`/CI wiring of the reference-client validator is F.3 Task 10 scope; the runtime
    fixture pack and the E2E fixture intentionally differ (RF14); `artifact_exists` assertions are
    existence-only; **direction `b` render coverage is limited to `commerce.pdp`** because
    `commerce.home`/`commerce.plp` hit the pre-existing shared `ProductCard`/`mainAxisExtent` overflow
    — direction `b` is still proven distinct by its bundle metadata, theme, and immutability
    assertions.
  - Post-fix counts: `test_reference_client_fixture` 16, `test_reference_client_scenario` 12,
    `flutter test test/reference_client` 8, `flutter test` 786.
  - **Scoped re-review: ACCEPT-WITH-MINORS — major M1 closed, 0 blockers / 0 majors met; F.2 may
    proceed.** Residual partials closed in the same pass: `validation_states.target` now validates bare
    entity ids as well as `kind:ref` targets, and `validate_assertions` now requires `version` and
    `client_id` to be present.
