# Canonical Agency Operating Flow

This document is the detailed operating model for client delivery. The executable Workflow Runtime remains eight stored workflow files; each workflow owns one or more detailed stages below.

## Detailed 20-stage flow

| # | Flow stage | Primary inputs | Canonical files read | Canonical files written / impacted | Main outcome / gate |
|---:|---|---|---|---|---|
| 1 | Client intake | Client requirements, business context, users, goals, brand, references, assets, constraints | `AGENTS.md`, `workflows/01-client-intake.md`, `templates/client-input.yaml` | `input/client-input.yaml`, `input/brand/`, `input/references/`, `input/assets/`, `input/source-documents/`, `workflow-state.yaml` | Client-supplied facts are captured canonically and are complete enough to proceed. |
| 2 | Client profile derivation | Canonical input + attachments | `templates/client-profile.yaml`, `presets/`, `design-contract/indexes/` | `derived/client-profile.yaml` | Free-form input is normalized into agency taxonomy without contaminating client facts with inference. |
| 3 | Resolve reusable intelligence | Derived client profile | `design-contract/`, business-model/industry/use-case presets, `DESIGN_SYSTEM.md` | `derived/resolved-presets.yaml`, `derived/intelligence-map.yaml` | Reusable solution space is defined. |
| 4 | Identify capability / UX gaps | Client profile + resolved intelligence | Design Contract components/patterns/journeys/variants/indexes | `derived/capability-map.yaml`, `derived/gaps.yaml` | Reuse/extend/variant/new/client-only decisions are explicit. |
| 5 | Detect resource needs | Resolved intelligence + client assets + gaps | `input/`, resource policies/registry | `derived/resource-requirements.yaml` | Structured resource requests exist before any external search. |
| 6 | Resource search & evaluation | Resource requirements | Resource registry/approved/policies plus approved providers | `resources/selection.yaml`, shared incoming/approved/rejected/registry metadata when relevant | Approved resources have traceable provenance. |
| 7 | Generate experience directions | Profile + presets + Design Contract + resources | `experience-patterns/`, Design Contract, `workflows/04-generate-directions.md` | `directions/direction-a.yaml`, `direction-b.yaml`, `direction-c.yaml`, `comparison.yaml` | 2–3 materially different strategies are ready. |
| 8 | Validate directions | Direction configs | Direction template, Design Contract indexes, implementation registries | Corrected direction files + state | Directions are coherent, compatible, and strategically distinct. |
| 9 | Prepare prototype manifest | Validated directions + profile + resources | Prototype template, direction configs, resource selection | `prototype/prototype-manifest.yaml` | Executable prototype specification exists. |
| 10 | Generate demo data | Industry, model, journeys, screens | Canonical input where useful + fixture rules | `prototype/fixtures/` | Deterministic non-sensitive demo data exists. |
| 11 | Build runnable prototype | Manifest + fixtures + resources | `packages/agency_flutter_ui/`, `apps/prototype_app/`, Design Contract | Shared runtime/config/build artifacts | Runnable A/B/C prototype exists without per-direction app forks. |
| 12 | Render prototype | Runnable app | Prototype runtime + manifest + fixtures | Runtime output + screenshot manifest | Stable rendered routes/screens are available for QA. |
| 13 | Structural QA | Running prototype/code | `VISUAL_QA.md`, tests, routes, UI package | Technical findings/code/config fixes where needed | Prototype is technically stable. |
| 14 | Visual AI QA | Screenshots | Visual QA policy + Design Contract + direction intent | `prototype/screenshots/`, `prototype/qa/visual-findings.yaml` | Structured visual findings exist. |
| 15 | Correction loop | QA findings | Design Contract, shared package, resources, direction configs | Corrected token/component/pattern/resource/direction/client files + updated findings | Prototype reaches review quality. |
| 16 | Client review | A/B/C prototypes + comparison | Directions, comparison, screenshots, prototype, QA findings | Feedback/state and revised alternatives where justified | Client preference/change set is captured. |
| 17 | Select / mix directions | Client decisions | A/B/C directions + approved-experience template | `approved-experience.yaml` | Approved experience is frozen as the production contract. |
| 18 | Promote reusable learnings | Proven client patterns/resources/components | Client-specific files + shared registries | Design Contract/presets/experience-patterns/resource registry only where justified | Shared system improves without client-specific contamination. |
| 19 | Productionize | Approved experience + production requirements | `workflows/08-productionize.md`, shared Flutter UI, backend/API contracts | Production app, integrations, tests, environment config | Production-ready implementation is produced by the production milestone. |
| 20 | Final QA & release | Production build | Tests, CI/release rules, client approval | PR/CI/release artifacts/docs | Release candidate / production release passes required gates. |

## Mapping to executable workflows

```text
01-client-intake.md          → stages 1–2
02-resolve-intelligence.md   → stages 3–4
03-resource-research.md      → stages 5–6
04-generate-directions.md    → stages 7–8
05-build-prototype.md        → stages 9–13
06-visual-qa.md              → stages 14–15
07-client-review.md          → stages 16–17
08-productionize.md          → stages 18–20
```

The eight-stage runtime is intentionally retained because it provides a compact orchestration surface; the 20-stage flow provides the consulting/detail model within those execution stages.

## Client information architecture

```text
client-projects/<client>/
├── brief.md
├── workflow-state.yaml
├── input/
│   ├── client-input.yaml
│   ├── brand/
│   ├── references/
│   ├── assets/
│   └── source-documents/
├── derived/
│   ├── client-profile.yaml
│   ├── resolved-presets.yaml
│   ├── intelligence-map.yaml
│   ├── capability-map.yaml
│   ├── gaps.yaml
│   └── resource-requirements.yaml
├── resources/
├── directions/
├── prototype/
│   ├── prototype-manifest.yaml
│   ├── fixtures/
│   ├── screenshots/
│   └── qa/
└── approved-experience.yaml
```

## Data-separation rule

```text
INPUT               = supplied / confirmed client facts
DERIVED              = OpenCode/agency interpretation and reusable-intelligence resolution
RESOURCES/DIRECTIONS = project decisions
PROTOTYPE/QA         = executable evidence and review artifacts
APPROVED EXPERIENCE  = frozen client decision contract
PRODUCTION           = later production implementation/release work
```

Never write inference into `input/client-input.yaml`. Never treat attachments or meeting notes as a substitute for `approved-experience.yaml`.