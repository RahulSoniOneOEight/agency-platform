# Agency Platform — Agent Operating Contract

These instructions are mandatory for all agent work in this repository.

## Governing architecture

Primary architecture source:

`docs/source/agency_flutter_opencode_delivery_system_v2.txt`

Read it before architectural or structural changes. This operating contract must not contradict the governing architecture source.

## Source of truth

- GitHub is the production source of truth.
- Flutter is authoritative for executable prototype and production UI implementation.
- OpenCode is the primary engineering/orchestration layer.
- Penpot is optional for visual reference, selected prototypes, representative screens, and client review.
- Do not depend on perfect Penpot ↔ Flutter round-tripping.

## Mandatory policy routing

Before reference discovery, evaluation, adoption, or normalization, read `REFERENCE_POLICY.md`.
Before shared UI, tokens, components, patterns, variants, or themes, read `DESIGN_SYSTEM.md`.
Before prototype composition or shared Flutter implementation, read `docs/prototype-platform.md`.
Before completing meaningful UI work, read `VISUAL_QA.md`.
Before Penpot-related work, read `PENPOT_MAPPING.md`.
Before product-consulting or Experience Direction work, read `docs/knowledge-platform.md` and the relevant client profile, presets, design contracts, and experience patterns.
Before starting or continuing a client project, read `docs/workflow-runtime.md` and the client's `workflow-state.yaml` when present.

Only load policies relevant to the current task, but never skip a relevant policy.

## Workflow Runtime operating model

Client work must follow the repository-driven runtime rather than ad-hoc prompt sequences.

For a new client:
1. initialize the workspace with `python -m tooling.workflow.initialize_client <client-id> --name "<display name>"`.

For any client, a fresh session must:
1. read `client-projects/<client>/workflow-state.yaml`; never infer progress from chat history or prose — the GitHub artifacts and the state file are authoritative;
2. run the runner's inspect/recovery (`tooling.workflow.runner.inspect_client`) to get the deterministic recovery decision and the next legal stage, and run `resume_stage`/`reconcile_state` when recovery requires it;
3. read only the current stage's numbered file under `workflows/` plus the files named in its `READ` section and the matching `workflows/contracts/` contract;
4. acquire/start/resume the attempt through the runner (`start_stage`/`resume_stage`) — never mutate state directly;
5. execute the stage;
6. checkpoint each durable atomic step through the runner (`checkpoint_stage`);
7. run the validators declared by the stage contract;
8. complete through the runner (`complete_stage`) only after every gate passes, or record failure with `fail_stage`;
9. persist ruling/deviation/override records to `workflow/audit.jsonl` (overrides require a human actor);
10. never edit `current_stage` by hand — only `tooling.workflow.runner` (and the one-time initializer) writes `workflow-state.yaml`.

Every workflow file must contain `PURPOSE`, `READ`, `PROCESS`, `WRITE`, `VALIDATE`, `DO NOT`, and `NEXT`.

Do not skip mandatory stages. `resource-research` may be skipped only when the state records a reason. Prototype, visual-QA, client-review, and productionization gates are artifact-aware and must not be bypassed.

## Knowledge Platform operating model

The shared knowledge layer has four responsibilities:

1. **Design Intelligence** — `design-contract/` + `presets/` + metadata.
2. **Resource Intelligence** — `resources/registry/` + source routing + normalization/provenance.
3. **Product Consulting** — `experience-patterns/` + client profile + Experience Direction Engine.
4. **Client Contract** — client selection/mixing produces `approved-experience.yaml` after prototype and visual QA.

Presets and experience patterns are hypotheses and reusable knowledge, not forced client outputs.
`discovery-first`, `search-first`, and `trade-first` are candidate archetypes only. OpenCode must evaluate the actual client objectives, personas, jobs, business model, industry, use cases, constraints, design intelligence, resource availability, and references before selecting directions.

For Experience Directions:
1. resolve business-model + industry + use-case presets;
2. inspect relevant design-contract components/patterns/journeys;
3. inspect approved resource/reference context where needed;
4. generate multiple candidate strategies;
5. score candidate fit;
6. enforce strategic diversity;
7. select the best 2–3 directions;
8. explain rationale and trade-offs.

Directions must differ materially in information architecture, primary journey, navigation, discovery model, merchandising, interaction model, transaction model, density, personalization, or procurement/service logic. Theme-only differences do not count.

## Prototype Platform operating model

Milestone B uses one shared Flutter system and one configurable prototype app.

Required flow:

```text
validated A/B/C directions
→ tooling.prototype composer
→ client prototype manifest + deterministic fixtures
→ apps/prototype_app
→ shared agency_flutter_ui patterns/components
→ screenshots + structured visual QA
→ client selection/mixing
→ approved-experience.yaml
```

Rules:
- Never create separate A/B/C source trees.
- Never copy shared Flutter source into a client directory.
- `packages/agency_flutter_ui/` is the reusable implementation layer corresponding to `design-contract/`.
- `apps/prototype_app/` is the shared client-review runtime.
- `apps/widgetbook/` is the component/pattern review surface.
- Client prototype directories store configuration, fixtures, screenshots, and QA artifacts only.
- Production backend/ERP/auth/payment/shipping/CRM/WhatsApp/Supabase/n8n integrations do not belong in prototype composition.

## Mandatory lookup order

Before creating any new reusable UI component, pattern, screen-level building block, or package-level implementation, check in this order:

1. Current client application/configuration.
2. `packages/agency_flutter_ui/`.
3. `design-contract/` components, patterns, journeys, and variants.
4. Active business-model / industry / use-case presets.
5. Approved Penpot components or patterns.
6. Approved GitHub references in `resources/registry/`.
7. Approved `pub.dev` packages / providers.
8. Only then create something new.

## Mandatory pre-implementation lookup report

Before creating a new reusable component or pattern, report:

```text
Client app/config:
Agency Flutter UI:
Design contract:
Active presets:
Approved Penpot:
Approved GitHub:
Approved pub.dev:

Decision:
- reuse
- extend
- add variant
- normalize external reference
- create new
```

Do not implement a new reusable component or pattern until this lookup is complete and the decision is stated.

## Reference and normalization rules

- Never copy external UI code or components directly into `client-projects/`.
- New external material enters through `resources/incoming/`.
- Evaluate licensing, Flutter compatibility, dependency quality, maintainability, visual usefulness, accessibility implications, and duplication before approval.
- Adopted references must pass through normalization before entering the agency design system.
- Approval does not mean production-ready.
- Remove unnecessary source-specific styling and dependencies.
- Map color, spacing, typography, radius, elevation, icon, imagery, and motion decisions to agency design-contract concepts.
- Prefer reusable, generalized component APIs over source-specific APIs.
- Record provider/source provenance for selected external resources.

Required flow:

```text
external source
→ resources/incoming/
→ review / registry status
→ normalization
→ design contract / agency_flutter_ui
→ client usage
```

## Design-system rules

- Use shared tokens instead of hard-coded design values when tokens exist.
- Prefer reuse over creation.
- Prefer extending an existing component over adding a duplicate.
- Prefer variants over duplicated widgets.
- Presets select/configure contracts; presets must not duplicate widgets.
- Keep client-specific changes focused on brand/theme, selected UX variants, and genuinely unique workflows.
- Keep component, pattern, journey, and variant naming aligned with `design-contract/`.

## Validation

For platform changes run:

```text
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_client_input_contract tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

Production-foundation changes additionally run:

```text
python -m unittest tooling.validation.test_production_config tooling.validation.test_production_migrations tooling.validation.test_h1_reference_report tooling.validation.test_h1_authority_boundaries -v
python -m tooling.production.validate_config client-projects/reference-commerce
python -m tooling.production.validate_migrations
python -m tooling.production.report client-projects/reference-commerce
```

H.2 hardening/release changes additionally run:

```text
python -m unittest tooling.validation.test_h2_workflow_integration tooling.validation.test_h2_authority_boundaries -v
python -m tooling.hardening.validate client-projects/reference-commerce
python -m tooling.release.release_record client-projects/reference-commerce
```

Flutter CI must additionally analyze/test initialized packages/apps and build `apps/prototype_app` and `apps/production_app` for web.

## Visual completion rule

Meaningful UI work is not complete based on Dart analysis or unit tests alone. Follow `VISUAL_QA.md`: render A/B/C, inspect required viewports, record structured findings, correct issues, and add golden regression coverage where appropriate.

## Current scope guardrail

Milestone B includes the shared Flutter prototype system, deterministic fixtures, Widgetbook, prototype composition, screenshot/visual-QA contracts, and client approval workflow. Milestone H.1 adds the production foundation only: provider-neutral production ports, a reference Supabase/Postgres + Supabase Auth adapter, deterministic fake ERP/payment/shipping/CRM/WhatsApp adapters, validated dev/staging/production configuration, and versioned migrations.

H.2 is the current milestone. It is one model with two halves: **H.2A operational hardening** (provider-neutral observability/analytics/deployment, performance, accessibility, security, migration readiness, recovery, and the no-rebuild rule) and **H.2B authorized release** (staging-first exact-candidate promotion, production smoke, telemetry health, and an immutable `ReleaseRecord`). Real client-specific vendor integrations, n8n, Android/iOS store release automation, and multi-client production operations remain later extensions unless explicitly authorized.

## Production foundation (H.1) operating model

- The stage-08 gate is named `production-foundation`; its completion language is **production-capable**, never **production-authorized** or **deployed**.
- H.1 performs no production deployment and cannot create or rewrite a `ProductionAuthorization`; existing C/D/E/F/G authorities remain unchanged.
- The deterministic evidence report is `client-projects/reference-commerce/production/evidence/h1-foundation-report.json`; its identity is SHA-256 over canonical report content excluding `report_identity`, and it references F/G authorities by identity/ref only.
- Normal CI requires no production credentials and no live Supabase project; Supabase imports stay in `packages/agency_supabase_adapter/` and the app composition boundary.

## Production hardening and release (H.2) operating model

- Stage 08 `productionize` remains H.1 production foundation: completion is **production-capable**, it never deploys or authorizes, and its `next` is `release`.
- Stage 09 `release` is H.2B: it consumes the immutable H.1 foundation evidence, the H.2A hardening/staging evidence, and the exact Milestone-G `ProductionAuthorization`, then produces the immutable `client-projects/reference-commerce/production/evidence/release-record.json`.
- H.2A creates hardening/staging evidence only. H.2B executes the authorized, no-rebuild promotion of the exact staging-tested artifact. Neither half creates, grants, or mutates a `ProductionAuthorization`.
- Authorization remains human/Milestone-G authority. The H.2 reference proof uses a synthetic human authorization fixture bound to the exact candidate; it is a permission artifact under `release/reference-proof/`, never a production implementation artifact.
- Workflow-state authority remains with `tooling.workflow.runner`; stage 09 completes only after the `h2-hardening`, `production-authorization`, and `h2-release-record` validators pass, with checkpoints `staging-validated`, `candidate-authorized`, and `production-released`.
- Normal CI requires no production credentials; privileged provider credentials remain CI/server secrets.

## OpenCode model routing

OpenCode should use the repository-local model roles under `.opencode/agents/` rather than keeping expensive reasoning models active for routine execution.

Default execution model:
- `deepseek/deepseek-v4-pro` for the primary Build session and ordinary implementation work.
- `deepseek/deepseek-v4-flash` is the lightweight model configured for cheap internal/simple work.

Specialist routing:
- Use `@strategy` for client interpretation, product/UX strategy, Experience Directions, ambiguous requirements, information architecture, architecture, and high-impact trade-offs. It uses `openai/gpt-5.6-sol#high` and must remain read-only.
- Use `@builder` for Flutter implementation, repository edits, tests, fixtures, configuration, routine refactors, and operational execution after the decision is clear. It uses `deepseek/deepseek-v4-pro`.
- Use `@worker` for deterministic, repetitive, low-risk edits and mechanical transformations. It uses `deepseek/deepseek-v4-flash`.
- Use `@reviewer` for difficult debugging analysis, architecture verification, shared-system review, regression risk, and important pre-merge review. It uses `openai/gpt-5.6-sol#high` and does not edit files.

Routing rules:
1. Do not use OpenAI merely because it is available; reserve it for judgment-heavy work.
2. If a task is routine and the design/decision is already clear, use `builder` or `worker`.
3. If implementation encounters a genuinely ambiguous product, UX, client-truth, architecture, or high-impact decision, stop that decision path and delegate it to `strategy`; then return to `builder` for implementation.
4. For important platform or shared-system work, prefer `strategy → builder → reviewer`.
5. For routine low-risk work, `builder` may complete without an OpenAI review when repository validation is sufficient.
6. Model/provider credentials remain local to OpenCode. Never commit API keys, ChatGPT sessions, provider tokens, or other secrets to this repository.
7. Agent routing never overrides workflow gates, repository policies, validation requirements, or human approval requirements.
