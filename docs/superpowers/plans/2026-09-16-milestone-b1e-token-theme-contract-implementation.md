# Milestone B.1E — Token + Theme Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a governed, deterministic token/theme compiler that resolves agency foundation tokens, semantic defaults, approved theme presets, client brand inputs, and direction overrides into a fully resolved runtime theme consumed by Flutter.

**Architecture:** `design-contract/` remains canonical. Python tooling validates and resolves all token/theme layers using one explicit precedence order, B.1B runtime bundles carry resolved values only, and Flutter maps those values into Material `ThemeData` plus an `AgencyThemeTokens` `ThemeExtension`. Active prototype styling is migrated only where B.1E semantics are high-value; no widget invents brand/theme decisions independently.

**Tech Stack:** Python 3.12, PyYAML, JSON/YAML schemas and repository validators, Flutter/Dart, Material 3 `ThemeData`, `ThemeExtension`, existing B.1B runtime bundle tooling, existing B.1D Design Contract validation/generation conventions.

**Spec:** `docs/superpowers/specs/2026-09-16-milestone-b1e-token-theme-contract-design.md`

## Global Constraints

- `design-contract/` is the canonical visual contract authority.
- Resolution precedence is exactly: foundation < semantic defaults < theme preset < client brand overrides < direction overrides.
- Runtime bundles contain fully resolved values only; no unresolved token references or inheritance rules.
- Canonical direction density remains exactly `compact | normal | spacious`.
- Client inputs may override approved semantic paths only; widget-specific implementation keys are invalid.
- Generated/checked artifacts use deterministic key ordering, UTF-8, LF, and one trailing newline.
- Flutter must not silently fall back to the old seed-color theme for a valid B.1E runtime bundle.
- External fonts are not downloaded dynamically at runtime; unavailable fonts require an explicit approved fallback or governed failure.
- B.1D canonical component/pattern binding authority remains unchanged.
- Nowa is not a source of truth; retained changes must exist as normal Flutter/configuration code in GitHub.
- B.1E does not implement Review Mode, BugDrop, screenshot automation, Visual AI QA, or a general animation engine.

---

## File Structure

### New governed contract files

- `design-contract/schema/foundation-tokens.schema.json` — validates raw foundation scale structure and primitive value types.
- `design-contract/schema/semantic-tokens.schema.json` — validates required semantic token groups and reference/value syntax.
- `design-contract/schema/theme-preset.schema.json` — validates approved reusable theme presets and allowed semantic override shape.
- `design-contract/tokens/foundation.yaml` — agency-wide foundation scales.
- `design-contract/tokens/semantic.yaml` — canonical semantic defaults referencing foundation values.
- `design-contract/themes/premium-modern.yaml` — approved spacious/premium preset.
- `design-contract/themes/compact-commerce.yaml` — approved compact commerce preset.
- `design-contract/themes/editorial-commerce.yaml` — approved discovery/editorial preset.

### New Python tooling

- `tooling/design_contract/theme_contract.py` — loaders, schema validation, reference resolution, cycle detection, override validation, compiler, deterministic errors.
- `tooling/design_contract/generate_resolved_themes.py` — CLI/freshness helper for deterministic resolved theme output used by client runtime generation.
- `tooling/validation/test_theme_contract.py` — focused contract/compiler tests.

### Existing Python/runtime files to modify

- `tooling/prototype/build_runtime_bundle.py` — compile the theme instead of copying manifest theme data verbatim.
- `tooling/prototype/validate_runtime_bundle.py` — validate versioned resolved theme shape and parity with a fresh compile.
- `tooling/validation/test_runtime_bundle.py` — theme composition/parity tests.
- `tooling/validation/validate_repo.py` — invoke theme-contract validation and freshness/parity checks.
- `tooling/validation/test_validate_repo.py` — prove repository validation rejects stale/invalid themes.
- current client input/direction schemas and fixtures under `client-projects/` — add only the governed preset/brand/direction theme fields required by current reference clients.

### Flutter files to create/modify

- `packages/agency_flutter_ui/lib/themes/agency_theme_tokens.dart` — `ThemeExtension` for agency-specific semantic spacing/radius/sizing/density/motion/breakpoints.
- `packages/agency_flutter_ui/lib/themes/agency_theme.dart` — construct `ThemeData` from resolved runtime values instead of primarily from `seedColor`.
- `packages/agency_flutter_ui/test/agency_theme_test.dart` — ThemeData + extension tests.
- `apps/prototype_app/lib/runtime/runtime_theme.dart` — typed parser/validation for resolved runtime theme.
- runtime bundle model/loader file already responsible for parsing generated JSON — attach typed `RuntimeTheme` without adding independent defaults.
- `apps/prototype_app/test/` runtime/theme tests — malformed/missing theme failures and density parity.
- targeted shared components/pattern files in `packages/agency_flutter_ui/lib/` — replace major repeated hard-coded colors/spacing/radii/control sizing with semantic theme reads.

---

### Task 1: Govern foundation and semantic token contracts

**Files:**
- Create: `design-contract/schema/foundation-tokens.schema.json`
- Create: `design-contract/schema/semantic-tokens.schema.json`
- Create: `design-contract/tokens/foundation.yaml`
- Create: `design-contract/tokens/semantic.yaml`
- Create: `tooling/design_contract/theme_contract.py`
- Create: `tooling/validation/test_theme_contract.py`

**Interfaces:**
- Produces: `load_foundation_tokens(root: Path) -> dict`, `load_semantic_tokens(root: Path) -> dict`, `validate_token_catalogs(root: Path) -> list[str]`.
- Produces canonical reference syntax `{foundation.<path>}` and semantic groups `color`, `typography`, `spacing`, `radius`, `elevation`, `size`, `density`, `motion`, `breakpoints`.

- [ ] **Step 1: Write failing loader/schema tests**

Add tests proving valid catalogs load and malformed top-level groups, bad colors, non-finite/negative dimensions where prohibited, and unknown keys produce deterministic errors.

```python
class ThemeContractTests(unittest.TestCase):
    def test_valid_foundation_and_semantic_catalogs_load(self):
        foundation = load_foundation_tokens(ROOT)
        semantic = load_semantic_tokens(ROOT)
        self.assertEqual(foundation["version"], 1)
        self.assertIn("color", semantic)
        self.assertEqual(validate_token_catalogs(ROOT), [])

    def test_validation_errors_are_sorted(self):
        errors = validate_token_catalogs(self.fixture_root("multiple-errors"))
        self.assertEqual(errors, sorted(errors))
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:
`py -3.12 -m unittest tooling.validation.test_theme_contract -v`

Expected: import/file-not-found failures for the new contract APIs/files.

- [ ] **Step 3: Add schemas and minimal governed catalogs**

Seed foundation scales for color, type size/weight/line-height, spacing, radius, elevation, size/control height, density multiplier metadata, motion durations, and breakpoints. Seed semantic defaults for required surface/text/control/layout meanings. Do not add client-specific values.

- [ ] **Step 4: Implement loaders and deterministic structural validation**

Use explicit root paths, `yaml.safe_load`, governed `ValueError` conversion, finite numeric checks, `#RRGGBB`/`#AARRGGBB` validation, and lexicographically sorted returned errors. Do not resolve references yet.

- [ ] **Step 5: Run focused tests and confirm GREEN**

Run:
`py -3.12 -m unittest tooling.validation.test_theme_contract -v`

Expected: Task 1 tests pass.

- [ ] **Step 6: Commit**

```bash
git add design-contract/schema design-contract/tokens tooling/design_contract/theme_contract.py tooling/validation/test_theme_contract.py
git commit -m "feat: govern foundation and semantic theme tokens"
```

---

### Task 2: Add approved theme presets and deterministic reference resolution

**Files:**
- Create: `design-contract/schema/theme-preset.schema.json`
- Create: `design-contract/themes/premium-modern.yaml`
- Create: `design-contract/themes/compact-commerce.yaml`
- Create: `design-contract/themes/editorial-commerce.yaml`
- Modify: `tooling/design_contract/theme_contract.py`
- Modify: `tooling/validation/test_theme_contract.py`

**Interfaces:**
- Produces: `load_theme_presets(root: Path) -> dict[str, dict]`.
- Produces: `resolve_theme(root: Path, preset_id: str, client_brand: dict | None, direction_overrides: dict | None) -> dict`.
- Resolved return value contains `version: 1` plus all nine semantic groups and zero `{foundation...}` strings.

- [ ] **Step 1: Write failing reference/preset tests**

Cover valid nested references, unknown references, reference cycles, unknown/unapproved preset IDs, and deterministic output independent of YAML mapping insertion order.

```python
def test_resolution_precedence_and_reference_elimination(self):
    theme = resolve_theme(ROOT, "premium-modern", {"primary_color": "#1155CC"}, None)
    self.assertEqual(theme["color"]["primary"], "#1155CC")
    self.assertFalse(any("{foundation." in value for value in walk_strings(theme)))
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:
`py -3.12 -m unittest tooling.validation.test_theme_contract -v`

Expected: missing resolver/preset APIs.

- [ ] **Step 3: Implement reference resolver with cycle detection**

Resolve only complete-token reference strings such as `{foundation.spacing.4}`. Track DFS visiting paths and return a governed error like `cyclic token reference: foundation.a -> foundation.b -> foundation.a`. Unknown references fail; interpolation inside arbitrary strings is out of scope.

- [ ] **Step 4: Implement preset loading and approved semantic override validation**

Presets contain `id`, `status`, and `semantic_overrides`; only `status: approved` is consumable by current runtime clients. Reject widget/component implementation paths.

- [ ] **Step 5: Implement deterministic deep merge and compile base + preset**

Deep merge dictionaries only. Type-changing overrides are invalid. Stable ordering is applied at serialization boundaries, while error ordering is sorted before return/raise.

- [ ] **Step 6: Run tests and commit**

Run:
`py -3.12 -m unittest tooling.validation.test_theme_contract -v`

Then:
```bash
git add design-contract/schema/theme-preset.schema.json design-contract/themes tooling/design_contract/theme_contract.py tooling/validation/test_theme_contract.py
git commit -m "feat: compile approved semantic theme presets"
```

---

### Task 3: Govern client brand and direction theme overrides

**Files:**
- Modify: current canonical client-input schema/validation file used by `tooling/validation/test_client_input_contract.py`
- Modify: current canonical direction schema/validation path used by runtime direction projection
- Modify: `tooling/design_contract/theme_contract.py`
- Modify: `tooling/validation/test_client_input_contract.py`
- Modify: `tooling/validation/test_theme_contract.py`
- Modify: current reference client input/direction fixtures only as required

**Interfaces:**
- Consumes: `resolve_theme(...)` from Task 2.
- Produces: `brand_to_semantic_overrides(brand: dict) -> dict`.
- Produces: `validate_direction_theme_overrides(overrides: object) -> list[str]`.
- Allowed brand fields initially: `primary_color`, `secondary_color`, `font_family`, `font_fallback`, `visual_character` when present in the canonical client contract.
- Direction theme overrides may target only explicitly allowlisted semantic paths and must preserve canonical density values.

- [ ] **Step 1: Write failing precedence and allowlist tests**

Prove exact precedence:
foundation/defaults < preset < client brand < direction override.

Also reject examples such as `ProductCard.padding`, `widgets.search.radius`, unknown semantic paths, and density values outside `compact|normal|spacious`.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:
`py -3.12 -m unittest tooling.validation.test_theme_contract tooling.validation.test_client_input_contract -v`

- [ ] **Step 3: Extend existing client contract minimally**

Add governed visual fields without replacing the existing input schema. Keep raw client brand facts in `input/`; derived theme compilation remains tooling-owned.

- [ ] **Step 4: Implement explicit brand mapping**

Example mapping:

```python
BRAND_OVERRIDE_MAP = {
    "primary_color": ("color", "primary"),
    "secondary_color": ("color", "secondary"),
    "font_family": ("typography", "font_family"),
    "font_fallback": ("typography", "font_fallback"),
}
```

Do not convert arbitrary client keys to semantic paths heuristically.

- [ ] **Step 5: Implement direction override allowlist and density preservation**

Allow only B.1E semantic presentation fields such as approved spacing/radius/density/typography emphasis/control sizing entries. Direction structure/navigation/component IDs stay governed by B.1A/B.1D.

- [ ] **Step 6: Run focused tests and commit**

```bash
py -3.12 -m unittest tooling.validation.test_theme_contract tooling.validation.test_client_input_contract -v
git add tooling client-projects design-contract
git commit -m "feat: govern client and direction theme overrides"
```

---

### Task 4: Integrate deterministic resolved themes into B.1B runtime bundles

**Files:**
- Create: `tooling/design_contract/generate_resolved_themes.py`
- Modify: `tooling/prototype/build_runtime_bundle.py`
- Modify: `tooling/prototype/validate_runtime_bundle.py`
- Modify: `tooling/validation/test_runtime_bundle.py`
- Modify: generated runtime JSON under `apps/prototype_app/assets/generated/` via the existing generator, not by hand

**Interfaces:**
- Consumes: `resolve_theme(...)`.
- Runtime `theme` becomes a required fully resolved object containing `version` and all required semantic groups.
- Produces CLI modes to write/check generated resolved bundle themes using existing client discovery/build conventions.

- [ ] **Step 1: Write failing runtime bundle tests**

Assert that `compose_runtime_bundle()` resolves a theme from current client manifest/input/direction data rather than copying `manifest["theme"]`, that no unresolved reference survives, and that two fresh builds are byte-identical.

- [ ] **Step 2: Run focused runtime tests and confirm RED**

Run:
`py -3.12 -m unittest tooling.validation.test_runtime_bundle -v`

- [ ] **Step 3: Wire theme compilation into runtime composition**

For each current client/direction context, derive the approved preset + client brand + applicable direction overrides, compile once, and place the resolved object under runtime `theme`. If runtime architecture requires per-direction visual differences, store resolved theme by direction in the smallest backward-compatible structure accepted by the existing bundle model; do not duplicate unrelated runtime data.

- [ ] **Step 4: Add runtime theme structural validation**

Require all nine groups, `version == 1`, valid resolved primitive types, canonical density, finite numeric values, and zero unresolved reference strings.

- [ ] **Step 5: Add fresh-compile parity validation**

Repository validation must compare the checked/generated bundle theme semantically and deterministically to `resolve_theme()` using the source client inputs. A stale checked JSON file must fail.

- [ ] **Step 6: Generate current bundles, run tests, commit**

Run existing runtime generation command(s) used by B.1B, then:

```bash
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
git add tooling/design_contract tooling/prototype tooling/validation apps/prototype_app/assets/generated client-projects
git commit -m "feat: compile resolved themes into runtime bundles"
```

---

### Task 5: Parse resolved runtime theme in Flutter and build ThemeData + ThemeExtension

**Files:**
- Create: `apps/prototype_app/lib/runtime/runtime_theme.dart`
- Modify: existing runtime bundle model/loader in `apps/prototype_app/lib/runtime/`
- Create: `packages/agency_flutter_ui/lib/themes/agency_theme_tokens.dart`
- Modify: `packages/agency_flutter_ui/lib/themes/agency_theme.dart`
- Create/Modify: `packages/agency_flutter_ui/test/agency_theme_test.dart`
- Create/Modify: prototype runtime theme tests under `apps/prototype_app/test/`

**Interfaces:**
- Produces typed `RuntimeTheme.fromJson(Map<String, Object?> json)` with governed `FormatException`/existing runtime error style.
- Produces `AgencyTheme.light(RuntimeThemeData resolved)` or an equivalent explicit typed input; valid B.1E clients must not use `seedColor` as design authority.
- Produces `AgencyThemeTokens extends ThemeExtension<AgencyThemeTokens>` with at least `sectionSpacing`, `cardSpacing`, `tileGap`, `controlRadius`, `cardRadius`, `compactControlHeight`, `motionFast`, `motionNormal`, breakpoint semantics, and canonical density.

- [ ] **Step 1: Write failing parser/theme tests**

Test resolved color conversion, typography mapping, extension availability, all three density values, missing required fields, malformed colors/numbers, and absence of valid-bundle seed fallback.

- [ ] **Step 2: Run Flutter tests and confirm RED**

Run from the affected packages:

```bash
flutter test packages/agency_flutter_ui/test/agency_theme_test.dart
flutter test apps/prototype_app/test
```

Use repository-standard package working directories if root invocation is unsupported.

- [ ] **Step 3: Implement typed runtime parser**

Parse exact required fields; reject unknown structural type mismatches. Do not silently insert design defaults that belong to the Python compiler.

- [ ] **Step 4: Implement `AgencyThemeTokens`**

Implement immutable fields, `copyWith`, `lerp`, and a convenient `of(BuildContext context)` accessor that fails clearly when the extension is absent in governed prototype contexts.

- [ ] **Step 5: Rework `AgencyTheme` to consume resolved values**

Map semantic colors to `ColorScheme`, type scale/family to `TextTheme`, surfaces to scaffold/card/input/button themes, and attach `AgencyThemeTokens` in `ThemeData.extensions`.

- [ ] **Step 6: Run Flutter tests and commit**

```bash
flutter test
flutter analyze
git add apps/prototype_app packages/agency_flutter_ui
git commit -m "feat: consume resolved semantic themes in Flutter"
```

---

### Task 6: Migrate high-value active styling surfaces to semantic tokens

**Files:**
- Modify: active card/product/list/detail/search/trade widgets in `packages/agency_flutter_ui/lib/` identified by repository scan for duplicated spacing/radius/color/control-size literals.
- Modify: corresponding package tests.
- Modify: Widgetbook stories only where required to provide `AgencyTheme`/extensions.

**Interfaces:**
- Consumes: `Theme.of(context)` and `AgencyThemeTokens.of(context)`.
- No new canonical semantic path may be invented directly in Flutter; if a necessary reusable semantic is missing, add it to Task 1/2 governed catalog + compiler tests before using it.

- [ ] **Step 1: Add focused widget tests for semantic styling**

Select the smallest representative set covering card radius/spacing, input/search treatment, primary control styling, and one dense trade/list surface. Tests should render the same widget under two resolved themes/densities and prove the expected semantic difference.

- [ ] **Step 2: Run tests and confirm RED where hard-coded styling remains**

Run affected `agency_flutter_ui` tests.

- [ ] **Step 3: Replace repeated high-value literals with theme reads**

Migrate only major active surfaces defined in the spec: root/surface, text hierarchy, cards, inputs/search, buttons/primary controls, shared spacing/radius, and active product/list/detail/trade patterns. Leave one-off decorative constants alone.

- [ ] **Step 4: Run Widgetbook/shared UI tests and analyze**

```bash
cd packages/agency_flutter_ui && flutter test && flutter analyze
cd ../../apps/widgetbook && flutter test && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add packages/agency_flutter_ui apps/widgetbook
git commit -m "refactor: apply semantic theme tokens to active UI"
```

---

### Task 7: Wire repository validation, CI freshness, and cross-layer parity

**Files:**
- Modify: `tooling/validation/validate_repo.py`
- Modify: `tooling/validation/test_validate_repo.py`
- Modify: existing GitHub Actions repository validation workflow
- Modify: existing Flutter CI workflow only if a new explicit theme generation/check command is required
- Modify: `.gitattributes` only if new checked text artifact paths are not already covered by B.1D LF rules

**Interfaces:**
- Repository validation invokes token catalog validation, preset validation, runtime fresh-compile parity, and checked output freshness.
- CI command exits non-zero on stale generated theme/runtime artifacts.

- [ ] **Step 1: Write failing repository validation tests**

Create fixture mutations for stale theme JSON, unknown preset, invalid reference, unsupported override path, and missing Flutter-required semantic field. Assert deterministic, insertion-order-independent errors.

- [ ] **Step 2: Run tests and confirm RED**

Run:
`py -3.12 -m unittest tooling.validation.test_validate_repo -v`

- [ ] **Step 3: Integrate B.1E checks into `validate_repo.py`**

Reuse the compiler/validator APIs; do not duplicate theme parsing logic in repository validation.

- [ ] **Step 4: Add CI freshness command**

Follow the existing B.1D generated binding pattern: CI must run a check-only command that does not mutate repository files and fails byte-exactly when checked generated artifacts are stale.

- [ ] **Step 5: Run focused + full Python validation and commit**

```bash
py -3.12 -m unittest discover tooling/validation -v
py -3.12 tooling/validation/validate_repo.py
git add tooling/validation .github .gitattributes
git commit -m "ci: enforce token and theme contract parity"
```

---

### Task 8: Documentation, full verification, independent review, and PR

**Files:**
- Modify: relevant architecture/readme docs describing Design Contract/runtime theming and Nowa operating rule.
- Do not modify the approved spec except for a factual correction discovered during implementation; document any ruling/deviation separately under `docs/superpowers/rulings/`.

**Interfaces:**
- Final deliverable must satisfy all 12 B.1E success criteria in the spec.

- [ ] **Step 1: Document the final authority boundaries**

Document this exact ownership chain:

```text
client brand facts + direction intent
        ↓
Design Contract token/theme compiler
        ↓
resolved runtime theme
        ↓
Flutter ThemeData + AgencyThemeTokens
        ↓
Nowa may refine implementation, but GitHub/config remains authority
```

- [ ] **Step 2: Run focused Python verification**

```bash
py -3.12 -m unittest tooling.validation.test_theme_contract -v
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
py -3.12 -m unittest tooling.validation.test_validate_repo -v
```

Expected: all pass.

- [ ] **Step 3: Run full repository validation**

```bash
py -3.12 -m unittest discover tooling/validation -v
py -3.12 tooling/validation/validate_repo.py
```

Also run the repository's knowledge, workflow, and prototype validators and the theme compiler/freshness `--check` command created in this plan.

- [ ] **Step 4: Run full Flutter verification**

For `apps/prototype_app`, `packages/agency_flutter_ui`, and `apps/widgetbook`:

```bash
flutter analyze
flutter test
```

Then from `apps/prototype_app`:

```bash
flutter build web
```

Expected: zero analyzer errors, all tests pass, web build succeeds.

- [ ] **Step 5: Run final whole-branch review**

Use a fresh reviewer subagent. Specifically inspect: precedence correctness; reference cycle handling; override allowlists; deterministic errors/output; runtime fresh-compile parity; absence of seed-color fallback for valid B.1E bundles; B.1D regressions; canonical density preservation; hard-coded active styling that should have been migrated; and accidental expansion into Review Mode/Nowa-specific source-of-truth behavior.

- [ ] **Step 6: Fix review findings and repeat affected verification**

Every blocker/high-confidence correctness finding gets a regression test before the fix. Re-run the smallest affected suite, then the full verification set before completion.

- [ ] **Step 7: Commit docs/final corrections, push, and open PR**

```bash
git add docs tooling design-contract client-projects apps packages .github .gitattributes
git commit -m "docs: complete B.1E token and theme contract"
git push -u origin milestone-b1e-token-theme-contract
gh pr create --base main --head milestone-b1e-token-theme-contract --title "Milestone B.1E: govern token and theme contract" --body-file <prepared-pr-body>
```

Do not merge the PR during implementation. Report branch SHA, PR number/URL, verification counts, review findings/fixes, and any explicit design rulings or deviations.

---

## Self-Review Against Spec

- Foundation + semantic token contracts: Tasks 1–2.
- Presets and approved reuse: Task 2.
- Client brand + direction override governance: Task 3.
- Exact precedence order: Tasks 2–3.
- Deterministic compiler/output/reference resolution/cycles: Tasks 1–4.
- B.1B runtime integration/freshness parity: Task 4 + Task 7.
- Flutter `ThemeData` + `AgencyThemeTokens`: Task 5.
- Typography/density/motion/breakpoints: Tasks 1, 3, 5.
- Active high-value styling migration: Task 6.
- Nowa authority boundary: Task 8 documentation; no Nowa-specific persistence added.
- Repository validation/CI: Task 7.
- Full Python/Flutter/web verification + independent review: Task 8.
- Non-goals remain outside implementation tasks.

No placeholders or deferred implementation requirements are part of this plan; any implementation-discovered ambiguity that changes a public contract must be recorded as a ruling and reviewed before proceeding past the affected task.
