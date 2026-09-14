# Milestone B.1B Client Runtime Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the single shared Flutter prototype app load generated client-specific runtime bundles for directions, fixtures, theme, and B.1C resource bindings instead of hard-coded demo configuration.

**Architecture:** Python tooling composes one deterministic JSON runtime bundle per client under `apps/prototype_app/assets/generated/`. Flutter loads the requested client from `?client=<id>`, validates the requested `?direction=<id>`, constructs a canonical runtime model, and renders only directions/resources declared by that client. Unknown client/direction values fail visibly; there is no silent fallback to Direction A.

**Tech Stack:** Python 3.12, JSON/YAML, Flutter 3.47.x, Dart 3.13.x, existing `agency_flutter_ui`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-15-milestone-b1b-client-runtime-loading-design.md`

## Global Constraints

- One shared Flutter prototype app; do not create one app per client.
- Flutter consumes generated JSON bundles, not repository YAML directly.
- Query contract is `?client=<client-id>&direction=<direction-id>`.
- A valid client has exactly 2 or 3 generated directions; A and B are mandatory, C optional.
- Unknown client and unknown direction must produce visible governed errors; never silently fall back to A.
- Flutter runtime direction fields must match the B.1A runtime contract: `id`, `name`, `strategic_goal`, `navigation_model`, `primary_journey`, `discovery_model`, `merchandising_model`, `density`, `transaction_model`, `patterns`, `components`, `component_variants`, `required_resources`.
- Supported density values are `compact`, `normal`, `spacious`.
- B.1C canonical resource bindings remain semantic IDs such as `asset.home.hero`, `icon.commerce.cart`, and `motion.checkout.success`.
- CI must remain deterministic and must not call external providers.
- Runtime generation is build-time; the Flutter prototype does not need network access to load client configuration.

---

## File Structure

### Create
- `tooling/prototype/build_runtime_bundle.py` — compose one client runtime JSON bundle.
- `tooling/prototype/validate_runtime_bundle.py` — validate bundle shape and semantic invariants.
- `tooling/validation/test_runtime_bundle.py` — Python TDD coverage for generated bundles.
- `apps/prototype_app/lib/runtime/prototype_runtime.dart` — typed client runtime model.
- `apps/prototype_app/lib/runtime/runtime_loader.dart` — load generated bundle through Flutter assets.
- `apps/prototype_app/lib/runtime/runtime_exception.dart` — governed runtime loading errors.
- `apps/prototype_app/lib/runtime/resource_binding.dart` — typed semantic resource binding.
- `apps/prototype_app/test/runtime/prototype_runtime_test.dart` — bundle parsing/model tests.
- `apps/prototype_app/test/runtime/runtime_loader_test.dart` — client/direction loading tests.
- `apps/prototype_app/assets/generated/prototype-demo.json` — generated regression bundle.

### Modify
- `tooling/prototype/build_prototype.py` — invoke runtime bundle generation after prototype artifacts are composed.
- `tooling/validation/validate_repo.py` — include B.1B generated bundle validation.
- `.github/workflows/validate.yml` — execute B.1B Python validation tests.
- `apps/prototype_app/pubspec.yaml` — declare `assets/generated/`.
- `apps/prototype_app/lib/direction/prototype_direction.dart` — align to canonical B.1A runtime vocabulary.
- `apps/prototype_app/lib/direction/direction_loader.dart` — remove hard-coded A/B/C defaults and resolve from `PrototypeRuntime`.
- `apps/prototype_app/lib/fixtures/demo_repository.dart` — replace static fixtures with runtime-backed repository/model conversion.
- `apps/prototype_app/lib/prototype_app.dart` — accept loaded runtime, client-aware direction selector, visible error state.
- `apps/prototype_app/lib/main.dart` — read `client` + `direction`, load bundle asynchronously, show governed loading/error states.
- Existing Flutter tests that assume fixed A/B/C or static demo data.

---

### Task 1: Runtime bundle contract and generator

**Files:**
- Create: `tooling/prototype/build_runtime_bundle.py`
- Create: `tooling/prototype/validate_runtime_bundle.py`
- Create: `tooling/validation/test_runtime_bundle.py`

**Interfaces:**
- Consumes: `client_dir/prototype/prototype-manifest.yaml`, referenced direction JSON files, fixture pack YAML, `manifest.theme`, optional `manifest.resources`.
- Produces: `build_runtime_bundle(root: Path, client_dir: Path, output_dir: Path) -> Path` and `validate_runtime_bundle(bundle: dict) -> list[str]`.

- [ ] **Step 1: Write failing Python tests for canonical bundle generation**

Test a reference client fixture and assert:

```python
bundle = json.loads(build_runtime_bundle(ROOT, client_dir, output_dir).read_text())
assert bundle["client_id"] == "prototype-demo"
assert bundle["default_direction"] == "a"
assert set(bundle["directions"]) == {"a", "b", "c"}
assert bundle["directions"]["a"]["navigation_model"] == "search-led"
assert bundle["directions"]["a"]["density"] == "compact"
assert "fixtures" in bundle
assert "theme" in bundle
assert "resources" in bundle
```

Also assert exactly 2 or 3 directions and A/B mandatory.

- [ ] **Step 2: Run the tests and confirm RED**

Run:

```bash
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
```

Expected: FAIL because generator/validator modules do not yet exist.

- [ ] **Step 3: Implement `validate_runtime_bundle`**

Validate:
- `version == 1`
- non-empty `client_id`
- `default_direction` exists in `directions`
- `directions` contains 2 or 3 entries
- `a` and `b` are present
- every direction key equals direction `id`
- required B.1A runtime fields exist
- density is one of `compact|normal|spacious`
- `review.allowed_directions` exactly matches direction keys
- resources is an object when present
- fixtures is an object/list structure generated from fixture pack

Return deterministic error strings instead of raising from the validator.

- [ ] **Step 4: Implement `build_runtime_bundle`**

Algorithm:
1. load `prototype-manifest.yaml`;
2. resolve each direction path relative to `client_dir`;
3. load direction JSON;
4. load fixture pack path from manifest;
5. copy `theme`, `resources`, and review metadata;
6. normalize review key to `allowed_directions`;
7. validate bundle;
8. raise `ValueError("invalid runtime bundle: ...")` if invalid;
9. write deterministic UTF-8 JSON with `indent=2`, `sort_keys=True` to `<output_dir>/<client_id>.json`.

- [ ] **Step 5: Run tests GREEN**

```bash
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tooling/prototype/build_runtime_bundle.py tooling/prototype/validate_runtime_bundle.py tooling/validation/test_runtime_bundle.py
git commit -m "feat: add client runtime bundle generator"
```

---

### Task 2: Integrate bundle generation into prototype composition

**Files:**
- Modify: `tooling/prototype/build_prototype.py`
- Modify: `tooling/validation/test_resource_integration.py` or add focused assertions to `test_runtime_bundle.py`
- Create/update: `apps/prototype_app/assets/generated/prototype-demo.json`

**Interfaces:**
- Consumes: `build_runtime_bundle(...)` from Task 1.
- Produces: generated app asset for every composed reference client.

- [ ] **Step 1: Add failing integration test**

Assert `compose_prototype(...)` also creates:

```text
apps/prototype_app/assets/generated/prototype-demo.json
```

and that B.1C resource bindings in the manifest appear unchanged under `bundle["resources"]`.

- [ ] **Step 2: Run test RED**

```bash
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
```

- [ ] **Step 3: Update `compose_prototype`**

After manifest/fixtures/runtime directions exist, call:

```python
build_runtime_bundle(
    root,
    client_dir,
    root / "apps" / "prototype_app" / "assets" / "generated",
)
```

Do not duplicate bundle construction logic in `build_prototype.py`.

- [ ] **Step 4: Regenerate `prototype-demo.json` and rerun tests**

Expected: PASS and generated bundle is deterministic across repeated runs.

- [ ] **Step 5: Commit**

```bash
git add tooling/prototype/build_prototype.py apps/prototype_app/assets/generated/prototype-demo.json tooling/validation/test_runtime_bundle.py
git commit -m "feat: generate Flutter client runtime assets"
```

---

### Task 3: Align Flutter direction model to B.1A runtime contract

**Files:**
- Modify: `apps/prototype_app/lib/direction/prototype_direction.dart`
- Test: `apps/prototype_app/test/runtime/prototype_runtime_test.dart`

**Interfaces:**
- Produces: `PrototypeDirection.fromMap(Map<String, dynamic>)` matching the canonical runtime contract.

- [ ] **Step 1: Write failing Dart tests**

Parse a canonical direction containing:

```dart
{
  'id': 'a',
  'name': 'Search-led Trade',
  'strategic_goal': 'reduce known-item order time',
  'navigation_model': 'search-led',
  'primary_journey': 'search-to-order',
  'discovery_model': 'sku-search',
  'merchandising_model': 'availability-and-price',
  'density': 'compact',
  'transaction_model': 'checkout-plus-rfq',
  'patterns': ['commerce.search'],
  'components': ['commerce.product-card'],
  'component_variants': [{'component': 'commerce.product-card', 'variant': 'b2b'}],
  'required_resources': ['asset.home.hero']
}
```

Assert all fields parse and `compact|normal|spacious` map into the existing UI density concept.

- [ ] **Step 2: Run Flutter test RED**

```bash
cd apps/prototype_app
flutter test test/runtime/prototype_runtime_test.dart
```

- [ ] **Step 3: Update `PrototypeDirection`**

Rename/remove legacy fields:
- `navigation` -> `navigationModel`
- `merchandising` -> `merchandisingModel`

Add:
- `List<ComponentVariant> componentVariants`
- `List<String> requiredResources`

Map canonical density:
- `compact` -> densest existing `AgencyDensity`
- `normal` -> balanced
- `spacious` -> airiest

Do not retain parsing aliases for old `dense|balanced|airy`; generated runtime is canonical after B.1A.

- [ ] **Step 4: Run test GREEN**

- [ ] **Step 5: Commit**

```bash
git add apps/prototype_app/lib/direction/prototype_direction.dart apps/prototype_app/test/runtime/prototype_runtime_test.dart
git commit -m "refactor: align Flutter direction runtime contract"
```

---

### Task 4: Add typed Flutter client runtime model

**Files:**
- Create: `apps/prototype_app/lib/runtime/prototype_runtime.dart`
- Create: `apps/prototype_app/lib/runtime/resource_binding.dart`
- Modify: `apps/prototype_app/test/runtime/prototype_runtime_test.dart`

**Interfaces:**
- Produces: `PrototypeRuntime.fromMap(Map<String, dynamic>)` with `clientId`, `defaultDirection`, `directions`, `fixtures`, `theme`, `resources`, `allowedDirections`.
- Produces: `ResourceBinding.fromMap(String id, Map<String, dynamic>)`.

- [ ] **Step 1: Add failing parsing tests for full generated bundle**

Assert:
- exact client ID
- two/three directions accepted
- default direction must exist
- resources keyed by canonical semantic ID
- allowed direction list matches declared directions
- invalid bundle throws `FormatException`.

- [ ] **Step 2: Run RED**

- [ ] **Step 3: Implement minimal typed runtime models**

Keep fixture payload generic initially as `Map<String, dynamic>` so B.1B does not invent a second fixture schema. Convert into UI-specific fixture objects at repository boundary in Task 6.

- [ ] **Step 4: Run GREEN**

- [ ] **Step 5: Commit**

```bash
git add apps/prototype_app/lib/runtime apps/prototype_app/test/runtime/prototype_runtime_test.dart
git commit -m "feat: add typed Flutter client runtime model"
```

---

### Task 5: Implement Flutter asset loader and governed errors

**Files:**
- Create: `apps/prototype_app/lib/runtime/runtime_exception.dart`
- Create: `apps/prototype_app/lib/runtime/runtime_loader.dart`
- Create: `apps/prototype_app/test/runtime/runtime_loader_test.dart`
- Modify: `apps/prototype_app/pubspec.yaml`

**Interfaces:**
- Produces: `Future<PrototypeRuntime> RuntimeLoader.loadClient(String clientId, {AssetBundle? bundle})`.
- Produces: error codes `client_not_found`, `invalid_bundle`, `direction_not_found` through `RuntimeException`.

- [ ] **Step 1: Write failing loader tests with an injected `AssetBundle`**

Cases:
1. valid `prototype-demo` loads;
2. unknown client throws `RuntimeException(code: 'client_not_found')`;
3. malformed JSON throws `invalid_bundle`;
4. path is always `assets/generated/<client-id>.json` after validating client ID contains only `[A-Za-z0-9._-]`.

- [ ] **Step 2: Run RED**

- [ ] **Step 3: Add Flutter asset declaration**

In `pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/generated/
```

- [ ] **Step 4: Implement runtime loader**

Use `rootBundle.loadString` by default and injected `AssetBundle` in tests. Decode JSON, ensure root object, then call `PrototypeRuntime.fromMap`.

- [ ] **Step 5: Run GREEN**

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/runtime/runtime_exception.dart apps/prototype_app/lib/runtime/runtime_loader.dart apps/prototype_app/test/runtime/runtime_loader_test.dart apps/prototype_app/pubspec.yaml
git commit -m "feat: load client runtime bundles in Flutter"
```

---

### Task 6: Replace hard-coded direction and fixture repositories

**Files:**
- Modify: `apps/prototype_app/lib/direction/direction_loader.dart`
- Modify: `apps/prototype_app/lib/fixtures/demo_repository.dart`
- Modify/add tests under `apps/prototype_app/test/`

**Interfaces:**
- `DirectionLoader.resolve(PrototypeRuntime runtime, String id) -> PrototypeDirection` and throws `RuntimeException(code: 'direction_not_found')`.
- Runtime fixture repository reads products/services from `runtime.fixtures`.

- [ ] **Step 1: Write failing tests**

Assert:
- Direction C is absent when runtime contains only A+B;
- `resolve(runtime, 'z')` throws instead of falling back to A;
- product names/prices come from runtime fixture payload, not hard-coded Dart constants.

- [ ] **Step 2: Run RED**

- [ ] **Step 3: Remove `DirectionLoader.defaults()` hard-coded A/B/C**

Loader becomes a thin runtime lookup only.

- [ ] **Step 4: Refactor fixture repository to runtime-backed data**

Preserve conversions into existing `AgencyProduct` objects so screens do not need to know raw JSON/YAML fixture shapes.

- [ ] **Step 5: Run GREEN**

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/direction/direction_loader.dart apps/prototype_app/lib/fixtures/demo_repository.dart apps/prototype_app/test
git commit -m "refactor: remove hard-coded prototype client data"
```

---

### Task 7: Wire `client` and `direction` into the Flutter application

**Files:**
- Modify: `apps/prototype_app/lib/main.dart`
- Modify: `apps/prototype_app/lib/prototype_app.dart`
- Modify/add widget tests.

**Interfaces:**
- `PrototypeApp` receives a loaded `PrototypeRuntime` and requested direction ID.
- Main entry reads `Uri.base.queryParameters['client']` and `['direction']`.

- [ ] **Step 1: Write failing widget tests**

Cases:
- A+B runtime renders only A and B selector segments;
- A+B+C renders all three;
- selected direction title/strategic goal changes correctly;
- unknown direction renders governed error UI, not Direction A;
- runtime error UI includes client ID and short actionable message without stack trace.

- [ ] **Step 2: Run RED**

- [ ] **Step 3: Update `PrototypeApp`**

Replace fixed segment list with:

```dart
runtime.allowedDirections.map((id) => ButtonSegment(value: id, label: Text(id.toUpperCase())))
```

Resolve the current direction from runtime. Keep selection state local to the prototype review session.

- [ ] **Step 4: Update `main.dart`**

Rules:
- client query parameter is required for client-specific review; for local convenience only, use the generated regression client `prototype-demo` when the parameter is omitted;
- direction parameter defaults to that runtime's `default_direction` only when omitted;
- an explicitly supplied unknown direction is an error.

Show a small loading view while bundle loads and a governed error screen on `RuntimeException`.

- [ ] **Step 5: Run widget tests GREEN**

- [ ] **Step 6: Commit**

```bash
git add apps/prototype_app/lib/main.dart apps/prototype_app/lib/prototype_app.dart apps/prototype_app/test
git commit -m "feat: route client and direction through runtime"
```

---

### Task 8: Verify B.1C resource bindings survive into Flutter runtime

**Files:**
- Modify: `apps/prototype_app/test/runtime/prototype_runtime_test.dart`
- Modify: `tooling/validation/test_runtime_bundle.py`

**Interfaces:**
- B.1C resources remain available as `runtime.resources['asset.home.hero']`, etc.

- [ ] **Step 1: Add Python and Dart tests**

Assert canonical ID, candidate/source/type/asset descriptor survive generation and parsing without provider-specific field renaming.

- [ ] **Step 2: Run RED if any boundary drops fields**

- [ ] **Step 3: Make only the minimal model/generator changes needed**

Do not implement image rendering in this task; B.1B guarantees runtime availability only.

- [ ] **Step 4: Run GREEN**

- [ ] **Step 5: Commit**

```bash
git add tooling/validation/test_runtime_bundle.py apps/prototype_app/test/runtime/prototype_runtime_test.dart apps/prototype_app/lib/runtime
git commit -m "test: preserve resource bindings through client runtime"
```

---

### Task 9: Repository validation and CI integration

**Files:**
- Modify: `tooling/validation/validate_repo.py`
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- Repository validation rejects missing/stale/invalid generated client bundles.

- [ ] **Step 1: Write failing repo validation test/assertion**

Validate every checked reference client whose prototype manifest exists has a corresponding generated bundle and the bundle passes `validate_runtime_bundle`.

- [ ] **Step 2: Run RED**

- [ ] **Step 3: Extend repository validation**

Keep live provider/API calls out of CI.

- [ ] **Step 4: Update workflow if needed so `test_runtime_bundle` runs explicitly**

- [ ] **Step 5: Run local Python verification**

```bash
py -3.12 -m unittest discover tooling/validation -v
py -3.12 tooling/validation/validate_repo.py
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add tooling/validation/validate_repo.py .github/workflows/validate.yml
git commit -m "ci: validate generated client runtime bundles"
```

---

### Task 10: Full Flutter verification and regression coverage

**Files:**
- Modify tests only if failures expose contract gaps.

- [ ] **Step 1: Run Flutter analyze**

```bash
cd apps/prototype_app
flutter analyze
```

Expected: no issues.

- [ ] **Step 2: Run prototype app tests**

```bash
flutter test
```

Expected: PASS.

- [ ] **Step 3: Verify shared UI package**

```bash
cd ../../packages/agency_flutter_ui
flutter test
```

Expected: PASS.

- [ ] **Step 4: Build Flutter Web**

```bash
cd ../../apps/prototype_app
flutter build web
```

Expected: successful web build.

- [ ] **Step 5: Manually verify review URLs locally**

Check:

```text
?client=prototype-demo&direction=a
?client=prototype-demo&direction=b
?client=prototype-demo&direction=c
```

and invalid cases:

```text
?client=does-not-exist&direction=a
?client=prototype-demo&direction=z
```

Expected: valid URLs render selected direction; invalid URLs display governed error UI.

- [ ] **Step 6: Commit any test-only corrections**

---

### Task 11: Documentation and status update

**Files:**
- Create/update: `docs/client-runtime.md`
- Modify: `docs/platform-status.md`
- Modify: `workflows/05-build-prototype.md` if runtime bundle output is not already explicit.

**Interfaces:**
- Documents how OpenCode generates and reviews a client runtime.

- [ ] **Step 1: Document runtime generation**

Include:

```text
client artifacts
→ build_prototype.py
→ prototype-manifest.yaml
→ build_runtime_bundle.py
→ apps/prototype_app/assets/generated/<client>.json
→ Flutter RuntimeLoader
→ ?client=<id>&direction=<id>
```

- [ ] **Step 2: Document error behavior and boundaries**

State that unknown explicit client/direction values never silently fall back.

- [ ] **Step 3: Mark B.1B implemented in platform status only after all verification passes**

- [ ] **Step 4: Commit**

```bash
git add docs/client-runtime.md docs/platform-status.md workflows/05-build-prototype.md
git commit -m "docs: document B.1B client runtime loading"
```

---

### Task 12: Final review and PR

- [ ] **Step 1: Run complete repository validation from repo root**

```bash
py -3.12 -m unittest discover tooling/validation -v
py -3.12 tooling/validation/validate_repo.py
```

- [ ] **Step 2: Run Flutter CI-equivalent commands**

```bash
cd apps/prototype_app
flutter analyze
flutter test
flutter build web
```

Run tests for `packages/agency_flutter_ui` and `apps/widgetbook` if the repository CI currently exercises them.

- [ ] **Step 3: Review diff against B.1B spec**

Check explicitly:
- no hard-coded client directions remain in `DirectionLoader`;
- no silent unknown-direction fallback;
- generated bundles contain canonical B.1A vocabulary;
- B.1C resources survive runtime bundle generation;
- selector supports exactly the client's declared 2–3 directions;
- CI has no network dependency.

- [ ] **Step 4: Open PR**

Title:

```text
Milestone B.1B: client runtime loading
```

PR body should summarize runtime bundle boundary, Flutter loading, governed errors, fixture/theme/resource loading, and verification evidence.

- [ ] **Step 5: Wait for Repository Validation and Flutter CI to succeed before merge readiness**
