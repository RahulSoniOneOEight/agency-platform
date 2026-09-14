# Client Information Architecture Alignment Design

## Goal

Align the implemented agency platform with the canonical 20-stage operating table by separating client-supplied inputs from OpenCode-derived intelligence and by persisting the gap/resource decisions that currently exist mostly as workflow logic.

## Principle

Client facts, agent derivations, client decisions, and executable artifacts must be stored separately:

```text
INPUT → DERIVED INTELLIGENCE → DECISIONS → EXECUTION → APPROVAL → PRODUCTION
```

The Knowledge Platform, Experience Direction Engine, shared Flutter package, one-app A/B/C prototype runtime, and existing eight workflow files remain intact.

## Canonical client workspace

```text
client-projects/<client>/
├── input/
│   ├── client-input.yaml
│   ├── brand/.gitkeep
│   ├── references/.gitkeep
│   ├── assets/.gitkeep
│   └── source-documents/.gitkeep
├── derived/
│   ├── client-profile.yaml
│   ├── resolved-presets.yaml
│   ├── intelligence-map.yaml
│   ├── capability-map.yaml
│   ├── gaps.yaml
│   └── resource-requirements.yaml
├── resources/
│   └── .gitkeep
├── directions/
│   └── .gitkeep
├── prototype/
│   ├── prototype-manifest.yaml
│   ├── fixtures/
│   ├── screenshots/
│   └── qa/
├── approved-experience.yaml
└── workflow-state.yaml
```

`brief.md` is retained as an optional human-readable intake note, but `input/client-input.yaml` is the canonical client-fact record.

## Canonical artifact semantics

- `input/client-input.yaml`: only supplied/confirmed client facts; no agent inference.
- `derived/client-profile.yaml`: normalized business model, industry, use cases, platforms, personas, jobs, capabilities, constraints.
- `derived/resolved-presets.yaml`: selected business-model, industry, and use-case presets.
- `derived/intelligence-map.yaml`: relevant reusable components, patterns, journeys, variants, themes, and experience-pattern candidates.
- `derived/capability-map.yaml`: each requested capability classified as `reuse`, `extend`, `variant`, `new`, or `client-only` with a target/reference when applicable.
- `derived/gaps.yaml`: only unresolved or genuinely new requirements identified from the capability map.
- `derived/resource-requirements.yaml`: structured asset/package/reference needs before resource search begins.
- `resources/`: client-selected/approved resource records and provenance references.
- `directions/`: validated A/B/C strategy contracts plus comparison.
- `prototype/`: generated executable prototype contract, deterministic fixtures, screenshots, and QA findings.
- `approved-experience.yaml`: frozen client selection/mix contract.

## Mapping the 20-stage table to the existing eight workflows

The existing runtime remains eight executable workflow files. The 20-stage table becomes the canonical operating model within them:

1. `01-client-intake.md` → stages 1–2: client intake + profile derivation.
2. `02-resolve-intelligence.md` → stages 3–4: reusable intelligence + capability/UX gaps.
3. `03-resource-research.md` → stages 5–6: detect resource needs + search/evaluation.
4. `04-generate-directions.md` → stages 7–8: generate + validate directions.
5. `05-build-prototype.md` → stages 9–13: manifest, fixtures, build, render, structural QA.
6. `06-visual-qa.md` → stages 14–15: visual AI QA + correction loop.
7. `07-client-review.md` → stages 16–17: client review + select/mix.
8. `08-productionize.md` → stages 18–20: promote reusable learnings + productionize + final QA/release.

This preserves runtime simplicity while making the detailed consulting flow explicit.

## Runtime path resolution

Add one canonical client-path helper so tooling does not hard-code flat paths in multiple modules. New clients use the new structure. A short compatibility fallback may read legacy root-level `client-profile.yaml` and `resolved-intelligence.yaml` during migration, but all writes use canonical `input/` and `derived/` paths.

## Initializer

`initialize_client` must create the canonical directories and seed:

- `brief.md`;
- `input/client-input.yaml`;
- `derived/client-profile.yaml`;
- `derived/resolved-presets.yaml`;
- `derived/intelligence-map.yaml`;
- `derived/capability-map.yaml`;
- `derived/gaps.yaml`;
- `derived/resource-requirements.yaml`;
- `workflow-state.yaml`;
- `.gitkeep` markers for attachment/resource/direction folders.

Derived files begin empty/explicitly unresolved; they must never contain invented client facts.

## Validation gates

Workflow validation must enforce the new canonical artifacts:

- client-intake completion requires both canonical client input and derived client profile;
- resolve-intelligence completion requires resolved presets, intelligence map, capability map, and gaps;
- resource-research completion requires resource requirements plus the existing resource selection artifact, unless resource research is skipped with a reason;
- later direction/prototype/QA/approval gates remain as already implemented.

## Prototype integration

Prototype tooling reads `derived/client-profile.yaml` through the shared path helper. Direction, fixture, prototype, QA, and approved-experience contracts do not change.

## Documentation

Create `docs/operating-flow.md` as the canonical 20-stage flow summary, using the user-approved table as the operating model. Update `AGENTS.md`, `docs/workflow-runtime.md`, `docs/prototype-platform.md` where paths are referenced, and fix `docs/platform-status.md` to show PR #6 / Milestone B as merged.

## Migration/reference client

Migrate `client-projects/examples/prototype-demo/` to the canonical structure so the regression example demonstrates the same layout future clients receive.

## Non-goals

- Do not replace the eight workflow files with twenty workflow files.
- Do not redesign the Knowledge Platform or Direction Engine.
- Do not fork the Flutter prototype app per client/direction.
- Do not implement production ERP/backend/auth/payment/shipping/CRM/WhatsApp/Supabase/n8n integrations in this change.
- Do not implement the full release platform; stages 19–20 remain documented production-phase gates until their dedicated milestone.

## Success criteria

The change is complete when a newly initialized client has the canonical `input/` and `derived/` structure, runtime/tooling reads that structure, explicit capability/gap/resource-requirement artifacts are validated, the prototype example is migrated, all existing Knowledge/Workflow/Prototype and Flutter CI checks remain green, and the repository documents the 20-stage table as the canonical agency operating flow.