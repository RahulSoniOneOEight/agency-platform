# Milestone B — Prototype Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn validated Experience Directions into one configurable Flutter prototype application with reusable agency UI, deterministic demo data, Widgetbook review, visual-QA contracts, and client approval output.

**Architecture:** Milestone B adds a shared `agency_flutter_ui` package, a single `prototype_app`, and a strict direction-to-prototype translation layer. A/B/C remain configuration over one codebase. Python tooling validates direction/prototype/QA artifacts and the Workflow Runtime advances through build-prototype, visual-qa, and client-review only when concrete artifacts exist.

**Tech Stack:** Flutter stable, Dart 3, Material 3, Python 3.12, YAML, JSON Schema, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-14-milestone-b-prototype-platform-design.md`

## Global Constraints

- GitHub is the source of truth.
- OpenCode is the orchestrator; Flutter is the executable prototype UI.
- One shared Flutter design system and one configurable prototype app; never separate A/B/C source trees.
- Direction differences must be structural/strategic, not theme-only.
- Reusable Flutter widgets map to Design Contract IDs.
- Client branding enters through theme/config, not hard-coded reusable widgets.
- Demo data is deterministic and local for Milestone B.
- Prototype/QA/client-review artifacts are machine validated before workflow advancement.
- Production ERP/backend/auth/payments/shipping/CRM/WhatsApp/Supabase/n8n are excluded.
- Existing Knowledge Platform and Workflow Runtime validations must remain green.

---

### Task 1: Define Milestone B Contract Tests

**Files:**
- Create: `tooling/validation/test_prototype_platform.py`
- Modify: `.github/workflows/validate.yml`
- Modify: `.github/workflows/flutter-ci.yml`

**Interfaces:**
- Consumes: Workflow Runtime router and Design Contract indexes.
- Produces: executable requirements for prototype schemas, fixture generation, manifests, QA findings, approved-experience validation, and Workflow Runtime advancement.

- [ ] Write failing Python tests covering direction validation, deterministic fixtures, prototype manifest creation, screenshot manifest viewports, QA validation, approved-experience validation, prototype-platform installation detection, and workflow advancement.
- [ ] Extend repository validation CI to run `tooling.validation.test_prototype_platform` and `python -m tooling.prototype.validate_prototype`.
- [ ] Extend Flutter CI package discovery to include `apps/` in addition to `packages/`, `starters/`, and `client-projects/`.
- [ ] Verify RED: tests fail because `tooling.prototype` and Flutter platform files do not yet exist.
- [ ] Commit as `test: define prototype platform contract`.

### Task 2: Add Prototype Artifact Contracts and Tooling

**Files:**
- Create: `tooling/prototype/__init__.py`
- Create: `tooling/prototype/direction_schema.json`
- Create: `tooling/prototype/validate_direction.py`
- Create: `tooling/prototype/fixture_generator.py`
- Create: `tooling/prototype/screenshot_manifest.py`
- Create: `tooling/prototype/validate_visual_qa.py`
- Create: `tooling/prototype/validate_prototype.py`
- Create: `templates/prototype-manifest.yaml`
- Create: `templates/visual-qa-findings.yaml`

**Interfaces:**
- `validate_direction(direction: dict) -> list[str]`
- `generate_fixture_pack(industry: str, seed: int = 108) -> dict`
- `build_screenshot_manifest(client_id: str, directions: list[str]) -> dict`
- `validate_visual_findings(data: dict) -> list[str]`
- `validate_prototype_platform(root: Path) -> list[str]`

- [ ] Implement direction schema/validator that requires strategic goal, navigation, primary journey, search/discovery, merchandising, density, transaction model, component/pattern IDs, strengths/trade-offs.
- [ ] Implement deterministic fixture generation for `electronics-appliances`, `furniture-home`, `grocery-fmcg`, and `services-booking` using fixed seed data.
- [ ] Implement standard screenshot viewport manifest for 360×800, 390×844, 430×932, 768×1024, and 1440×900.
- [ ] Implement QA finding validation with severity, screen, direction, viewport, issue, status, and optional evidence.
- [ ] Implement top-level prototype validator for required schemas/templates/tooling.
- [ ] Run prototype contract tests and commit as `feat: add prototype artifact contracts`.

### Task 3: Build Shared Flutter Foundation Package

**Files:**
- Create: `packages/agency_flutter_ui/pubspec.yaml`
- Create: `packages/agency_flutter_ui/lib/agency_flutter_ui.dart`
- Create: `packages/agency_flutter_ui/lib/foundation/agency_tokens.dart`
- Create: `packages/agency_flutter_ui/lib/themes/agency_theme.dart`
- Create: `packages/agency_flutter_ui/lib/primitives/agency_button.dart`
- Create: `packages/agency_flutter_ui/lib/primitives/agency_search_field.dart`
- Create: `packages/agency_flutter_ui/lib/primitives/agency_chip.dart`
- Create: `packages/agency_flutter_ui/lib/primitives/agency_surface.dart`
- Create: `packages/agency_flutter_ui/test/foundation_test.dart`

**Interfaces:**
- `AgencyTokens` exposes semantic spacing/radius/motion constants.
- `AgencyTheme.light({Color? seedColor}) -> ThemeData`.
- primitives accept semantic parameters and Material states without client-specific hard-coding.

- [ ] Add package and failing token/theme/widget tests.
- [ ] Implement semantic tokens and Material 3 theme factory.
- [ ] Implement button, search field, chip, and surface primitives.
- [ ] Run `flutter analyze` and package tests.
- [ ] Commit as `feat: add agency Flutter foundations`.

### Task 4: Add Commerce Domain Components

**Files:**
- Create: `packages/agency_flutter_ui/lib/domain/product_models.dart`
- Create: `packages/agency_flutter_ui/lib/domain/product_card.dart`
- Create: `packages/agency_flutter_ui/lib/domain/price_display.dart`
- Create: `packages/agency_flutter_ui/lib/domain/category_tile.dart`
- Create: `packages/agency_flutter_ui/lib/domain/promo_tile.dart`
- Create: `packages/agency_flutter_ui/lib/domain/cart_item_card.dart`
- Create: `packages/agency_flutter_ui/lib/domain/quote_card.dart`
- Create: `packages/agency_flutter_ui/lib/domain/credit_summary.dart`
- Create: `packages/agency_flutter_ui/lib/domain/merchandising_split_tile.dart`
- Create: `packages/agency_flutter_ui/test/domain_components_test.dart`

**Interfaces:**
- `AgencyProduct`, `AgencyPrice`, and simple fixture-friendly value objects.
- `ProductCard(variant: ProductCardVariant, density: AgencyDensity, ...)`.
- domain widgets use shared tokens/theme and expose no backend dependency.

- [ ] Write widget tests for default/B2B/compact ProductCard variants and key component rendering.
- [ ] Implement value objects and domain components mapped to Design Contract IDs.
- [ ] Verify responsive constraints and semantic labels.
- [ ] Run Flutter analyze/tests and commit as `feat: add commerce domain components`.

### Task 5: Add Reusable Pattern Shells and Registry

**Files:**
- Create: `packages/agency_flutter_ui/lib/patterns/pattern_registry.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/home_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/search_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/plp_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/pdp_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/cart_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/rfq_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/trade_dashboard_pattern.dart`
- Create: `packages/agency_flutter_ui/lib/patterns/booking_pattern.dart`
- Create: `packages/agency_flutter_ui/test/pattern_registry_test.dart`

**Interfaces:**
- `AgencyPatternId` enumerates implemented canonical pattern IDs.
- `PatternRegistry.resolve(String id)` returns implemented pattern metadata/factory or rejects unknown IDs.

- [ ] Write registry tests for known/unknown IDs and pattern composition.
- [ ] Implement responsive shells for Home, Search, PLP, PDP, Cart, RFQ, Trade Dashboard, and Booking.
- [ ] Ensure patterns accept data/config and do not embed client branding.
- [ ] Run Flutter checks and commit as `feat: add reusable Flutter patterns`.

### Task 6: Build Single Configurable Prototype App

**Files:**
- Create: `apps/prototype_app/pubspec.yaml`
- Create: `apps/prototype_app/lib/main.dart`
- Create: `apps/prototype_app/lib/prototype_app.dart`
- Create: `apps/prototype_app/lib/direction/prototype_direction.dart`
- Create: `apps/prototype_app/lib/direction/direction_loader.dart`
- Create: `apps/prototype_app/lib/registry/prototype_registry.dart`
- Create: `apps/prototype_app/lib/fixtures/demo_repository.dart`
- Create: `apps/prototype_app/lib/screens/prototype_shell.dart`
- Create: `apps/prototype_app/test/direction_loader_test.dart`
- Create: `apps/prototype_app/test/prototype_app_test.dart`
- Create minimal Flutter Web bootstrap files required for build.

**Interfaces:**
- `PrototypeDirection.fromMap(Map<String,dynamic>)`.
- `DirectionLoader` resolves A/B/C from bundled prototype manifest/config.
- URL selection supports `?client=<id>&direction=a|b|c`.
- internal debug selector changes direction without changing source tree.

- [ ] Write failing parser/selector tests.
- [ ] Implement strict direction model and registry lookup.
- [ ] Implement local deterministic demo repository.
- [ ] Implement prototype shell with navigation and selected pattern composition.
- [ ] Add query-parameter direction selection plus internal switcher.
- [ ] Run Flutter analyze/tests/web build and commit as `feat: add configurable prototype app`.

### Task 7: Add Prototype Composer and Client Artifact Generation

**Files:**
- Create: `tooling/prototype/build_prototype.py`
- Create: `tooling/prototype/approved_experience.py`
- Create: `client-projects/examples/prototype-demo/` fixture workspace used only for regression validation.

**Interfaces:**
- `compose_prototype(root: Path, client_dir: Path) -> Path` writes `prototype/prototype-manifest.yaml` and fixture JSON/YAML without generating duplicate Flutter source.
- `validate_approved_experience(root, client_dir) -> list[str]` checks direction/pattern/component/resource references.

- [ ] Write tests that compose a manifest from three validated directions and deterministic fixtures.
- [ ] Ensure the manifest references the shared `apps/prototype_app` runtime instead of copying it.
- [ ] Implement approved-experience validator supporting full-direction selection and mixed sections.
- [ ] Add regression fixture client with A/B/C that differ structurally.
- [ ] Run prototype tests and commit as `feat: compose client prototypes from directions`.

### Task 8: Add Widgetbook Review Surface

**Files:**
- Create: `apps/widgetbook/pubspec.yaml`
- Create: `apps/widgetbook/lib/main.dart`
- Create: `apps/widgetbook/lib/widgetbook_app.dart`

**Interfaces:**
- Shows shared primitives/domain components/pattern examples and important variants/states/densities/themes.

- [ ] Add Widgetbook package dependency compatible with current Flutter stable.
- [ ] Register stories for buttons, search, ProductCard variants, merchandising split tile, RFQ/credit components, and key pattern shells.
- [ ] Ensure Widgetbook is development-only and imports `agency_flutter_ui` by path.
- [ ] Run analyze/test/build checks and commit as `feat: add Widgetbook review surface`.

### Task 9: Add Visual QA Runtime and Workflow Integration

**Files:**
- Create: `tooling/prototype/capture_screenshots.py`
- Modify: `tooling/workflow/router.py`
- Modify: `tooling/workflow/validate_workflow.py`
- Modify: `workflows/05-build-prototype.md`
- Modify: `workflows/06-visual-qa.md`
- Modify: `workflows/07-client-review.md`
- Modify: `templates/approved-experience.yaml`
- Modify: `tooling/validation/test_workflow_runtime.py`

**Interfaces:**
- Build-prototype advances when a valid prototype manifest exists and shared Flutter runtime is installed.
- Visual-QA requires screenshot manifest plus QA findings.
- Client-review requires prototype and QA artifacts and can produce validated approved experience.

- [ ] Replace `prototype-platform-not-installed` routing with concrete artifact gates.
- [ ] Add screenshot capture command contract using Flutter Web routes and standard viewport manifest; allow CI to validate manifests even where browser capture is not executed.
- [ ] Require QA findings with no unresolved critical issues before client-review completion.
- [ ] Require valid approved-experience to advance to productionize.
- [ ] Update runtime regression tests and commit as `feat: activate prototype workflow stages`.

### Task 10: CI, Documentation, and Final Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `VISUAL_QA.md`
- Modify: `docs/platform-status.md`
- Create: `docs/prototype-platform.md`
- Modify: `.github/workflows/flutter-ci.yml`
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- OpenCode reads prototype-platform docs before Flutter prototype composition.
- CI analyzes/tests all initialized Flutter packages/apps and validates Python contracts.

- [ ] Document direction→composer→Flutter→QA→client-review flow.
- [ ] Update `AGENTS.md` lookup/build rules and `VISUAL_QA.md` automated artifact contract.
- [ ] Make Flutter CI detect `apps/`, run package/app analyze and tests, and build `apps/prototype_app` for web.
- [ ] Run Python repository/Knowledge/Workflow/Prototype validation suites.
- [ ] Run Flutter analyze/tests for shared package, prototype app, and Widgetbook plus prototype web build.
- [ ] Update platform status and open PR with verification evidence.
- [ ] Commit as `docs: complete Milestone B prototype platform`.

## Final Verification Commands

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_prototype_platform -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
```

Flutter CI must additionally confirm analyze/tests for every initialized Flutter package/app and a successful Flutter Web build of `apps/prototype_app`.
