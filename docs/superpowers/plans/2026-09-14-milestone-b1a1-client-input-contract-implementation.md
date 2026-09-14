# Milestone B.1A.1 Client Input Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `client-projects/<client>/input/` the canonical client/source-truth layer and `client-projects/<client>/derived/` the canonical normalized interpretation layer, with schemas, validation, workflow gating, initialization, and reference-client migration.

**Architecture:** Keep client-provided facts immutable-in-place from the derivation flow: intake manifests live under `input/`, normalized/agency-inferred artifacts live under `derived/`, and downstream workflow/prototype tooling reads `derived/client-profile.yaml`. `input/client-input.yaml` is the required index; detailed module files are optional unless referenced. A focused validator enforces schemas, path containment, referenced-file existence, duplicate IDs, and blocking open questions without raising on malformed input.

**Tech Stack:** Python 3.12, PyYAML, jsonschema Draft 2020-12, JSON Schema, existing workflow/router/prototype tooling, unittest, GitHub Actions repository validation.

**Spec:** `docs/superpowers/specs/2026-09-14-milestone-b1a1-client-input-contract-design.md`

## Global Constraints

- `client-projects/<client>/input/` is client/source truth.
- `client-projects/<client>/derived/` is agency/OpenCode interpretation.
- `input/client-input.yaml` is the only mandatory structured client-input file at initialization.
- Optional module files become required when referenced from `client-input.yaml`.
- Paths in input manifests are relative to `input/` and must not escape it.
- OpenCode may normalize/classify/infer into `derived/` but must never silently rewrite an inference into `input/`.
- Existing active tooling must converge on `derived/client-profile.yaml`; no permanent dual-read fallback remains.
- Credentials/secrets must never be stored in `integration-requirements.yaml`.
- Binary documents/assets are optional and referenced from manifests; do not fabricate binary files for the example client.
- Validation must return structured errors and must not raise on malformed client input.
- Blocking open questions prevent client-intake completion.
- B.1A.1 does not implement Flutter runtime loading, OCR/document ingestion, spreadsheet/PDF parsing, production integrations, Design Contract redesign, or screenshot execution.

---

## File Structure / Responsibility Map

### New schema files
- `client-projects/schema/input/client-input.schema.json` — required intake index schema.
- `client-projects/schema/input/business-rules.schema.json` — explicit business-rule entries.
- `client-projects/schema/input/user-groups.schema.json` — client-declared user groups.
- `client-projects/schema/input/journey-priorities.schema.json` — declared journey priorities.
- `client-projects/schema/input/feature-requirements.schema.json` — requested/optional/excluded features.
- `client-projects/schema/input/platform-requirements.schema.json` — platform/device/browser/accessibility requirements.
- `client-projects/schema/input/integration-requirements.schema.json` — integration requirements without secrets.
- `client-projects/schema/input/content-requirements.schema.json` — languages/content/CMS needs.
- `client-projects/schema/input/data-context.schema.json` — descriptive data-source/entity/volume context.
- `client-projects/schema/input/constraints.schema.json` — explicit constraints.
- `client-projects/schema/input/open-questions.schema.json` — unresolved questions and blocking flags.
- `client-projects/schema/input/brand-input.schema.json` — brand facts and supplied-file pointers.
- `client-projects/schema/input/references.schema.json` — current-app/competitor/inspiration references with provenance.
- `client-projects/schema/input/asset-manifest.schema.json` — supplied asset index.
- `client-projects/schema/input/source-documents.schema.json` — source-document index.

### New validation tooling
- `tooling/workflow/client_input.py` — load/validate input index and referenced modules; path containment; duplicate IDs; blocking questions.

### Modified workflow/tooling files
- `tooling/workflow/initialize_client.py` — canonical hierarchy and templates.
- `tooling/workflow/router.py` — derived profile path + intake blocker behavior.
- `tooling/workflow/validate_workflow.py` — validate client input before intake completion and update path expectations.
- `tooling/prototype/build_prototype.py` — read `derived/client-profile.yaml`.
- `workflows/01-client-intake.md` — explicit source-truth → derived flow.
- `workflows/02-resolve-intelligence.md` through `05-build-prototype.md` where needed — read derived profile path.
- `docs/workflow-runtime.md` — canonical workspace example.

### Example migration
- `client-projects/examples/prototype-demo/input/**` — small valid input set.
- `client-projects/examples/prototype-demo/derived/client-profile.yaml` — migrated normalized profile.
- remove legacy `client-projects/examples/prototype-demo/client-profile.yaml`.

### Tests
- `tooling/validation/test_client_input_contract.py` — focused schema/validator tests.
- `tooling/validation/test_workflow_runtime.py` — initializer/router/intake-stage tests.
- `tooling/validation/test_prototype_platform.py` — derived profile path regression.
- `tooling/validation/test_prototype_workflow_integration.py` — end-to-end path update.
- `.github/workflows/validate.yml` — include focused test if suite list is explicit.

---

### Task 1: Add Client Input Schemas and Focused Validator

**Files:**
- Create: `client-projects/schema/input/client-input.schema.json`
- Create: `client-projects/schema/input/business-rules.schema.json`
- Create: `client-projects/schema/input/user-groups.schema.json`
- Create: `client-projects/schema/input/journey-priorities.schema.json`
- Create: `client-projects/schema/input/feature-requirements.schema.json`
- Create: `client-projects/schema/input/platform-requirements.schema.json`
- Create: `client-projects/schema/input/integration-requirements.schema.json`
- Create: `client-projects/schema/input/content-requirements.schema.json`
- Create: `client-projects/schema/input/data-context.schema.json`
- Create: `client-projects/schema/input/constraints.schema.json`
- Create: `client-projects/schema/input/open-questions.schema.json`
- Create: `client-projects/schema/input/brand-input.schema.json`
- Create: `client-projects/schema/input/references.schema.json`
- Create: `client-projects/schema/input/asset-manifest.schema.json`
- Create: `client-projects/schema/input/source-documents.schema.json`
- Create: `tooling/workflow/client_input.py`
- Create: `tooling/validation/test_client_input_contract.py`

**Interfaces:**
- Consumes: `client-projects/<client>/input/client-input.yaml` and referenced files under the same `input/` root.
- Produces: `validate_client_input(root: Path, client_dir: Path) -> list[str]` and `blocking_open_questions(client_dir: Path) -> list[dict]`.

- [ ] **Step 1: Write failing validator tests**

Create tests covering:

```python
class ClientInputContractTests(unittest.TestCase):
    def test_minimal_client_input_validates(self): ...
    def test_referenced_module_is_schema_validated(self): ...
    def test_missing_referenced_file_is_reported(self): ...
    def test_path_escape_is_rejected(self): ...
    def test_malformed_yaml_returns_error_not_exception(self): ...
    def test_duplicate_manifest_ids_are_rejected(self): ...
    def test_blocking_open_question_is_reported(self): ...
    def test_unreferenced_optional_template_does_not_block(self): ...
```

Use temporary client directories; never depend on the committed example for malformed-input tests.

- [ ] **Step 2: Run focused tests and confirm red state**

Run:

```bash
python -m unittest tooling.validation.test_client_input_contract -v
```

Expected: import/file failures because the validator and schemas do not exist yet.

- [ ] **Step 3: Implement schemas with shared conventions**

Use Draft 2020-12. Every schema must require `version: 1` plus only the minimum stable structural fields. Keep project-specific content extensible with `additionalProperties: true` unless the structure itself is the contract.

For manifest-like collections (`references`, `assets`, `source_documents`) define item IDs as non-empty strings so duplicate-ID checking can be deterministic.

`client-input.schema.json` must require:

```json
["version", "client", "source_status", "modules", "collections"]
```

and require `client.id` and `client.display_name`.

- [ ] **Step 4: Implement `tooling/workflow/client_input.py`**

Required public functions:

```python
def validate_client_input(root: Path, client_dir: Path) -> list[str]:
    ...

def blocking_open_questions(client_dir: Path) -> list[dict]:
    ...
```

Implementation requirements:
- load YAML defensively;
- validate `input/client-input.yaml` first;
- resolve referenced module/collection paths relative to `input/`;
- reject absolute paths and any resolved path outside `input/`;
- validate referenced files against the matching schema;
- report missing referenced files;
- detect duplicate `id` values in manifest arrays when present;
- inspect referenced `open_questions` and return entries with `blocking: true` and status not equal to `resolved`;
- catch parse/schema/type errors and return messages rather than raising.

- [ ] **Step 5: Run focused tests and confirm green**

```bash
python -m unittest tooling.validation.test_client_input_contract -v
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add client-projects/schema/input tooling/workflow/client_input.py tooling/validation/test_client_input_contract.py
git commit -m "feat: add canonical client input schemas and validator"
```

---

### Task 2: Make Client Initialization Create the Canonical Input/Derived Hierarchy

**Files:**
- Modify: `tooling/workflow/initialize_client.py`
- Modify: `tooling/validation/test_workflow_runtime.py`

**Interfaces:**
- Consumes: `initialize_client(root, client_id, display_name)` existing API.
- Produces: canonical directory hierarchy, schema-valid `input/client-input.yaml`, optional empty templates, and `derived/client-profile.yaml`.

- [ ] **Step 1: Add failing initializer tests**

Assert initialization creates:

```text
input/
input/brand/brand-assets/
input/references/current-app/
input/references/competitor/
input/references/inspiration/
input/assets/products/
input/assets/categories/
input/assets/banners/
input/assets/sellers/
input/assets/videos/
input/source-documents/
derived/
resources/
directions/
prototype/
workflow-state.yaml
```

Also assert:
- `input/client-input.yaml` validates through `validate_client_input`;
- all optional YAML templates exist but contain `provided: false` or empty collections, with no invented client facts;
- root `client-profile.yaml`, root `references/`, and root `fixtures/` are not created;
- `derived/client-profile.yaml` exists.

- [ ] **Step 2: Run initializer tests and confirm failure**

```bash
python -m unittest tooling.validation.test_workflow_runtime -v
```

Expected: existing initializer structure assertions fail.

- [ ] **Step 3: Update `initialize_client.py`**

Create the complete hierarchy from the spec. Write `input/client-input.yaml` with:

```yaml
version: 1
client:
  id: <client-id>
  display_name: <display-name>
source_status: client_supplied
modules: {}
collections: {}
unresolved_input: true
```

Create each optional module template with `version: 1`, `provided: false`, and an empty domain collection (for example `rules: []`, `groups: []`, `questions: []`). Do not pre-reference these optional templates in `client-input.yaml`.

Create `derived/client-profile.yaml` using the existing profile field shape but with empty normalized values except ID/display name.

- [ ] **Step 4: Run initializer + client-input tests**

```bash
python -m unittest tooling.validation.test_client_input_contract tooling.validation.test_workflow_runtime -v
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add tooling/workflow/initialize_client.py tooling/validation/test_workflow_runtime.py
git commit -m "feat: initialize canonical client input workspace"
```

---

### Task 3: Enforce Intake Validation and Derived Profile Path in Workflow Runtime

**Files:**
- Modify: `tooling/workflow/router.py`
- Modify: `tooling/workflow/validate_workflow.py`
- Modify: `tooling/validation/test_workflow_runtime.py`
- Modify: `workflows/01-client-intake.md`

**Interfaces:**
- Consumes: `validate_client_input(...)`, `blocking_open_questions(...)`, `derived/client-profile.yaml`.
- Produces: intake stage cannot advance with invalid input, missing derived profile, or unresolved blocking question.

- [ ] **Step 1: Add failing workflow tests**

Cover these behaviors:

```python
def test_router_blocks_intake_when_client_input_invalid(): ...
def test_router_blocks_intake_when_blocking_question_open(): ...
def test_router_requires_derived_client_profile_after_intake(): ...
def test_router_allows_intake_progress_with_valid_nonblocking_inputs(): ...
```

Ensure tests use the canonical directory layout rather than legacy root profile paths.

- [ ] **Step 2: Run workflow tests and confirm red state**

```bash
python -m unittest tooling.validation.test_workflow_runtime -v
```

- [ ] **Step 3: Update router and workflow validation**

Behavior:
- before `client-intake` can be considered complete/advance, call the focused client-input validator;
- unresolved `blocking: true` questions are blockers;
- after intake completion, require `derived/client-profile.yaml`;
- return clear structured blocker reasons such as `client-input-invalid`, `blocking-open-questions`, `derived-client-profile-missing`;
- never accept root `client-profile.yaml` as fallback.

- [ ] **Step 4: Rewrite `workflows/01-client-intake.md` contract**

READ must point to `client-projects/<client>/input/` and schemas. WRITE must point to `derived/client-profile.yaml` and `workflow-state.yaml`. PROCESS must explicitly preserve client truth, mark inferences as derived, and never edit input merely to satisfy derivation. VALIDATE must require valid referenced input plus no unresolved blocking questions.

- [ ] **Step 5: Run workflow tests**

```bash
python -m unittest tooling.validation.test_client_input_contract tooling.validation.test_workflow_runtime -v
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add tooling/workflow/router.py tooling/workflow/validate_workflow.py tooling/validation/test_workflow_runtime.py workflows/01-client-intake.md
git commit -m "feat: gate workflow intake on client input contract"
```

---

### Task 4: Migrate Downstream Tooling to `derived/client-profile.yaml`

**Files:**
- Modify: `tooling/prototype/build_prototype.py`
- Modify: `workflows/02-resolve-intelligence.md`
- Modify: `workflows/03-resource-research.md`
- Modify: `workflows/04-generate-directions.md`
- Modify: `workflows/05-build-prototype.md`
- Modify: `tooling/validation/test_prototype_platform.py`
- Modify: `tooling/validation/test_prototype_workflow_integration.py`
- Modify as required by search: active runtime/tooling references to root `client-profile.yaml`

**Interfaces:**
- Consumes: normalized profile only from `client-projects/<client>/derived/client-profile.yaml`.
- Produces: zero active tooling reads of root `client-profile.yaml`.

- [ ] **Step 1: Add failing prototype/integration regressions**

Update test fixtures to place profiles at:

```text
client-projects/<client>/derived/client-profile.yaml
```

Add a regression that a client with only root `client-profile.yaml` is rejected by active tooling.

- [ ] **Step 2: Run tests and confirm failure**

```bash
python -m unittest tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
```

- [ ] **Step 3: Update prototype composer and active workflows**

In `build_prototype.py`, replace root lookup with:

```python
profile_path = client_dir / "derived" / "client-profile.yaml"
```

Use an error message that names the canonical path. Update workflow READ sections 02–05 to the same path. Search the active runtime/tooling surface for `client-profile.yaml` and migrate operational references; historical specs/plans may remain historical.

- [ ] **Step 4: Verify no active legacy reads remain**

Run:

```bash
git grep -n 'client-profile.yaml' -- tooling workflows templates docs/*.md client-projects ':!docs/superpowers/specs/*' ':!docs/superpowers/plans/*'
```

Inspect every result. Active reads must use `derived/client-profile.yaml`; schema/template documentation may mention the filename as a contract name but not as a root project path.

- [ ] **Step 5: Run prototype/integration tests**

```bash
python -m unittest tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

```bash
git add tooling/prototype/build_prototype.py workflows tooling/validation/test_prototype_platform.py tooling/validation/test_prototype_workflow_integration.py
git commit -m "refactor: use derived client profile across active workflows"
```

---

### Task 5: Migrate the Reference Prototype Client to the New Contract

**Files:**
- Create: `client-projects/examples/prototype-demo/input/client-input.yaml`
- Create: `client-projects/examples/prototype-demo/input/user-groups.yaml`
- Create: `client-projects/examples/prototype-demo/input/journey-priorities.yaml`
- Create: `client-projects/examples/prototype-demo/input/feature-requirements.yaml`
- Create: `client-projects/examples/prototype-demo/input/platform-requirements.yaml`
- Create: `client-projects/examples/prototype-demo/input/constraints.yaml`
- Create: `client-projects/examples/prototype-demo/input/open-questions.yaml`
- Create: `client-projects/examples/prototype-demo/input/brand/brand-input.yaml`
- Create: `client-projects/examples/prototype-demo/input/references/references.yaml`
- Create: `client-projects/examples/prototype-demo/input/assets/asset-manifest.yaml`
- Create: `client-projects/examples/prototype-demo/input/source-documents/source-documents.yaml`
- Create: `client-projects/examples/prototype-demo/derived/client-profile.yaml`
- Remove: `client-projects/examples/prototype-demo/client-profile.yaml`
- Modify: `tooling/validation/test_client_input_contract.py`

**Interfaces:**
- Consumes: existing example facts only; do not fabricate binaries.
- Produces: one committed reference client that validates through the intake contract and remains usable by prototype composition.

- [ ] **Step 1: Add reference-client validation test**

```python
def test_reference_prototype_demo_validates_end_to_end():
    root = Path(__file__).resolve().parents[2]
    client = root / "client-projects" / "examples" / "prototype-demo"
    self.assertEqual([], validate_client_input(root, client))
    self.assertTrue((client / "derived" / "client-profile.yaml").exists())
    self.assertFalse((client / "client-profile.yaml").exists())
```

- [ ] **Step 2: Run test and confirm failure**

```bash
python -m unittest tooling.validation.test_client_input_contract -v
```

- [ ] **Step 3: Create the small meaningful input set**

Use facts already represented by the example client/profile/directions. The example should include:
- at least one user group;
- at least one journey priority;
- at least one feature requirement;
- platform requirements;
- one explicit constraint;
- open questions with no unresolved blocking item;
- brand manifest with no fake file pointer;
- references manifest with at least one metadata-only reference if an actual URL/fact exists; otherwise empty but `provided: false`;
- asset and source-document manifests with empty arrays if no real files exist.

Reference only the module files from `client-input.yaml` that are actually populated/provided. Keep empty optional manifests discoverable but unreferenced when `provided: false`.

- [ ] **Step 4: Move normalized profile to `derived/`**

Preserve its existing normalized values exactly unless required for schema validity. Do not reinterpret example business facts during this migration.

- [ ] **Step 5: Run focused + prototype tests**

```bash
python -m unittest tooling.validation.test_client_input_contract tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
```

Expected: PASS.

- [ ] **Step 6: Commit Task 5**

```bash
git add client-projects/examples/prototype-demo tooling/validation/test_client_input_contract.py
git commit -m "test: migrate reference client to canonical input contract"
```

---

### Task 6: Repository Validation, Documentation, and CI Integration

**Files:**
- Modify: `tooling/validation/validate_repo.py` if structural checks enumerate required schema/tooling paths.
- Modify: `.github/workflows/validate.yml` if unittest modules are explicitly listed.
- Modify: `docs/workflow-runtime.md`
- Modify: `AGENTS.md` if client-project governance paths are documented there.
- Modify: `tooling/validation/test_validate_repo.py` as needed.

**Interfaces:**
- Consumes: all Task 1–5 contracts.
- Produces: repository-level guardrails and documentation matching the implemented client-input boundary.

- [ ] **Step 1: Add/adjust repository validation test**

Ensure repository validation requires:
- `client-projects/schema/input/client-input.schema.json`;
- `tooling/workflow/client_input.py`;
- canonical workflow docs;
- reference client input/derived structure where the current validator treats examples as required platform fixtures.

- [ ] **Step 2: Run repository validator tests and confirm any intended red state**

```bash
python -m unittest tooling.validation.test_validate_repo -v
```

- [ ] **Step 3: Update repository validation and CI test list**

If `.github/workflows/validate.yml` explicitly names unittest modules, include:

```text
tooling.validation.test_client_input_contract
```

Do not duplicate test execution if CI already discovers tests automatically.

- [ ] **Step 4: Update runtime documentation**

`docs/workflow-runtime.md` must show:

```text
client-projects/<client>/
  input/
  derived/client-profile.yaml
  resources/
  directions/
  prototype/
  workflow-state.yaml
```

Document the governance rule `INPUT = client/source truth`, `DERIVED = agency/OpenCode interpretation` and the rule that optional modules only become required when referenced or capability-required.

- [ ] **Step 5: Run the full Python verification suite**

Run:

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_client_input_contract tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

Expected: all tests pass and all validators exit 0.

- [ ] **Step 6: Run Flutter regression verification**

From each Flutter package/app used by CI, run the same analyze/test commands as `.github/workflows/flutter.yml`. At minimum:

```bash
cd packages/agency_flutter_ui && flutter pub get && flutter analyze && flutter test
cd ../../apps/prototype_app && flutter pub get && flutter analyze && flutter test && flutter build web
cd ../widgetbook && flutter pub get && flutter analyze && flutter test
```

Expected: all commands exit 0.

- [ ] **Step 7: Final active-path search**

Run:

```bash
git grep -n 'client-projects/<client>/client-profile.yaml\|client_dir / "client-profile.yaml"\|/references/' -- tooling workflows docs AGENTS.md
```

Review each result and remove stale active-path assumptions. Historical specs/plans are exempt if clearly historical.

- [ ] **Step 8: Commit Task 6**

```bash
git add .github/workflows tooling/validation docs/workflow-runtime.md AGENTS.md
git commit -m "docs: enforce canonical client input and derived boundaries"
```

---

## Final Verification Checklist

Before opening a PR, verify each success criterion from the spec explicitly:

- [ ] `input/` is the canonical client/source-truth layer.
- [ ] `derived/` is the canonical interpretation layer.
- [ ] initialization creates the complete hierarchy.
- [ ] `client-input.yaml` is mandatory and schema-valid.
- [ ] optional modules are not mandatory unless referenced.
- [ ] referenced modules/collections validate against their schemas.
- [ ] path escapes and missing referenced files are rejected.
- [ ] duplicate manifest IDs are rejected.
- [ ] malformed YAML returns validation errors rather than exceptions.
- [ ] blocking open questions prevent intake completion.
- [ ] workflow/router/prototype tooling use `derived/client-profile.yaml`.
- [ ] no active root-profile fallback remains.
- [ ] reference example demonstrates the input/derived structure.
- [ ] Python full suite and validators pass.
- [ ] Flutter analyze/tests/web build remain green.

## PR Boundary

Suggested title:

```text
Milestone B.1A.1: canonical client input and derived contracts
```

PR summary should explicitly state that this milestone changes the upstream client/project contract only. Flutter runtime loading remains B.1B.
