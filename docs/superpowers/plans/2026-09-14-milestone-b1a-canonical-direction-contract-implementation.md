# Milestone B.1A Canonical Direction Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish one canonical strategic direction contract, generate deterministic runtime direction projections, and make prototype composition support exactly 2–3 validated directions without manual contract reshaping.

**Architecture:** Strategic direction YAML remains the human/product-consulting source of truth. A deterministic Python adapter validates and projects each strategic direction into a compact runtime JSON contract, then prototype composition writes manifest and screenshot jobs from the actual available direction set. Flutter runtime loading of these generated files remains out of scope for B.1A and is the next milestone (B.1B).

**Tech Stack:** Python 3.12, PyYAML, jsonschema, unittest, JSON Schema Draft 2020-12, existing prototype tooling.

**Spec:** `docs/superpowers/specs/2026-09-14-milestone-b1a-canonical-direction-contract-design.md`

## Global Constraints

- Strategic YAML is canonical; runtime JSON is generated and disposable.
- Support exactly 2 or 3 directions: A and B required; C optional.
- Use `compact | normal | spacious` as the canonical density vocabulary.
- Runtime directions must preserve canonical pattern/component IDs and must never silently infer missing strategic content.
- Prototype composition must fail visibly for invalid schema, duplicate IDs, missing A/B, >3 directions, invalid projection, or manifest/runtime mismatch.
- No Flutter runtime loading changes in B.1A.
- No Design Contract token alignment, screenshot capture, production integrations, or unrelated documentation cleanup.
- Follow TDD: each production change is preceded by a failing test and an observed expected failure.

---

## File structure and responsibilities

### New files

- `tooling/knowledge/direction.schema.json` — canonical strategic direction JSON Schema.
- `tooling/prototype/runtime_direction.schema.json` — compact execution/runtime direction JSON Schema.
- `tooling/prototype/project_direction.py` — validates and deterministically projects one strategic direction into one runtime direction.

### Modified files

- `templates/direction.yaml` — canonical strategic authoring template aligned with the strategic schema.
- `tooling/prototype/validate_direction.py` — validate strategic directions against the canonical schema; keep the existing public function name for compatibility.
- `tooling/prototype/build_prototype.py` — discover A/B/(optional C), validate strategic directions, project runtime JSON, and generate manifest/screenshot configuration from actual directions.
- `tooling/workflow/router.py` — require A+B and treat C as optional where direction readiness is checked.
- `tooling/validation/test_prototype_platform.py` — contract/projection/composition tests.
- `tooling/validation/test_prototype_workflow_integration.py` — workflow cardinality and artifact-gate tests.
- `client-projects/examples/prototype-demo/directions/direction-a.yaml` — migrate to canonical strategic shape.
- `client-projects/examples/prototype-demo/directions/direction-b.yaml` — migrate to canonical strategic shape.
- `client-projects/examples/prototype-demo/directions/direction-c.yaml` — migrate to canonical strategic shape.
- `docs/prototype-platform.md` — document strategic vs generated-runtime contract boundary and 2–3 direction rule.

---

### Task 1: Canonical strategic direction schema and validator

**Files:**
- Create: `tooling/knowledge/direction.schema.json`
- Modify: `templates/direction.yaml`
- Modify: `tooling/prototype/validate_direction.py`
- Test: `tooling/validation/test_prototype_platform.py`

**Interfaces:**
- Consumes: strategic direction dictionaries loaded from YAML.
- Produces: `validate_direction(direction: dict) -> list[str]`, now validating the canonical strategic contract.
- Canonical density values: `compact`, `normal`, `spacious`.

- [ ] **Step 1: Replace the existing validator-focused fixtures in the test with a canonical strategic helper**

Add a helper shaped like:

```python
def valid_strategic_direction(direction_id: str) -> dict:
    return {
        "id": direction_id,
        "name": f"Direction {direction_id.upper()}",
        "archetype": "search-first",
        "strategy_family": "search",
        "thesis": "Reduce time from intent to transaction.",
        "strategic_goal": "reduce-order-time",
        "primary_personas": ["trade-buyer"],
        "primary_jobs": ["find-and-order-known-sku"],
        "rationale": "Known-SKU buyers benefit from direct search and dense decision support.",
        "information_architecture": ["home", "search", "plp", "pdp", "cart"],
        "navigation": {"model": "search-led"},
        "primary_journey": {"id": "search-to-order", "steps": ["search", "pdp", "cart", "checkout"]},
        "secondary_journeys": [{"id": "browse-to-order", "steps": ["home", "plp", "pdp", "cart"]}],
        "discovery_model": "sku-search",
        "search": {"prominence": "high"},
        "merchandising": {"emphasis": "availability-and-price"},
        "density": "compact",
        "transaction_model": "checkout-plus-rfq",
        "patterns": ["commerce.home", "commerce.search", "commerce.pdp"],
        "components": ["commerce.product-card", "commerce.price-display"],
        "component_variants": [{"component": "commerce.product-card", "variant": "b2b"}],
        "required_resources": [],
        "strengths": ["fast known-SKU ordering"],
        "tradeoffs": ["less editorial discovery"],
        "risks": ["depends on catalog data quality"],
        "success_metrics": ["time-to-cart"],
        "score": 0.9,
    }
```

Add tests:

```python
def test_strategic_direction_requires_canonical_fields(self):
    errors = validate_direction({"id": "a", "name": "A"})
    self.assertTrue(any("strategic_goal" in error for error in errors))
    self.assertTrue(any("primary_journey" in error for error in errors))


def test_strategic_direction_rejects_runtime_density_vocabulary(self):
    direction = valid_strategic_direction("a")
    direction["density"] = "balanced"
    errors = validate_direction(direction)
    self.assertTrue(any("density" in error for error in errors))


def test_canonical_strategic_direction_validates(self):
    self.assertEqual([], validate_direction(valid_strategic_direction("a")))
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
python -m unittest tooling.validation.test_prototype_platform.PrototypePlatformTests.test_strategic_direction_requires_canonical_fields tooling.validation.test_prototype_platform.PrototypePlatformTests.test_strategic_direction_rejects_runtime_density_vocabulary tooling.validation.test_prototype_platform.PrototypePlatformTests.test_canonical_strategic_direction_validates -v
```

Expected: at least the canonical-shape and density tests fail because the current schema expects the old prototype-specific contract.

- [ ] **Step 3: Create the canonical strategic schema**

Create `tooling/knowledge/direction.schema.json` with Draft 2020-12 and these exact required top-level fields:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": [
    "id", "name", "archetype", "strategy_family", "thesis", "strategic_goal",
    "primary_personas", "primary_jobs", "rationale", "information_architecture",
    "navigation", "primary_journey", "secondary_journeys", "discovery_model",
    "search", "merchandising", "density", "transaction_model", "patterns",
    "components", "component_variants", "required_resources", "strengths",
    "tradeoffs", "risks", "success_metrics", "score"
  ],
  "properties": {
    "id": {"type": "string", "minLength": 1},
    "name": {"type": "string", "minLength": 1},
    "archetype": {"type": "string", "minLength": 1},
    "strategy_family": {"type": "string", "minLength": 1},
    "thesis": {"type": "string", "minLength": 1},
    "strategic_goal": {"type": "string", "minLength": 1},
    "primary_personas": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "primary_jobs": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "rationale": {"type": "string", "minLength": 1},
    "information_architecture": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "navigation": {
      "type": "object",
      "required": ["model"],
      "properties": {"model": {"type": "string", "minLength": 1}},
      "additionalProperties": true
    },
    "primary_journey": {
      "type": "object",
      "required": ["id", "steps"],
      "properties": {
        "id": {"type": "string", "minLength": 1},
        "steps": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1}
      },
      "additionalProperties": true
    },
    "secondary_journeys": {"type": "array", "items": {"type": "object"}},
    "discovery_model": {"type": "string", "minLength": 1},
    "search": {"type": "object"},
    "merchandising": {
      "type": "object",
      "required": ["emphasis"],
      "properties": {"emphasis": {"type": "string", "minLength": 1}},
      "additionalProperties": true
    },
    "density": {"enum": ["compact", "normal", "spacious"]},
    "transaction_model": {"type": "string", "minLength": 1},
    "patterns": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "components": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "component_variants": {"type": "array", "items": {"type": "object"}},
    "required_resources": {"type": "array", "items": {"type": "string"}},
    "strengths": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "tradeoffs": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "risks": {"type": "array", "items": {"type": "string"}},
    "success_metrics": {"type": "array", "items": {"type": "string", "minLength": 1}, "minItems": 1},
    "score": {"type": "number"}
  },
  "additionalProperties": true
}
```

- [ ] **Step 4: Point `validate_direction.py` at the canonical schema**

Keep the existing public function name and return type. Load `tooling/knowledge/direction.schema.json` relative to repository root/module location and return stable human-readable error strings sorted by JSON path.

Minimum shape:

```python
from jsonschema import Draft202012Validator


def validate_direction(direction: dict) -> list[str]:
    validator = Draft202012Validator(_load_schema())
    errors = sorted(validator.iter_errors(direction), key=lambda error: list(error.path))
    return [f"{'.'.join(map(str, error.path)) or '<root>'}: {error.message}" for error in errors]
```

- [ ] **Step 5: Update `templates/direction.yaml` to match the canonical schema**

Use structured `navigation`, structured `primary_journey`, `tradeoffs`, explicit `patterns`/`components`, and canonical `density: normal`. Remove `weaknesses`.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run the exact command from Step 2.

Expected: all 3 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add tooling/knowledge/direction.schema.json templates/direction.yaml tooling/prototype/validate_direction.py tooling/validation/test_prototype_platform.py
git commit -m "feat: define canonical strategic direction contract"
```

---

### Task 2: Runtime direction schema and deterministic projection adapter

**Files:**
- Create: `tooling/prototype/runtime_direction.schema.json`
- Create: `tooling/prototype/project_direction.py`
- Modify: `tooling/validation/test_prototype_platform.py`

**Interfaces:**
- Consumes: one canonical strategic direction dictionary.
- Produces: `project_direction(direction: dict) -> dict`.
- Produces: `validate_runtime_direction(direction: dict) -> list[str]` in `project_direction.py`.

- [ ] **Step 1: Write failing adapter tests**

Add:

```python
from tooling.prototype.project_direction import project_direction, validate_runtime_direction


def test_direction_projection_is_deterministic(self):
    strategic = valid_strategic_direction("a")
    self.assertEqual(project_direction(strategic), project_direction(strategic))


def test_direction_projection_preserves_canonical_ids(self):
    runtime = project_direction(valid_strategic_direction("a"))
    self.assertEqual(["commerce.home", "commerce.search", "commerce.pdp"], runtime["patterns"])
    self.assertEqual(["commerce.product-card", "commerce.price-display"], runtime["components"])
    self.assertEqual("compact", runtime["density"])


def test_direction_projection_maps_structured_fields(self):
    runtime = project_direction(valid_strategic_direction("a"))
    self.assertEqual("search-led", runtime["navigation_model"])
    self.assertEqual("search-to-order", runtime["primary_journey"])
    self.assertEqual("availability-and-price", runtime["merchandising_model"])


def test_direction_projection_rejects_invalid_strategic_input(self):
    strategic = valid_strategic_direction("a")
    del strategic["navigation"]["model"]
    with self.assertRaisesRegex(ValueError, "navigation"):
        project_direction(strategic)
```

- [ ] **Step 2: Run tests and verify RED**

```bash
python -m unittest tooling.validation.test_prototype_platform.PrototypePlatformTests.test_direction_projection_is_deterministic tooling.validation.test_prototype_platform.PrototypePlatformTests.test_direction_projection_preserves_canonical_ids tooling.validation.test_prototype_platform.PrototypePlatformTests.test_direction_projection_maps_structured_fields tooling.validation.test_prototype_platform.PrototypePlatformTests.test_direction_projection_rejects_invalid_strategic_input -v
```

Expected: import/module failure because `project_direction.py` does not exist.

- [ ] **Step 3: Create `runtime_direction.schema.json`**

Required runtime fields:

```json
[
  "id", "name", "strategic_goal", "navigation_model", "primary_journey",
  "discovery_model", "merchandising_model", "density", "transaction_model",
  "patterns", "components", "component_variants", "required_resources"
]
```

Use `compact | normal | spacious` for runtime density too. Require non-empty scalar strings where applicable and arrays for IDs/variants/resources.

- [ ] **Step 4: Implement validation and projection**

Use the canonical strategic validator first; do not infer defaults.

Core implementation:

```python
def project_direction(direction: dict) -> dict:
    strategic_errors = validate_direction(direction)
    if strategic_errors:
        raise ValueError("invalid strategic direction: " + "; ".join(strategic_errors))

    runtime = {
        "id": direction["id"],
        "name": direction["name"],
        "strategic_goal": direction["strategic_goal"],
        "navigation_model": direction["navigation"]["model"],
        "primary_journey": direction["primary_journey"]["id"],
        "discovery_model": direction["discovery_model"],
        "merchandising_model": direction["merchandising"]["emphasis"],
        "density": direction["density"],
        "transaction_model": direction["transaction_model"],
        "patterns": list(direction["patterns"]),
        "components": list(direction["components"]),
        "component_variants": list(direction["component_variants"]),
        "required_resources": list(direction["required_resources"]),
    }

    runtime_errors = validate_runtime_direction(runtime)
    if runtime_errors:
        raise ValueError("invalid runtime direction: " + "; ".join(runtime_errors))
    return runtime
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: all 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add tooling/prototype/runtime_direction.schema.json tooling/prototype/project_direction.py tooling/validation/test_prototype_platform.py
git commit -m "feat: project strategic directions to runtime contract"
```

---

### Task 3: 2–3 direction discovery and prototype composer integration

**Files:**
- Modify: `tooling/prototype/build_prototype.py`
- Modify: `tooling/workflow/router.py`
- Modify: `tooling/validation/test_prototype_platform.py`
- Modify: `tooling/validation/test_prototype_workflow_integration.py`

**Interfaces:**
- Consumes: `directions/direction-a.yaml`, `direction-b.yaml`, optional `direction-c.yaml`.
- Produces: `prototype/runtime/direction-<id>.json` for each available strategic direction.
- Produces manifest direction mapping from actual generated runtime files.

- [ ] **Step 1: Add failing 2-direction, 3-direction, and invalid-cardinality tests**

Refactor the temporary-client setup into a focused helper if needed, but keep tests explicit.

Required assertions:

```python
manifest = yaml.safe_load(compose_prototype(root, client).read_text(encoding="utf-8"))
self.assertEqual(["a", "b"], list(manifest["directions"].keys()))
self.assertEqual(["a", "b"], manifest["review"]["allowed_values"])
self.assertTrue((client / "prototype" / "runtime" / "direction-a.json").exists())
self.assertTrue((client / "prototype" / "runtime" / "direction-b.json").exists())
self.assertFalse((client / "prototype" / "runtime" / "direction-c.json").exists())
```

Add a 3-direction test expecting A/B/C and a 1-direction test expecting `ValueError` containing `at least directions a and b`.

Add a >3 test by creating `direction-d.yaml` and expecting `ValueError` containing `at most 3 directions`.

- [ ] **Step 2: Run focused composition tests and verify RED**

```bash
python -m unittest tooling.validation.test_prototype_platform -v
```

Expected: new 2-direction/cardinality tests fail because composer currently hard-requires A/B/C and writes no runtime JSON.

- [ ] **Step 3: Implement available-direction discovery**

Add a helper in `build_prototype.py`:

```python
def _discover_direction_paths(client_dir: Path) -> list[tuple[str, Path]]:
    directions_dir = client_dir / "directions"
    found = []
    for path in sorted(directions_dir.glob("direction-*.yaml")):
        direction_key = path.stem.removeprefix("direction-")
        found.append((direction_key, path))

    keys = [key for key, _ in found]
    if "a" not in keys or "b" not in keys:
        raise ValueError("at least directions a and b are required")
    if len(found) > 3:
        raise ValueError("at most 3 directions are supported")
    if any(key not in {"a", "b", "c"} for key in keys):
        raise ValueError("only direction IDs a, b, and optional c are supported")
    return found
```

- [ ] **Step 4: Project and write runtime JSON during composition**

Create `prototype/runtime/`, call `project_direction()` for each strategic artifact, verify YAML file key matches `direction["id"]`, reject duplicate logical IDs, and write deterministic JSON:

```python
runtime_path.write_text(
    json.dumps(runtime_direction, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
```

Manifest direction mapping must become:

```python
directions[direction_key] = f"prototype/runtime/direction-{direction_key}.json"
```

Set:

```python
available_ids = list(directions.keys())
manifest["default_direction"] = available_ids[0]
manifest["review"]["allowed_values"] = available_ids
```

Pass `available_ids` into `build_screenshot_manifest()`.

- [ ] **Step 5: Update router readiness to A+B required, C optional**

Where the router checks direction files, require A and B and accept C only when present. Do not introduce general arbitrary direction IDs in this milestone.

- [ ] **Step 6: Run prototype + workflow integration tests and verify GREEN**

```bash
python -m unittest tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add tooling/prototype/build_prototype.py tooling/workflow/router.py tooling/validation/test_prototype_platform.py tooling/validation/test_prototype_workflow_integration.py
git commit -m "feat: compose prototypes from two or three directions"
```

---

### Task 4: Migrate reference prototype directions to the canonical strategic contract

**Files:**
- Modify: `client-projects/examples/prototype-demo/directions/direction-a.yaml`
- Modify: `client-projects/examples/prototype-demo/directions/direction-b.yaml`
- Modify: `client-projects/examples/prototype-demo/directions/direction-c.yaml`
- Modify: `tooling/validation/test_prototype_platform.py`

**Interfaces:**
- Consumes: canonical strategic schema from Task 1.
- Produces: executable regression example that requires no hand-authored runtime direction files.

- [ ] **Step 1: Add a failing repository-example test**

Add:

```python
def test_reference_example_directions_are_canonical(self):
    root = Path(__file__).resolve().parents[2]
    directions = root / "client-projects" / "examples" / "prototype-demo" / "directions"
    for direction_id in ("a", "b", "c"):
        data = yaml.safe_load((directions / f"direction-{direction_id}.yaml").read_text(encoding="utf-8"))
        self.assertEqual([], validate_direction(data), direction_id)
```

- [ ] **Step 2: Run the test and verify RED**

```bash
python -m unittest tooling.validation.test_prototype_platform.PrototypePlatformTests.test_reference_example_directions_are_canonical -v
```

Expected: FAIL because existing example directions use the old runtime-specific shape.

- [ ] **Step 3: Migrate all three example YAML files**

Preserve the intended differences among A/B/C, but express them using the canonical fields. Use namespaced pattern/component IDs where canonical IDs exist. Use structured navigation and primary journey. Replace old density values with `compact | normal | spacious`. Replace `weaknesses`/old trade-off representation with `tradeoffs`.

Do not create runtime JSON manually; composer must generate it.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Run composition against the reference example**

Run the existing prototype composer/validator command used by the repository. Then verify the generated manifest references `prototype/runtime/direction-a.json`, `direction-b.json`, and `direction-c.json`.

- [ ] **Step 6: Commit**

```bash
git add client-projects/examples/prototype-demo/directions tooling/validation/test_prototype_platform.py
git commit -m "test: migrate reference client to canonical directions"
```

---

### Task 5: Tighten prototype validation around generated runtime artifacts

**Files:**
- Modify: `tooling/prototype/validate_prototype.py`
- Modify: `tooling/validation/test_prototype_platform.py`

**Interfaces:**
- Consumes: prototype manifest and generated runtime JSON.
- Produces: repository validation errors for missing/mismatched runtime artifacts.

- [ ] **Step 1: Add failing validator tests for manifest/runtime mismatch**

Create a temporary valid prototype, then delete one generated runtime file and assert validator errors include that path. Add a second test that mutates manifest direction keys to disagree with generated runtime IDs and assert validation fails.

Example assertion:

```python
errors = validate_prototype_platform(root)
self.assertTrue(any("runtime" in error and "direction-b" in error for error in errors))
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
python -m unittest tooling.validation.test_prototype_platform -v
```

Expected: new mismatch tests fail because current validation is primarily existence-oriented and does not establish manifest/runtime parity.

- [ ] **Step 3: Extend prototype validation**

For each prototype manifest discovered by validator logic:

1. verify `directions` is a mapping with 2–3 entries;
2. verify keys are exactly a subset of `{a,b,c}` containing `a` and `b`;
3. resolve each manifest runtime path and require file existence;
4. parse each JSON object;
5. validate with `validate_runtime_direction()`;
6. require JSON `id` to match the manifest key;
7. require `review.allowed_values` to equal manifest direction keys in order;
8. require screenshot manifest directions to equal the same set.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tooling/prototype/validate_prototype.py tooling/validation/test_prototype_platform.py
git commit -m "test: validate runtime direction artifact parity"
```

---

### Task 6: Document the strategic/runtime boundary and run full verification

**Files:**
- Modify: `docs/prototype-platform.md`
- Modify only if required by validator installation checks: repository validation metadata/docs already used by the project.

**Interfaces:**
- Documents the stable contract that B.1B will consume.

- [ ] **Step 1: Update prototype platform documentation**

Document this exact flow:

```text
canonical strategic direction YAML
→ canonical strategic schema validation
→ project_direction.py
→ generated runtime direction JSON
→ prototype manifest
→ Flutter runtime (B.1B consumer)
```

Document A+B mandatory, C optional, and state that generated runtime JSON must never be hand-authored.

- [ ] **Step 2: Run the complete Python validation suite from `AGENTS.md`**

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

Expected: all commands exit 0.

- [ ] **Step 3: Run Flutter CI-equivalent checks for initialized packages/apps**

Use the same package discovery and commands as `.github/workflows/flutter.yml`; at minimum verify `flutter analyze`, relevant Flutter tests, and `flutter build web` for `apps/prototype_app` all exit 0.

- [ ] **Step 4: Check the branch diff for scope discipline**

```bash
git diff --stat main...HEAD
git diff --name-only main...HEAD
```

Expected: only B.1A spec/plan, strategic/runtime contract tooling, tests, reference directions, router/composer validation, and minimal prototype documentation are changed. No Flutter runtime client-loading implementation, token work, screenshot capture, or production integrations.

- [ ] **Step 5: Commit documentation**

```bash
git add docs/prototype-platform.md
git commit -m "docs: document strategic runtime direction boundary"
```

- [ ] **Step 6: Open a PR only after all verification is green**

PR title:

```text
Milestone B.1A: canonical direction contract and runtime projection
```

PR summary must explicitly state that Flutter consumption of generated runtime artifacts is deferred to B.1B.

---

## Self-review results

- **Spec coverage:** canonical strategic schema, runtime schema, deterministic adapter, canonical density, structured journey projection, 2–3 cardinality, composer integration, generated runtime artifacts, reference migration, visible failures, and regression validation are all mapped to tasks above.
- **Scope:** B.1A stops before Flutter runtime loading, Design Contract token work, visual capture, and productionization.
- **Type consistency:** `validate_direction(direction: dict) -> list[str]`, `project_direction(direction: dict) -> dict`, and `validate_runtime_direction(direction: dict) -> list[str]` are consistently named across tasks.
- **No placeholders:** implementation steps contain exact fields, interfaces, commands, and expected outcomes.
