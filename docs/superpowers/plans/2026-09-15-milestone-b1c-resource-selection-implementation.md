# Milestone B.1C Resource Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an executable, auditable high-impact resource selection pipeline that derives asset requirements, evaluates client/agency/Pexels/icon/motion candidates, selects and normalizes resources, and binds canonical IDs into the client prototype runtime.

**Architecture:** Extend the existing Resource Intelligence registry/workflow rather than create a parallel system. Provider-specific adapters normalize into one candidate contract; sourcing policy controls whether client assets are authoritative, preferred, compared, or supplemented by discovery. Flutter consumes canonical semantic resource IDs through prototype runtime bindings.

**Tech Stack:** Python 3.12, PyYAML, jsonschema, urllib.request (stdlib HTTP), existing workflow/prototype tooling, Flutter runtime artifacts.

**Spec:** `docs/superpowers/specs/2026-09-15-milestone-b1c-resource-selection-design.md`

## Global Constraints
- Never commit provider API keys; `PEXELS_API_KEY` is environment-only.
- CI must not call external providers.
- Client/source truth remains under `client-projects/<client>/input/`; OpenCode inference belongs under `derived/`.
- Authoritative identity assets cannot be replaced by stock providers.
- Comparative/discovery requirements may research alternatives even when client assets exist.
- External resources require traceable provenance before runtime binding.
- Flutter-facing contracts use canonical semantic IDs, not raw provider URLs.

---

### Task 1: Resource contracts and sourcing policy

**Files:**
- Create: `resources/policies/sourcing-policy.yaml`
- Create: `resources/registry/schema/resource-requirements.schema.json`
- Create: `resources/registry/schema/resource-candidates.schema.json`
- Create: `resources/registry/schema/resource-selection.schema.json`
- Create: `resources/registry/schema/resource-provenance.schema.json`
- Create: `tooling/validation/test_resource_selection.py`

**Interfaces:**
- Produces canonical fields used by all later resource tooling: `id`, `type`, `role`, `impact`, `sourcing.mode`, candidate `source`, selection `primary`, provenance entries.

- [ ] Write failing tests that require the four sourcing modes, reject invalid modes, require critical requirement IDs/roles, and reject a selected candidate missing from `candidates.yaml`.
- [ ] Run the focused validation test and confirm RED because contracts/tooling are missing.
- [ ] Add schemas and sourcing policy with authoritative/prefer_client/comparative/discovery semantics.
- [ ] Re-run focused tests and confirm GREEN for contract parsing/schema cases.
- [ ] Commit `feat: add B.1C resource contracts and sourcing policy`.

### Task 2: Core requirement/router/client-asset tooling

**Files:**
- Create: `tooling/resources/__init__.py`
- Create: `tooling/resources/requirements.py`
- Create: `tooling/resources/provider_router.py`
- Create: `tooling/resources/client_assets.py`
- Modify: `tooling/validation/test_resource_selection.py`

**Interfaces:**
- `load_requirements(root: Path, client_dir: Path) -> dict`
- `route_sources(requirement: dict, client_candidates_exist: bool) -> list[str]`
- `client_asset_candidates(client_dir: Path, requirement: dict) -> list[dict]`

- [ ] Add failing tests for authoritative routing, prefer-client stop/search behavior, comparative always including allowed external sources, and client manifest normalization.
- [ ] Run focused tests and confirm expected RED.
- [ ] Implement minimal loader/router/client resolver.
- [ ] Re-run focused tests and confirm GREEN.
- [ ] Commit `feat: route B.1C resource requirements and client assets`.

### Task 3: Pexels provider adapter

**Files:**
- Modify: `resources/registry/providers/pexels.yaml`
- Create: `tooling/resources/pexels_client.py`
- Modify: `tooling/validation/test_resource_selection.py`

**Interfaces:**
- `search_pexels(requirement: dict, api_key: str | None = None, transport=None) -> list[dict]`
- Missing key returns an empty candidate list plus controlled availability metadata or an empty list without raising.

- [ ] Add failing tests using an injected local transport fixture so no network call occurs.
- [ ] Assert header uses the supplied key, query derives from requirement subject/role, results normalize provider ID/dimensions/source URL/photographer, and missing key does not crash.
- [ ] Run focused tests and confirm RED.
- [ ] Implement adapter with stdlib HTTP and dependency-injected transport.
- [ ] Re-run focused tests and confirm GREEN.
- [ ] Commit `feat: add governed Pexels resource adapter`.

### Task 4: Semantic icon and motion registries

**Files:**
- Create: `resources/registry/icons/semantic-icons.yaml`
- Create: `resources/registry/motion/motion-assets.yaml`
- Create: `tooling/resources/icon_resolver.py`
- Create: `tooling/resources/motion_resolver.py`
- Modify: `tooling/validation/test_resource_selection.py`

**Interfaces:**
- `resolve_icon(root: Path, semantic_id: str) -> dict`
- `resolve_motion(root: Path, semantic_id: str) -> dict`

- [ ] Add failing tests for known IDs, fallbacks, and unknown IDs.
- [ ] Run focused tests and confirm RED.
- [ ] Add minimal approved registries and resolvers.
- [ ] Re-run focused tests and confirm GREEN.
- [ ] Commit `feat: add semantic icon and motion resolution`.

### Task 5: Candidate scoring, selection, provenance, normalization

**Files:**
- Create: `tooling/resources/scorer.py`
- Create: `tooling/resources/selector.py`
- Create: `tooling/resources/normalizer.py`
- Create: `tooling/resources/validate_resources.py`
- Modify: `tooling/validation/test_resource_selection.py`

**Interfaces:**
- `score_candidate(requirement: dict, candidate: dict) -> float`
- `select_candidates(requirements: dict, candidates: dict) -> dict`
- `normalize_bindings(selection: dict, candidates: dict) -> dict`
- `validate_resource_artifacts(root: Path, client_dir: Path) -> list[str]`

- [ ] Add failing tests proving: comparative can beat a client asset, prefer_client gets bounded bonus, authoritative rejects Pexels, fallback is retained, external selection requires provenance, and normalized IDs are canonical.
- [ ] Run focused tests and confirm RED.
- [ ] Implement deterministic scoring weights and source-mode rules.
- [ ] Implement selector/normalizer/validator.
- [ ] Re-run focused tests and confirm GREEN.
- [ ] Commit `feat: score select and normalize client resources`.

### Task 6: Workflow and reference-client integration

**Files:**
- Modify: `workflows/02-resolve-intelligence.md`
- Modify: `workflows/03-resource-research.md`
- Modify: `workflows/04-generate-directions.md`
- Modify: `workflows/05-build-prototype.md`
- Create: `client-projects/examples/prototype-demo/derived/resource-requirements.yaml`
- Create: `client-projects/examples/prototype-demo/resources/candidates.yaml`
- Create: `client-projects/examples/prototype-demo/resources/selection.yaml`
- Create: `client-projects/examples/prototype-demo/resources/provenance.yaml`
- Modify: `tooling/validation/test_resource_integration.py`

**Interfaces:**
- Workflow 03 writes deterministic resource artifacts and can skip only with an explicit reason when no resource need exists.

- [ ] Add failing integration tests for the reference client: valid requirements, a comparative hero with both client/Pexels candidates, authoritative logo remaining client sourced, valid provenance, and validator success.
- [ ] Run integration test and confirm RED.
- [ ] Add reference artifacts and workflow text.
- [ ] Re-run integration test and confirm GREEN.
- [ ] Commit `feat: integrate B.1C into resource research workflow`.

### Task 7: Prototype manifest binding

**Files:**
- Modify: `tooling/prototype/build_prototype.py`
- Modify: `tooling/validation/test_prototype_platform.py`
- Modify: `tooling/validation/test_prototype_workflow_integration.py`

**Interfaces:**
- `prototype-manifest.yaml` gains a `resources` mapping when `resources/selection.yaml` and candidates are present.
- Existing clients without B.1C artifacts remain buildable until Workflow 03 requires them.

- [ ] Add failing tests that require canonical resource bindings in the generated manifest and prohibit raw provider URLs as runtime keys.
- [ ] Run focused prototype tests and confirm RED.
- [ ] Extend composer to load/validate/normalize selected resources and write `resources` in the manifest.
- [ ] Re-run focused tests and confirm GREEN.
- [ ] Commit `feat: bind selected resources into prototype manifest`.

### Task 8: Repository validation, CI, docs, regression

**Files:**
- Modify: `tooling/validation/validate_repo.py`
- Modify: `.github/workflows/validate.yml`
- Create: `docs/resource-intelligence.md`
- Modify: `AGENTS.md` if required to point OpenCode to B.1C runtime rules.

**Interfaces:**
- Repository validation requires B.1C schemas/tooling/registries.
- CI runs resource tests without any Pexels secret or network access.

- [ ] Add failing repo-validation assertions for the new required B.1C paths.
- [ ] Run validation and confirm RED.
- [ ] Update validator/CI/docs.
- [ ] Run the full Python validation suite.
- [ ] Run existing Flutter analyze/tests/build workflow unchanged to catch prototype regressions.
- [ ] Confirm no secret is committed and `.gitignore` still excludes `.env`/`.env.*`.
- [ ] Commit `test: validate B.1C resource selection end to end`.

## Final verification
Run the repository's complete validation commands from `AGENTS.md`/CI, including all Python validation tests, knowledge/workflow/prototype validators, Flutter analyze/tests, and Flutter Web build. The Pexels tests must use injected fixtures and never require `PEXELS_API_KEY` in CI.
