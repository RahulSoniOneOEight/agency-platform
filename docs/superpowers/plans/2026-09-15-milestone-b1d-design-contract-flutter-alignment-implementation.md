# Milestone B.1D — Design Contract ↔ Flutter Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `design-contract/` the authoritative source for canonical component/pattern IDs and supported variants/states/density, with deterministic validated Flutter implementation bindings consumed by the prototype runtime.

**Architecture:** Add a machine-readable Flutter binding catalog under `design-contract/bindings/flutter/`, validate it against canonical component/pattern contracts and current runtime directions, and deterministically generate a checked Dart binding projection. The prototype app resolves canonical IDs through that generated projection before dispatching to `agency_flutter_ui`; runtime bundles keep canonical IDs unchanged.

**Tech Stack:** Python 3.12, PyYAML, JSON Schema-style repository validation, Dart/Flutter 3.47.x, `agency_flutter_ui`, Flutter tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-15-milestone-b1d-design-contract-flutter-alignment-design.md`

## Global Constraints

- `design-contract/` is authoritative for canonical IDs and supported UX metadata.
- Flutter registry keys, Dart class names, enum names, and widget factories are implementation details.
- Runtime bundles continue to carry canonical IDs unchanged.
- Canonical-to-Flutter translation must be explicit and allowlisted; heuristic prefix stripping or convention-based inference is forbidden.
- Missing or invalid bindings must fail deterministically before client review; no silent fallback.
- B.1A runtime direction schema and B.1B bundle shape remain backward-compatible.
- B.1D governs states as capability metadata only; it does not add a new state machine.
- Validation error ordering must be stable-sorted.
- Checked generated Dart binding output must byte-match a fresh deterministic projection in CI.
- Do not build the B.1E token/theme system in this milestone.

---

## File Structure

**Create**
- `design-contract/schema/flutter-binding.schema.json` — binding document contract.
- `design-contract/bindings/flutter/*.yaml` — approved component/pattern binding records used by current runtime directions.
- `tooling/design_contract/flutter_bindings.py` — load, normalize, validate, and project bindings.
- `tooling/design_contract/generate_flutter_bindings.py` — deterministic Dart projection writer/checker.
- `tooling/validation/test_flutter_bindings.py` — Python regression suite.
- `apps/prototype_app/lib/registry/generated_design_bindings.dart` — checked generated Dart projection.
- `apps/prototype_app/lib/registry/design_contract_resolver.dart` — governed canonical-ID resolver.
- `apps/prototype_app/test/registry/design_contract_resolver_test.dart` — resolver/variant/density tests.

**Modify**
- `tooling/validation/validate_repo.py` — include binding validation and freshness checks.
- `tooling/validation/test_runtime_bundle.py` — require every runtime pattern/component/variant to have approved Flutter binding.
- `apps/prototype_app/lib/registry/prototype_registry.dart` — resolve patterns through Design Contract resolver.
- `apps/prototype_app/lib/direction/prototype_direction.dart` — expose canonical density name alongside internal enum mapping if needed for binding checks.
- `apps/prototype_app/lib/registry/canonical_pattern_adapter.dart` — remove after generated resolver parity is proven.
- `apps/prototype_app/test/registry/canonical_pattern_adapter_test.dart` — replace with resolver coverage.
- `docs/client-runtime.md`, `docs/prototype-platform.md`, `docs/platform-status.md` — document B.1D boundary and status.

---

### Task 1: Binding schema, loader, and canonical validation

**Files:**
- Create: `design-contract/schema/flutter-binding.schema.json`
- Create: `tooling/design_contract/flutter_bindings.py`
- Create: `tooling/validation/test_flutter_bindings.py`

**Interfaces:**
- Consumes: canonical YAML records under `design-contract/components/` and `design-contract/patterns/`.
- Produces: `load_flutter_bindings(root: Path) -> dict[str, dict]`, `validate_flutter_bindings(root: Path, bindings: dict | None = None) -> list[str]`, and `runtime_binding_errors(root: Path, runtime_direction: dict, bindings: dict | None = None) -> list[str]`.

- [ ] **Step 1: Write failing loader/schema tests**

Add tests equivalent to:

```python
class FlutterBindingTests(unittest.TestCase):
    def test_missing_contract_is_rejected(self):
        root = make_contract_root()
        write_binding(root, {
            "id": "commerce.unknown",
            "kind": "component",
            "status": "approved",
            "implementation": {
                "package": "agency_flutter_ui",
                "registry_key": "unknown",
                "symbol": "UnknownWidget",
            },
            "variants": {"standard": "standard"},
            "states": {"normal": "supported"},
            "density": {"normal": "normal"},
        })
        self.assertIn(
            "binding commerce.unknown: canonical component contract not found",
            validate_flutter_bindings(root),
        )

    def test_binding_metadata_must_be_subset_of_contract(self):
        root = make_contract_root()
        write_component(root, variants=["standard"], states=["normal"], density=["normal"])
        write_binding(root, component_binding(variants={"premium": "premium"}))
        errors = validate_flutter_bindings(root)
        self.assertIn(
            "binding commerce.product-card: variant premium is not declared by canonical contract",
            errors,
        )
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bat
py -3.12 -m unittest tooling.validation.test_flutter_bindings -v
```

Expected: import/file failures because the binding module and schema do not yet exist.

- [ ] **Step 3: Add binding schema**

Define `flutter-binding.schema.json` with required fields:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["id", "kind", "status", "implementation", "variants", "states", "density"],
  "properties": {
    "id": {"type": "string", "minLength": 1},
    "kind": {"enum": ["component", "pattern"]},
    "status": {"enum": ["experimental", "approved", "deprecated"]},
    "implementation": {
      "type": "object",
      "required": ["package", "registry_key", "symbol"],
      "properties": {
        "package": {"const": "agency_flutter_ui"},
        "registry_key": {"type": "string", "minLength": 1},
        "symbol": {"type": "string", "minLength": 1}
      },
      "additionalProperties": false
    },
    "variants": {"type": "object", "additionalProperties": {"type": "string"}},
    "states": {"type": "object", "additionalProperties": {"enum": ["supported", "unsupported"]}},
    "density": {"type": "object", "additionalProperties": {"type": "string"}}
  },
  "additionalProperties": false
}
```

- [ ] **Step 4: Implement deterministic binding loader and validator**

Implement `tooling/design_contract/flutter_bindings.py` so it:
- loads `design-contract/bindings/flutter/*.yaml` in filename-sorted order;
- rejects non-mapping documents and duplicate canonical IDs;
- loads canonical component/pattern records by `id`;
- requires binding kind to match the source catalog;
- requires an approved binding to point to an approved canonical contract;
- verifies variants/states/density keys are subsets of canonical declarations;
- rejects duplicate internal pattern registry targets and duplicate component implementation identifiers where uniqueness is required;
- returns `sorted(set(errors))`.

- [ ] **Step 5: Add runtime-direction validation helper**

`runtime_binding_errors()` must verify each runtime `patterns[]`, `components[]`, and each `component_variants[]` entry resolves to an approved binding. It must also verify runtime density `compact|normal|spacious` exists in every referenced component binding density map.

- [ ] **Step 6: Run focused tests and confirm GREEN**

```bat
py -3.12 -m unittest tooling.validation.test_flutter_bindings -v
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bat
git add design-contract/schema/flutter-binding.schema.json tooling/design_contract/flutter_bindings.py tooling/validation/test_flutter_bindings.py
git commit -m "feat: validate Flutter design contract bindings"
```

---

### Task 2: Seed governed pattern and component bindings

**Files:**
- Create: `design-contract/bindings/flutter/commerce-home.yaml`
- Create: `design-contract/bindings/flutter/commerce-search.yaml`
- Create: `design-contract/bindings/flutter/commerce-plp.yaml`
- Create: `design-contract/bindings/flutter/commerce-pdp.yaml`
- Create: `design-contract/bindings/flutter/commerce-cart.yaml`
- Create: `design-contract/bindings/flutter/commerce-rfq.yaml`
- Create: `design-contract/bindings/flutter/commerce-reorder.yaml`
- Create: `design-contract/bindings/flutter/commerce-trade-dashboard.yaml`
- Create component binding YAML files for every component referenced by the checked A/B/C runtime directions.
- Modify/Test: `tooling/validation/test_flutter_bindings.py`

**Interfaces:**
- Consumes: current runtime directions under `client-projects/examples/prototype-demo/prototype/runtime/` and canonical records under `design-contract/`.
- Produces: complete approved binding coverage for current prototype runtime references.

- [ ] **Step 1: Write failing repository-coverage test**

```python
def test_current_runtime_directions_have_complete_approved_bindings(self):
    root = REPO_ROOT
    bindings = load_flutter_bindings(root)
    errors = []
    for path in sorted((root / "client-projects/examples/prototype-demo/prototype/runtime").glob("direction-*.json")):
        direction = json.loads(path.read_text(encoding="utf-8"))
        errors.extend(runtime_binding_errors(root, direction, bindings))
    self.assertEqual([], sorted(errors))
```

- [ ] **Step 2: Run test and confirm RED**

```bat
py -3.12 -m unittest tooling.validation.test_flutter_bindings.FlutterBindingTests.test_current_runtime_directions_have_complete_approved_bindings -v
```

Expected: FAIL listing missing bindings.

- [ ] **Step 3: Seed pattern binding records**

Each pattern binding must use canonical `id`, `kind: pattern`, `status: approved`, `package: agency_flutter_ui`, explicit `registry_key`, and concrete existing Dart symbol. Example:

```yaml
id: commerce.cart
kind: pattern
status: approved
implementation:
  package: agency_flutter_ui
  registry_key: cart
  symbol: CartPattern
variants: {}
states: {}
density:
  compact: dense
  normal: balanced
  spacious: airy
```

Do not infer targets from IDs; record each explicitly.

- [ ] **Step 4: Seed current component binding records**

For `commerce.product-card` and every other component used by the checked runtime directions, map only variants/states/density actually supported by the existing Flutter implementation. If a canonical variant is declared but not implemented, do not claim support; runtime validation must fail if such a variant is requested.

- [ ] **Step 5: Run focused coverage + full binding tests**

```bat
py -3.12 -m unittest tooling.validation.test_flutter_bindings -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bat
git add design-contract/bindings/flutter tooling/validation/test_flutter_bindings.py
git commit -m "feat: add governed Flutter implementation bindings"
```

---

### Task 3: Deterministic Dart binding projection

**Files:**
- Create: `tooling/design_contract/generate_flutter_bindings.py`
- Create: `apps/prototype_app/lib/registry/generated_design_bindings.dart`
- Modify/Test: `tooling/validation/test_flutter_bindings.py`

**Interfaces:**
- Consumes: normalized approved bindings from `load_flutter_bindings(root)`.
- Produces: `render_flutter_bindings(root: Path) -> str`, `write_flutter_bindings(root: Path) -> Path`, `check_flutter_bindings_fresh(root: Path) -> list[str]` and checked Dart constants.

- [ ] **Step 1: Write failing deterministic projection tests**

```python
def test_generated_dart_projection_is_deterministic(self):
    first = render_flutter_bindings(REPO_ROOT)
    second = render_flutter_bindings(REPO_ROOT)
    self.assertEqual(first, second)
    self.assertTrue(first.endswith("\n"))

def test_checked_projection_matches_fresh_generation(self):
    self.assertEqual([], check_flutter_bindings_fresh(REPO_ROOT))
```

- [ ] **Step 2: Run focused test and confirm RED**

```bat
py -3.12 -m unittest tooling.validation.test_flutter_bindings -v
```

Expected: import/function failure.

- [ ] **Step 3: Implement deterministic renderer**

Generated Dart must contain immutable descriptors for canonical ID, kind, registry key, symbol, variant map, state capability map, and density map. Sort canonical IDs and all nested map keys before rendering. Use LF newlines and one trailing newline.

Generated file header must say:

```dart
// GENERATED FILE. DO NOT EDIT.
// Source: design-contract/bindings/flutter/*.yaml
```

- [ ] **Step 4: Generate and check in Dart projection**

```bat
py -3.12 -m tooling.design_contract.generate_flutter_bindings --write
```

- [ ] **Step 5: Run projection tests and confirm GREEN**

```bat
py -3.12 -m unittest tooling.validation.test_flutter_bindings -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bat
git add tooling/design_contract/generate_flutter_bindings.py apps/prototype_app/lib/registry/generated_design_bindings.dart tooling/validation/test_flutter_bindings.py
git commit -m "feat: generate deterministic Flutter binding projection"
```

---

### Task 4: Repository/runtime parity validation

**Files:**
- Modify: `tooling/validation/validate_repo.py`
- Modify: `tooling/validation/test_runtime_bundle.py`
- Modify/Test: `tooling/validation/test_flutter_bindings.py`

**Interfaces:**
- Consumes: binding validator, current generated runtime bundles/directions, generated Dart freshness checker.
- Produces: repository validation that blocks stale/missing/invalid Flutter bindings before client review.

- [ ] **Step 1: Write failing repository validation tests**

Add tests proving:
- stale generated Dart projection fails;
- missing approved binding for a runtime pattern fails;
- unknown runtime component variant fails;
- invalid runtime density support fails;
- error ordering remains stable when YAML insertion order changes.

Example assertion:

```python
self.assertEqual(sorted(errors), errors)
```

- [ ] **Step 2: Run focused validation tests and confirm RED**

```bat
py -3.12 -m unittest tooling.validation.test_runtime_bundle tooling.validation.test_flutter_bindings -v
```

- [ ] **Step 3: Wire binding validation into `validate_repo.py`**

Repository validation must call both `validate_flutter_bindings(root)` and `check_flutter_bindings_fresh(root)`, and include binding paths/generated projection in required-path checks.

- [ ] **Step 4: Extend runtime bundle cross-checks**

For every checked generated runtime direction/bundle, invoke `runtime_binding_errors()` so canonical Design Contract existence alone is no longer enough; approved Flutter implementation parity is also required for the current prototype runtime.

- [ ] **Step 5: Run focused and repository validation**

```bat
py -3.12 -m unittest tooling.validation.test_runtime_bundle tooling.validation.test_flutter_bindings -v
py -3.12 tooling/validation/validate_repo.py
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bat
git add tooling/validation/validate_repo.py tooling/validation/test_runtime_bundle.py tooling/validation/test_flutter_bindings.py
git commit -m "feat: enforce Flutter binding parity in repository validation"
```

---

### Task 5: Flutter governed Design Contract resolver

**Files:**
- Create: `apps/prototype_app/lib/registry/design_contract_resolver.dart`
- Create: `apps/prototype_app/test/registry/design_contract_resolver_test.dart`
- Modify: `apps/prototype_app/lib/registry/prototype_registry.dart`

**Interfaces:**
- Consumes: `generatedDesignBindings` from generated Dart projection.
- Produces: `DesignContractResolver.patternKey(String canonicalId)`, `component(String canonicalId)`, `componentVariant(String canonicalId, String canonicalVariant)`, and `density(String canonicalId, String canonicalDensity)`.

- [ ] **Step 1: Write failing Flutter resolver tests**

Tests must cover:

```dart
test('canonical pattern resolves explicitly', () {
  expect(DesignContractResolver.patternKey('commerce.cart'), 'cart');
});

test('unknown canonical id is rejected', () {
  expect(
    () => DesignContractResolver.patternKey('commerce.missing'),
    throwsArgumentError,
  );
});

test('component variant resolves through generated binding', () {
  expect(
    DesignContractResolver.componentVariant('commerce.product-card', 'b2b'),
    'b2b',
  );
});
```

Also verify `compact`, `normal`, and `spacious` resolve explicitly for current component bindings.

- [ ] **Step 2: Run Flutter focused tests and confirm RED**

```bat
cd apps\prototype_app
flutter test test\registry\design_contract_resolver_test.dart
```

Expected: compile failure because resolver does not exist.

- [ ] **Step 3: Implement resolver without fallback**

Resolver looks up exact canonical IDs only. It may return generated implementation descriptors, but must never strip prefixes, guess registry keys, or choose a default for unknown IDs/variants/density.

- [ ] **Step 4: Replace prototype pattern resolution path**

Modify `PrototypeRegistry.labelFor()` and `buildPattern()` to call `DesignContractResolver.patternKey(canonicalPatternId)` before `PatternRegistry.resolve()`.

- [ ] **Step 5: Run focused Flutter tests**

```bat
flutter test test\registry\design_contract_resolver_test.dart
flutter test test\registry\prototype_registry_test.dart
```

If the second path does not exist, run the package's full test suite instead; do not invent a duplicate test file solely to satisfy this command.

- [ ] **Step 6: Commit**

```bat
git add apps/prototype_app/lib/registry/design_contract_resolver.dart apps/prototype_app/lib/registry/prototype_registry.dart apps/prototype_app/test/registry/design_contract_resolver_test.dart
git commit -m "feat: resolve Flutter UI through governed design bindings"
```

---

### Task 6: Variant and density parity at Flutter boundary

**Files:**
- Modify: `apps/prototype_app/lib/direction/prototype_direction.dart`
- Modify: `apps/prototype_app/lib/registry/design_contract_resolver.dart`
- Modify: `apps/prototype_app/lib/registry/prototype_registry.dart`
- Modify/Test: `apps/prototype_app/test/registry/design_contract_resolver_test.dart`
- Modify/Test: relevant direction/runtime tests under `apps/prototype_app/test/`

**Interfaces:**
- Consumes: canonical runtime density name and `component_variants` from `PrototypeDirection`.
- Produces: explicit canonical-density access and governed variant lookup usable by prototype rendering paths.

- [ ] **Step 1: Write failing canonical-density preservation test**

Require `PrototypeDirection` to retain both canonical density name and internal `AgencyDensity` mapping:

```dart
final direction = PrototypeDirection.fromMap(validDirectionMap(density: 'compact'));
expect(direction.canonicalDensity, 'compact');
expect(direction.density, AgencyDensity.dense);
```

- [ ] **Step 2: Write failing unsupported variant/density tests**

```dart
expect(
  () => DesignContractResolver.componentVariant('commerce.product-card', 'not-real'),
  throwsArgumentError,
);
expect(
  () => DesignContractResolver.density('commerce.product-card', 'not-real'),
  throwsArgumentError,
);
```

- [ ] **Step 3: Run focused tests and confirm RED**

```bat
cd apps\prototype_app
flutter test
```

- [ ] **Step 4: Preserve canonical density and enforce lookups**

Add `canonicalDensity` to `PrototypeDirection`; keep the existing explicit canonical-to-`AgencyDensity` mapping. Before component variants are consumed by any current prototype path, validate them through `DesignContractResolver.componentVariant()`. Where no dynamic component rendering exists yet, expose a pure helper used by tests/runtime validation rather than inventing new dynamic widget factories.

- [ ] **Step 5: Run Flutter package tests and confirm GREEN**

```bat
flutter test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bat
git add apps/prototype_app/lib/direction/prototype_direction.dart apps/prototype_app/lib/registry/design_contract_resolver.dart apps/prototype_app/lib/registry/prototype_registry.dart apps/prototype_app/test
git commit -m "feat: enforce design variant and density parity"
```

---

### Task 7: Remove hand-maintained canonical pattern mapping knowledge

**Files:**
- Delete: `apps/prototype_app/lib/registry/canonical_pattern_adapter.dart`
- Delete or replace: `apps/prototype_app/test/registry/canonical_pattern_adapter_test.dart`
- Modify: imports/references under `apps/prototype_app/`
- Modify/Test: `tooling/validation/test_runtime_bundle.py`

**Interfaces:**
- Consumes: generated binding projection + DesignContractResolver from Tasks 3 and 5.
- Produces: one authoritative mapping source (`design-contract/bindings/flutter/`) with no duplicate hand-maintained canonical pattern table.

- [ ] **Step 1: Add failing no-legacy-adapter regression assertion**

Python repository test should assert the old adapter path does not exist and runtime registry source does not contain heuristic conversion such as `replace('commerce.', '')`, substring stripping, or split-based canonical resolution.

- [ ] **Step 2: Delete adapter and migrate all references**

Remove the hand-authored Dart adapter only after the generated resolver tests prove complete current pattern coverage.

- [ ] **Step 3: Run Python and Flutter regression suites**

```bat
py -3.12 -m unittest tooling.validation.test_runtime_bundle tooling.validation.test_flutter_bindings -v
cd apps\prototype_app
flutter test
flutter analyze
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bat
git add -A apps/prototype_app tooling/validation/test_runtime_bundle.py
git commit -m "refactor: remove hand-maintained canonical pattern adapter"
```

---

### Task 8: Full verification, documentation, and CI integration

**Files:**
- Modify: `docs/client-runtime.md`
- Modify: `docs/prototype-platform.md`
- Modify: `docs/platform-status.md`
- Modify if needed: `.github/workflows/validate-structure.yml` or existing repository validation workflow only to execute existing validation entrypoints; do not duplicate validation logic in YAML.

**Interfaces:**
- Consumes: completed B.1D implementation.
- Produces: documented boundary, green repository validation, Flutter verification, and PR-ready branch.

- [ ] **Step 1: Update documentation**

Document:
- Design Contract is canonical authority;
- `design-contract/bindings/flutter/` is the governed implementation-binding catalog;
- generated Dart projection is checked, deterministic, and never manually edited;
- runtime bundles preserve canonical IDs;
- resolver performs exact lookup only;
- component variant/density parity is validated before client review;
- B.1E tokens/themes remain next milestone.

- [ ] **Step 2: Run full Python validation**

```bat
py -3.12 -m unittest discover tooling\validation -v
py -3.12 tooling\validation\validate_repo.py
```

Expected: all tests and repository validation PASS.

- [ ] **Step 3: Run knowledge/workflow/prototype validators**

Run the repository's existing validator commands exactly as documented by current CI/workflow files. Do not create duplicate validators. All must PASS.

- [ ] **Step 4: Run Flutter analyze/tests**

```bat
cd apps\prototype_app
flutter analyze
flutter test
cd ..\..\packages\agency_flutter_ui
flutter analyze
flutter test
cd ..\..\apps\widgetbook
flutter analyze
flutter test
```

Expected: all PASS with no analyze issues.

- [ ] **Step 5: Build Flutter Web**

```bat
cd ..\prototype_app
flutter build web
```

Expected: successful build.

- [ ] **Step 6: Check generated projection freshness after all edits**

```bat
cd ..\..
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
```

Expected: exit code 0 and no stale-output error.

- [ ] **Step 7: Commit docs/CI changes**

```bat
git add docs .github tooling apps packages design-contract
git commit -m "docs: document B.1D Flutter design contract alignment"
```

- [ ] **Step 8: Final whole-branch review**

Review the diff from `main...HEAD` specifically for:
- any canonical ID inference outside generated resolver;
- binding claims unsupported by actual Flutter code;
- missing current runtime pattern/component coverage;
- non-deterministic generation;
- stale checked generated file;
- accidental B.1E token/theme scope creep;
- runtime bundle schema changes.

Fix any findings, rerun affected tests, then rerun the full verification commands above.

- [ ] **Step 9: Push and open PR without merging**

PR title:

`Milestone B.1D: align Design Contract with Flutter implementations`

PR body must summarize authority boundary, binding catalog, deterministic Dart projection, variant/density validation, removal of hand-maintained adapter, and verification results. Do not merge until CI is green and review is complete.

---

## Plan Self-Review

### Spec coverage

- Canonical authority boundary: Tasks 1, 4, 5, 7.
- Machine-readable Flutter binding catalog: Tasks 1–2.
- Approved current runtime coverage: Tasks 2 and 4.
- Deterministic generated Dart projection: Task 3.
- Component variants/states/density parity: Tasks 1, 4, 6.
- Pattern registry target parity: Tasks 2, 5, 7.
- Stable validation error ordering: Tasks 1 and 4.
- No heuristic canonical-ID conversion: Tasks 5 and 7.
- Full Python/Flutter verification: Task 8.
- No B.1A/B.1B schema break and no B.1E scope: Global Constraints + Task 8 review.

### Placeholder scan

No `TBD`, `TODO`, deferred implementation placeholders, or unspecified "add tests" steps remain. Each implementation task contains explicit behaviors, commands, and test expectations.

### Type/interface consistency

`load_flutter_bindings`, `validate_flutter_bindings`, `runtime_binding_errors`, `render_flutter_bindings`, `write_flutter_bindings`, `check_flutter_bindings_fresh`, and `DesignContractResolver` method names are defined once and reused consistently across tasks.
