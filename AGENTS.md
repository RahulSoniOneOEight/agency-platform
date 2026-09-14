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
1. initialize the workspace with `python -m tooling.workflow.initialize_client <client-id> --name "<display name>"`;
2. read `client-projects/<client>/workflow-state.yaml`;
3. determine the next legal stage with the runtime router;
4. read only the matching numbered file under `workflows/` plus the files named in its `READ` section;
5. execute the stage;
6. validate the required outputs;
7. update `workflow-state.yaml` only after the gate is satisfied.

For an existing client, never infer progress from chat history or prose. The GitHub artifacts and `workflow-state.yaml` are authoritative.

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
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

Flutter CI must additionally analyze/test initialized packages/apps and build `apps/prototype_app` for web.

## Visual completion rule

Meaningful UI work is not complete based on Dart analysis or unit tests alone. Follow `VISUAL_QA.md`: render A/B/C, inspect required viewports, record structured findings, correct issues, and add golden regression coverage where appropriate.

## Current scope guardrail

Milestone B includes the shared Flutter prototype system, deterministic fixtures, Widgetbook, prototype composition, screenshot/visual-QA contracts, and client approval workflow. Production backend/ERP integrations, Supabase, n8n, production auth/payments/shipping/CRM/WhatsApp, deployment pipelines, and app-store release automation remain later milestones unless explicitly authorized.
