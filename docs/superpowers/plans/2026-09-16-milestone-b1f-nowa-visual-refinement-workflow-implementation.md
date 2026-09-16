# Milestone B.1F — Nowa-Compatible Visual Refinement Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight, governed Nowa refinement workflow that records material visual decisions, validates them deterministically, keeps refinement metadata out of runtime authority, and gives OpenCode an explicit reconciliation process before GitHub/CI handoff.

**Architecture:** Nowa remains an optional visual editor working on the same Flutter project as OpenCode and CI. The repository gains an optional `refinement-notes.yaml` contract plus validator and operator documentation; runtime composition remains unchanged except for an explicit regression guard proving refinement notes are never consumed. Existing B.1D Design Contract and B.1E token/theme validation remain the authoritative gates.

**Tech Stack:** Python 3.12, YAML/JSON Schema conventions already used by the repository, Flutter/Dart, GitHub Actions, existing repository validators.

**Spec:** `docs/superpowers/specs/2026-09-16-milestone-b1f-nowa-visual-refinement-workflow-design.md`

## Global Constraints

- Nowa is an optional **Visual Flutter Workbench**, not a runtime or design authority.
- GitHub remains the only persistent source of truth.
- OpenCode, Nowa, CI, and later Review Mode operate on the same Flutter codebase.
- No Nowa-only state may be required to reproduce or build the prototype.
- B.1D canonical component/pattern IDs and Flutter bindings remain authoritative.
- B.1E semantic tokens/themes remain authoritative for governed styling.
- Allowed refinement classifications are exactly: `semantic_token`, `client_override`, `direction_override`, `reusable_candidate`, `implementation_detail`, `reject`.
- Allowed refinement statuses are exactly: `observed`, `accepted`, `reconciled`, `proposed`, `rejected`.
- `refinement-notes.yaml` is optional metadata only and must never be copied into runtime bundles or used to render Flutter.
- Validation errors must be deterministically ordered.
- Do not add a Nowa API integration, custom visual editor, BugDrop, Review Mode, screenshot automation, or Visual AI QA in this milestone.
- Do not introduce parallel A/B/C Flutter codebases or a Nowa-specific design system.

---

## File Structure

Create or modify these files only as needed by the tasks below:

- `client-projects/schema/refinement-notes.schema.json` — structural contract for optional refinement metadata.
- `tooling/prototype/refinement_notes.py` — loading and deterministic semantic validation.
- `tooling/validation/test_refinement_notes.py` — focused validator tests.
- `client-projects/examples/prototype-demo/prototype/refinement-notes.yaml` — valid reference example.
- `tooling/validation/test_runtime_bundle.py` — regression that refinement notes never enter runtime bundles.
- `tooling/validation/validate_repo.py` — discover/validate any repository refinement-note files.
- `tooling/validation/test_validate_repo.py` — repository-validation integration tests.
- `docs/nowa-visual-refinement-workflow.md` — operator guide and OpenCode reconciliation checklist.
- Existing CI workflow files only if the current repository-validation command does not already cover the new validator transitively.

Do not add Flutter runtime dependencies for B.1F.

---

### Task 1: Add the refinement-note schema and deterministic validator

**Files:**
- Create: `client-projects/schema/refinement-notes.schema.json`
- Create: `tooling/prototype/refinement_notes.py`
- Create: `tooling/validation/test_refinement_notes.py`

**Interfaces:**
- Consumes: YAML files at `client-projects/<client>/prototype/refinement-notes.yaml`.
- Produces: `load_refinement_notes(path: Path) -> dict` and `validate_refinement_notes(root: Path, path: Path) -> list[str]`.
- Later tasks rely on `validate_refinement_notes()` returning a stable sorted list and never raising for ordinary validation failures.

- [ ] **Step 1: Write failing tests for valid shape and exact enums**

Add tests equivalent to:

```python
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tooling.prototype.refinement_notes import validate_refinement_notes


class RefinementNotesTests(unittest.TestCase):
    def test_valid_notes_pass(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            note = root / "client-projects/demo/prototype/refinement-notes.yaml"
            note.parent.mkdir(parents=True)
            note.write_text(
                """version: 1
changes:
  - id: home-hero-height
    screen: home
    subject: hero
    change: reduce hero height
    classification: client_override
    status: reconciled
    target: theme.spacing.section
""",
                encoding="utf-8",
            )
            self.assertEqual(validate_refinement_notes(root, note), [])

    def test_invalid_classification_and_status_are_rejected(self):
        # Build a note using classification: custom and status: done.
        # Assert errors contain both enum violations in deterministic order.
        ...
```

Replace the final ellipsis with concrete fixture creation and exact assertions before committing; do not leave placeholders in repository code/tests.

- [ ] **Step 2: Run focused test and confirm failure**

Run:

```bash
py -3.12 -m unittest tooling.validation.test_refinement_notes -v
```

Expected: import/file-not-found failure because the contract does not exist yet.

- [ ] **Step 3: Create the JSON schema**

The schema must require:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["version", "changes"],
  "properties": {
    "version": {"const": 1},
    "changes": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "change", "classification", "status"],
        "properties": {
          "id": {"type": "string", "minLength": 1},
          "screen": {"type": "string", "minLength": 1},
          "component": {"type": "string", "minLength": 1},
          "pattern": {"type": "string", "minLength": 1},
          "subject": {"type": "string", "minLength": 1},
          "change": {"type": "string", "minLength": 1},
          "classification": {
            "enum": ["semantic_token", "client_override", "direction_override", "reusable_candidate", "implementation_detail", "reject"]
          },
          "status": {
            "enum": ["observed", "accepted", "reconciled", "proposed", "rejected"]
          },
          "target": {"type": "string", "minLength": 1},
          "notes": {"type": "string"}
        }
      }
    }
  }
}
```

- [ ] **Step 4: Implement loading + deterministic validation**

`tooling/prototype/refinement_notes.py` must:

```python
def load_refinement_notes(path: Path) -> dict:
    # UTF-8 YAML load; raise ValueError("invalid refinement notes: ...") for I/O/YAML/top-level shape failures.


def validate_refinement_notes(root: Path, path: Path) -> list[str]:
    # Return [] for valid notes.
    # Validate schema.
    # Reject duplicate change IDs.
    # Validate canonical component/pattern IDs when those fields are present.
    # Return sorted(errors).
```

Use the repository's existing Design Contract loaders/helpers rather than creating a second catalog parser.

- [ ] **Step 5: Add focused edge-case tests**

Cover at minimum:

```text
duplicate change ids
unknown component id
unknown pattern id
malformed YAML
non-object top level
unknown property
empty id
all six allowed classifications
all five allowed statuses
insertion-order-independent errors
```

- [ ] **Step 6: Run focused tests**

```bash
py -3.12 -m unittest tooling.validation.test_refinement_notes -v
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add client-projects/schema/refinement-notes.schema.json tooling/prototype/refinement_notes.py tooling/validation/test_refinement_notes.py
git commit -m "feat: govern visual refinement notes"
```

---

### Task 2: Add a governed example without making notes runtime authority

**Files:**
- Create: `client-projects/examples/prototype-demo/prototype/refinement-notes.yaml`
- Modify: `tooling/validation/test_runtime_bundle.py`

**Interfaces:**
- Consumes: Task 1 note contract.
- Produces: one valid reference fixture and a hard regression guarantee that runtime bundles ignore refinement notes.

- [ ] **Step 1: Write the runtime non-authority regression first**

Add a test around the existing runtime-bundle fixture/helper that creates a valid `prototype/refinement-notes.yaml`, composes the runtime bundle, and asserts:

```python
bundle = compose_runtime_bundle(client_dir)
self.assertNotIn("refinement_notes", bundle)
self.assertNotIn("refinement-notes", bundle)
self.assertNotIn("refinement-notes.yaml", json.dumps(bundle, sort_keys=True))
```

Also assert the output is byte-identical with and without the refinement note when all authoritative inputs are unchanged.

- [ ] **Step 2: Run the targeted runtime test**

```bash
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
```

The new test should pass with the current composer if the boundary is already correct; this is an intentional characterization test. If it fails, fix only the accidental runtime coupling and do not add a new theme/runtime field.

- [ ] **Step 3: Add the reference note**

Use a valid example such as:

```yaml
version: 1
changes:
  - id: home-hero-height
    screen: home
    subject: hero
    change: reduce hero height for the client workshop direction
    classification: client_override
    status: reconciled
    target: theme.spacing.section

  - id: compact-product-card-spacing
    component: commerce.product-card
    change: evaluate tighter compact card spacing across commerce prototypes
    classification: reusable_candidate
    status: proposed
    target: design-contract
```

If `commerce.product-card` is not the exact canonical ID on the branch, inspect the Design Contract and use the exact approved ID.

- [ ] **Step 4: Validate the example**

Use `validate_refinement_notes()` in a focused test or a direct Python command and assert no errors.

- [ ] **Step 5: Commit**

```bash
git add client-projects/examples/prototype-demo/prototype/refinement-notes.yaml tooling/validation/test_runtime_bundle.py
git commit -m "test: keep refinement notes out of runtime authority"
```

---

### Task 3: Integrate refinement-note validation into repository validation

**Files:**
- Modify: `tooling/validation/validate_repo.py`
- Modify: `tooling/validation/test_validate_repo.py`

**Interfaces:**
- Consumes: `validate_refinement_notes(root, path)` from Task 1.
- Produces: repository validation that discovers all `client-projects/**/prototype/refinement-notes.yaml` files and reports deterministic failures.

- [ ] **Step 1: Write failing repository-validation tests**

Add tests that create a temporary repository/client fixture and assert:

```text
valid refinement note -> repository validation passes this concern
invalid enum -> validation fails with the refinement-note path in the message
duplicate id -> validation fails
multiple invalid note files -> error ordering is stable by path then message
absence of refinement-notes.yaml -> no failure (file is optional)
```

- [ ] **Step 2: Run targeted tests and confirm failure**

```bash
py -3.12 -m unittest tooling.validation.test_validate_repo -v
```

Expected: the invalid note fixture is not yet discovered.

- [ ] **Step 3: Wire discovery into `validate_repo.py`**

Use a stable path scan equivalent to:

```python
note_paths = sorted(root.glob("client-projects/**/prototype/refinement-notes.yaml"), key=lambda p: p.as_posix())
for note_path in note_paths:
    for error in validate_refinement_notes(root, note_path):
        errors.append(f"{note_path.relative_to(root).as_posix()}: {error}")
```

Do not add the note file to a list of mandatory client paths; it is optional.

- [ ] **Step 4: Run repository-validator tests**

```bash
py -3.12 -m unittest tooling.validation.test_validate_repo -v
```

Expected: all tests pass.

- [ ] **Step 5: Run the actual validator**

```bash
py -3.12 tooling/validation/validate_repo.py
```

Expected: pass with the reference note validated.

- [ ] **Step 6: Commit**

```bash
git add tooling/validation/validate_repo.py tooling/validation/test_validate_repo.py
git commit -m "feat: validate visual refinement metadata"
```

---

### Task 4: Add the operator workflow and OpenCode reconciliation contract

**Files:**
- Create: `docs/nowa-visual-refinement-workflow.md`

**Interfaces:**
- Consumes: classifications/statuses from Task 1 and B.1D/B.1E authority boundaries.
- Produces: the human/agent operating procedure used before later Flutter Review Mode work.

- [ ] **Step 1: Write the operator guide with these exact sections**

```markdown
# Nowa Visual Refinement Workflow

## Role and boundaries
## Before opening Nowa
## Working on the same Flutter project
## Workshop mode
## Handing control back to OpenCode
## Classification decision table
## Reconciliation checklist
## B.1D Design Contract protection
## B.1E token/theme protection
## Git and commit rules
## CI verification
## What must never remain Nowa-only
## Example refinement-notes.yaml
```

- [ ] **Step 2: Document the required pre-Nowa baseline**

The guide must require:

```text
clean/understood git status
correct client/direction runtime bundle generated
B.1D bindings fresh
B.1E resolved themes fresh
Flutter app runs before visual edits
baseline commit or clearly identified baseline SHA
```

- [ ] **Step 3: Document the post-Nowa reconciliation checklist**

Use this exact decision order:

```text
1. inspect git diff
2. list material visual changes
3. existing semantic token? -> semantic_token
4. intentionally client-specific? -> client_override
5. intentionally direction-specific? -> direction_override
6. reusable across clients/patterns? -> reusable_candidate
7. justified local implementation detail? -> implementation_detail
8. otherwise -> reject
9. replace arbitrary literals with governed representation where applicable
10. run B.1D/B.1E validation
11. run Flutter verification appropriate to the changed scope
12. commit only the reconciled result
```

- [ ] **Step 4: Document Git rules**

The guide must state:

```text
Nowa may edit the working tree.
Nowa is not the source of truth.
Do not maintain a parallel Nowa-only project as the review artifact.
Do not commit governed-semantic changes without OpenCode reconciliation.
All retained state must be ordinary repository code/config.
```

- [ ] **Step 5: Document workshop mode**

Include:

```text
client request -> live Nowa adjustment -> preview -> accept/reject -> OpenCode reconciliation -> tests -> commit
```

Clarify that rejected workshop experiments can be discarded and do not need refinement-note entries.

- [ ] **Step 6: Commit**

```bash
git add docs/nowa-visual-refinement-workflow.md
git commit -m "docs: define Nowa visual refinement workflow"
```

---

### Task 5: Add architecture-boundary regression tests

**Files:**
- Modify: `tooling/validation/test_refinement_notes.py`
- Modify: `tooling/validation/test_runtime_bundle.py`
- Modify other focused validation tests only if necessary to reuse existing B.1D/B.1E fixtures.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: explicit regression protection for the milestone's source-of-truth boundaries.

- [ ] **Step 1: Add a test proving notes cannot redefine runtime theme authority**

Create a note with a target like `theme.color.primary` and an arbitrary change description. Assert runtime theme output stays exactly equal to a fresh B.1E compile from authoritative inputs.

- [ ] **Step 2: Add a test proving notes cannot redefine canonical component identity**

Use an unknown `component:` value and assert `validate_refinement_notes()` rejects it rather than accepting a Nowa-local identity.

- [ ] **Step 3: Add a test proving notes are optional**

Delete/omit `refinement-notes.yaml` from a complete client fixture and assert runtime/repository validation still succeeds.

- [ ] **Step 4: Add a deterministic error-order test**

Construct the same invalid changes in two YAML key/list insertion arrangements and assert the returned normalized error list is identical where semantic order is not meaningful. For duplicate IDs, preserve stable occurrence semantics and document the exact chosen behavior in the test name.

- [ ] **Step 5: Run focused regression suites**

```bash
py -3.12 -m unittest tooling.validation.test_refinement_notes -v
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
py -3.12 -m unittest tooling.validation.test_validate_repo -v
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add tooling/validation/test_refinement_notes.py tooling/validation/test_runtime_bundle.py tooling/validation/test_validate_repo.py
git commit -m "test: protect Nowa refinement authority boundaries"
```

---

### Task 6: Full verification, documentation check, final review, and PR

**Files:**
- Modify documentation only for corrections found during review.
- Modify code/tests only for findings required to satisfy the spec.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: merge-ready B.1F branch and pull request; no merge.

- [ ] **Step 1: Run focused B.1F tests**

```bash
py -3.12 -m unittest tooling.validation.test_refinement_notes -v
py -3.12 -m unittest tooling.validation.test_runtime_bundle -v
py -3.12 -m unittest tooling.validation.test_validate_repo -v
```

Expected: all pass.

- [ ] **Step 2: Run the full Python validation suite**

```bash
py -3.12 -m unittest discover tooling/validation
```

Expected: all tests pass.

- [ ] **Step 3: Run repository and contract validators**

Run the canonical repository commands present on the branch, including:

```bash
py -3.12 tooling/validation/validate_repo.py
py -3.12 -m tooling.knowledge.validate_knowledge
py -3.12 -m tooling.workflow.validate_workflow
py -3.12 -m tooling.prototype.validate_prototype
py -3.12 -m tooling.design_contract.generate_flutter_bindings --check
py -3.12 -m tooling.design_contract.generate_resolved_themes --check
```

If a module name differs, inspect the repository and use the canonical existing command; record the exact command in the final report.

- [ ] **Step 4: Run Flutter verification even though B.1F adds no runtime dependency**

In each package/app, run:

```bash
flutter analyze
flutter test
```

For the prototype app also run:

```bash
flutter build web
```

Verify:

```text
apps/prototype_app
packages/agency_flutter_ui
apps/widgetbook
```

- [ ] **Step 5: Perform final whole-branch review**

The independent reviewer must explicitly check:

```text
Nowa is not runtime authority
GitHub is still the only persistent source of truth
same-codebase rule is preserved
refinement notes are optional
refinement notes cannot enter runtime bundle
B.1D component/pattern identity remains canonical
B.1E semantic tokens/themes remain canonical
client-specific changes have a client-level path
reusable candidates have a promotion path
no Nowa API/custom editor scope creep
error ordering is deterministic
operator guide is executable by a non-expert agency operator
```

Fix blockers and re-review before opening the PR.

- [ ] **Step 6: Confirm clean branch state**

```bash
git status --short
git log --oneline --decorate -12
```

Do not accidentally include `pubspec.lock`, temporary Nowa files, editor state, build outputs, or stray workspace artifacts unless repository policy explicitly requires them.

- [ ] **Step 7: Push and open the PR**

```bash
git push -u origin milestone-b1f-nowa-visual-refinement-workflow
```

Open a PR against `main` titled:

```text
Milestone B.1F: govern Nowa visual refinement workflow
```

The PR body must summarize the workflow boundary, refinement-note contract, non-runtime guarantee, validation, documentation, and verification results.

Do **not** merge the PR.

---

## Self-Review Checklist

Before execution, confirm the plan covers every B.1F success criterion:

- Nowa role and boundaries → Task 4.
- Same-codebase/GitHub source-of-truth rule → Tasks 4 and 6 review.
- Classification system → Tasks 1 and 4.
- B.1D authority protection → Tasks 1, 4, 5.
- B.1E authority protection → Tasks 4 and 5.
- Client-specific/reusable promotion paths → Task 4.
- Optional refinement notes → Tasks 1–3 and 5.
- Deterministic validation → Tasks 1, 3, 5.
- Notes excluded from runtime → Tasks 2 and 5.
- Repeatable OpenCode reconciliation checklist → Task 4.
- Existing repository/Flutter CI stays green → Task 6.
- Ready for later Flutter Review Mode → Task 6.

No task introduces Review Mode, BugDrop, screenshot automation, Visual AI QA, or a Nowa API/runtime dependency.
