# Milestone B.1A.1 — Client Input Contract

## Purpose

Introduce a canonical client-input layer so raw client/source facts are separated from OpenCode/agency-derived interpretation before Milestone B.1B wires client configuration into the Flutter runtime.

## Core governance rule

```text
client-projects/<client>/input/   = client/source truth
client-projects/<client>/derived/ = agency/OpenCode interpretation
```

OpenCode may normalize, classify, summarize, and infer into `derived/`, but must never silently rewrite an inference into `input/` as if the client supplied it.

## Canonical client structure

```text
client-projects/<client>/
├── input/
│   ├── client-input.yaml
│   ├── business-rules.yaml
│   ├── user-groups.yaml
│   ├── journey-priorities.yaml
│   ├── feature-requirements.yaml
│   ├── platform-requirements.yaml
│   ├── integration-requirements.yaml
│   ├── content-requirements.yaml
│   ├── data-context.yaml
│   ├── constraints.yaml
│   ├── open-questions.yaml
│   ├── brand/
│   │   ├── brand-input.yaml
│   │   └── brand-assets/
│   ├── references/
│   │   ├── references.yaml
│   │   ├── current-app/
│   │   ├── competitor/
│   │   └── inspiration/
│   ├── assets/
│   │   ├── asset-manifest.yaml
│   │   ├── products/
│   │   ├── categories/
│   │   ├── banners/
│   │   ├── sellers/
│   │   └── videos/
│   └── source-documents/
│       └── source-documents.yaml
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
├── approved-experience.yaml
└── workflow-state.yaml
```

Binary/client files such as logo SVGs, brand-guide PDFs, catalogue/pricing spreadsheets, requirements PDFs, and API notes live under the appropriate `input/` subfolder and are referenced by manifest YAML rather than being mandatory fixed filenames.

## Required vs optional inputs

`input/client-input.yaml` is the only mandatory structured client-input file.

All detailed module files are optional at initialization time and become required only when referenced from `client-input.yaml` or when a workflow capability explicitly needs them.

This keeps small-project onboarding light while allowing structured enterprise intake.

## client-input.yaml

`client-input.yaml` is the intake index and source-of-truth manifest. It contains:

- client identity/display name
- source provenance/status
- declared business context
- declared goals/objectives
- links to detailed input modules
- presence/availability of brand, references, assets, and source documents
- unresolved input state

Example:

```yaml
version: 1
client:
  id: acme-retail
  display_name: ACME Retail

source_status: client_supplied

modules:
  business_rules: business-rules.yaml
  user_groups: user-groups.yaml
  journey_priorities: journey-priorities.yaml
  feature_requirements: feature-requirements.yaml
  platform_requirements: platform-requirements.yaml
  integration_requirements: integration-requirements.yaml
  content_requirements: content-requirements.yaml
  data_context: data-context.yaml
  constraints: constraints.yaml
  open_questions: open-questions.yaml

collections:
  brand: brand/brand-input.yaml
  references: references/references.yaml
  assets: assets/asset-manifest.yaml
  source_documents: source-documents/source-documents.yaml
```

Paths are relative to `input/` and must not escape the input directory.

## Detailed input modules

### business-rules.yaml
Captures explicit client business rules only, such as minimum order value, quotation rules, credit rules, returns rules, pricing logic, channel differences, order approval, availability, and business-specific constraints.

### user-groups.yaml
Captures client-declared user/customer/staff groups, labels, access needs, business relationships, and known distinctions. Derived personas belong in `derived/client-profile.yaml`, not here.

### journey-priorities.yaml
Captures the client’s stated priority journeys and desired outcomes, without converting them into UX architecture.

### feature-requirements.yaml
Captures requested capabilities, priorities, acceptance notes, and explicit exclusions.

### platform-requirements.yaml
Captures required platforms, form factors, responsive expectations, browser/device requirements, accessibility statements, offline needs, and distribution expectations.

### integration-requirements.yaml
Captures systems, APIs, ERPs, payment providers, logistics systems, analytics, authentication, messaging, and data exchange requirements. Credentials/secrets must never be stored here.

### content-requirements.yaml
Captures content types, languages, ownership, editorial needs, product/content richness, localization, and content-management expectations.

### data-context.yaml
Captures known data entities, source systems, volumes/ranges where supplied, refresh expectations, and sample-data availability. This is descriptive intake, not a production data model.

### constraints.yaml
Captures explicit budget, timeline, technology, policy, compliance, brand, content, staffing, platform, and operational constraints.

### open-questions.yaml
Captures unresolved client questions with IDs, category, owner, status, blocking level, and resolution when known. Blocking questions can stop workflow advancement.

## Brand, references, assets, and source documents

### brand/brand-input.yaml
Captures explicit brand facts and pointers to supplied files: logo variants, color/typography guidance, tone, brand restrictions, and source provenance.

### references/references.yaml
Indexes current product/app references, competitors, inspiration examples, URLs/files, why each reference matters, and whether it is client-provided or agency-added. Agency-added references must be clearly marked and must not be represented as client input.

### assets/asset-manifest.yaml
Indexes supplied product/category/banner/seller/video assets with IDs, relative paths, media type, usage notes, provenance, and optional metadata.

### source-documents/source-documents.yaml
Indexes supplied PDFs, spreadsheets, API notes, catalogues, pricing files, and other source documents with IDs, relative paths, document type, source/provenance, and processing status.

## Schemas

Add machine-readable JSON Schemas under:

```text
client-projects/schema/input/
```

At minimum:

- `client-input.schema.json`
- `business-rules.schema.json`
- `user-groups.schema.json`
- `journey-priorities.schema.json`
- `feature-requirements.schema.json`
- `platform-requirements.schema.json`
- `integration-requirements.schema.json`
- `content-requirements.schema.json`
- `data-context.schema.json`
- `constraints.schema.json`
- `open-questions.schema.json`
- `brand-input.schema.json`
- `references.schema.json`
- `asset-manifest.schema.json`
- `source-documents.schema.json`

Schemas should validate structure and provenance fields without over-constraining project-specific content.

## Initialization behavior

`tooling/workflow/initialize_client.py` must create the canonical hierarchy.

Initialization must:

1. create `input/` and `derived/`;
2. create all standard subdirectories;
3. create `input/client-input.yaml` with the client ID/name and empty module/collection references;
4. create optional module templates so they are discoverable, but mark them empty/not-provided rather than inventing facts;
5. create `derived/client-profile.yaml` rather than root `client-profile.yaml`;
6. preserve `workflow-state.yaml` at client root;
7. stop creating legacy root `references/` and `fixtures/` folders as intake containers;
8. retain `resources/`, `directions/`, and `prototype/` as downstream areas.

## Client-profile derivation

The existing `client-profile.schema.json` remains the normalized/derived profile contract.

The client-intake workflow should derive:

```text
input/client-input.yaml
+ referenced input modules
        ↓
client-projects/<client>/derived/client-profile.yaml
```

The derived profile may normalize client wording into platform vocabulary, for example:

```text
input/user-groups.yaml
  dealer
  installer
  retail customer

        ↓

derived/client-profile.yaml
  personas:
    - trade-dealer
    - installer
    - retail-customer
```

Every derived value must be traceable to an input source or explicitly marked as an agency inference where applicable.

## Backward compatibility

Existing example/client projects using root `client-profile.yaml` must be migrated to `derived/client-profile.yaml` in the same change, and all workflow/prototype tooling must read the canonical derived location.

No permanent dual-read fallback should remain after migration; the repository should converge on one path.

## Workflow changes

Update `workflows/01-client-intake.md` so that it:

- reads `input/` client/source truth;
- validates `client-input.yaml` and referenced module files;
- records unresolved blocking questions;
- writes normalized understanding to `derived/client-profile.yaml`;
- never overwrites client input during derivation;
- marks intake complete only when required input contracts are valid and no intake-blocking question remains.

Downstream workflows should read `derived/client-profile.yaml` rather than treating raw input as normalized knowledge.

## Validation tooling

Add a focused client-input validator that:

1. validates `client-input.yaml` against schema;
2. validates referenced module/collection manifests against their schemas;
3. verifies referenced relative paths stay inside `input/`;
4. reports missing referenced files;
5. rejects duplicate manifest IDs where IDs are defined;
6. reports unresolved questions with `blocking: true` as workflow blockers;
7. never raises on malformed input; returns structured validation errors.

The workflow validator must use this validation before intake can advance.

## Reference example

Migrate `client-projects/examples/prototype-demo/` to demonstrate the contract with a small but meaningful input set:

- `input/client-input.yaml`
- user groups
- journey priorities
- feature requirements
- platform requirements
- constraints/open questions
- one brand manifest
- one references manifest
- one asset manifest
- one source-document manifest
- `derived/client-profile.yaml`

The example should not require fake binary PDFs/XLSX/SVG files solely to satisfy the contract; manifest entries should reference files only when those files genuinely exist.

## Out of scope

This milestone does not:

- implement Flutter runtime loading (B.1B);
- build a document ingestion/OCR system;
- parse spreadsheets/PDFs into business objects;
- add production secrets or credentials;
- implement production integrations;
- redesign Design Contract tokens/themes;
- implement screenshot/visual QA execution.

## Testing

Required coverage:

- initialized client receives canonical directory structure;
- `client-input.yaml` is created and schema-valid;
- optional module templates contain no invented facts;
- referenced module files are validated;
- path escape references are rejected;
- missing referenced files are reported;
- malformed YAML/schema data returns errors rather than raising;
- blocking open questions prevent intake completion;
- derived profile path is used by workflow/router/prototype tooling;
- legacy root `client-profile.yaml` references are removed from active tooling;
- reference example validates end-to-end through intake.

## Success criteria

B.1A.1 is complete when:

1. `input/` is the canonical client/source truth layer;
2. `derived/` is the canonical interpretation layer;
3. initialization creates the complete standard hierarchy;
4. schemas and validation govern the input manifests;
5. the intake workflow enforces the source-truth/derived boundary;
6. downstream tooling uses `derived/client-profile.yaml`;
7. unresolved blocking questions can prevent intake completion;
8. the reference client demonstrates the new structure;
9. repository validation and existing prototype/knowledge/workflow tests remain green.
