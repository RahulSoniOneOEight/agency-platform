# Nowa Visual Refinement Workflow

This guide is for the agency operator who uses Nowa as an optional visual Flutter workbench
between OpenCode-generated Flutter and client review. It explains when to use Nowa, what it may
change, how to keep working on the same Flutter project, how to hand control back to OpenCode,
how to classify changes, and what must never remain Nowa-only.

Nowa is a convenience, not a dependency. If Nowa is unavailable, the prototype must still build and
run from the repository alone.

## Role and boundaries

Nowa is an optional **Visual Flutter Workbench**. It may accelerate:

- spacing and layout refinement;
- responsive tuning;
- typography presentation;
- visual hierarchy;
- component composition;
- section ordering;
- card/image proportions;
- direction-level visual differentiation;
- workshop-time visual changes;
- last-mile prototype polish.

Nowa does **not** own:

- product/UX strategy;
- Direction Engine decisions;
- canonical component/pattern IDs;
- Design Contract authority;
- token/theme precedence;
- client review/approval state;
- production authorization;
- API/data architecture;
- workflow state.

If a task falls in the "does not own" list, stop and route it through OpenCode and the governed
repository artifacts. Do not resolve it in the workbench.

## Before opening Nowa

Do not start a visual session until every item below is true. This is the pre-Nowa baseline.

1. **Git status is clean or fully understood.** `git status --short` shows only the files you
   intend to touch. Never begin visual edits on top of unknown or half-finished changes.
2. **The correct client/direction runtime bundle is generated.** The bundle at
   `apps/prototype_app/assets/generated/<client-id>.json` matches the client and directions you
   are about to preview.
3. **B.1D Flutter bindings are fresh.**
   ```bash
   python -m tooling.design_contract.generate_flutter_bindings --check
   ```
4. **B.1E resolved themes are fresh.**
   ```bash
   python -m tooling.design_contract.generate_resolved_themes --check
   ```
5. **The Flutter app runs before you make visual edits.** Confirm the prototype app launches and
   renders the target client/direction, so you have a known-good starting point.
6. **A baseline commit or a clearly identified baseline SHA exists.** Record it (for example in the
   session notes or the run ledger) so the post-Nowa diff is reviewable.

If any check fails, regenerate the artifact or fix the repository state first. Never "repair" a
stale bundle by editing generated files.

## Working on the same Flutter project

Nowa must operate on the **same Flutter repository/project** used by OpenCode and CI. There is one
prototype codebase; visual refinement edits that codebase in place.

Do not introduce:

- a parallel prototype app;
- duplicated A/B/C Flutter codebases;
- exported throwaway code as the primary review artifact;
- a Nowa-specific design system that diverges from `design-contract/`;
- a runtime dependency on Nowa.

Directions configure the shared app; they do not fork it. All work happens in the ordinary
repository working tree so that OpenCode can review a normal `git diff`.

## Workshop mode

Use this loop for live client sessions:

```text
client request -> live Nowa adjustment -> preview -> accept/reject -> OpenCode reconciliation -> tests -> commit
```

- Adjust in Nowa, preview immediately, and let the client accept or reject in the room.
- On **accept**, hand the change to OpenCode for reconciliation before it becomes authoritative.
- On **reject**, discard the experiment. Rejected experiments are throwaway and do **not** need
  refinement-note entries.
- Only reconciled, committed changes become authoritative. A live preview is not a decision of
  record.

## Handing control back to OpenCode

When the workshop or refinement session ends, OpenCode reconciles the working tree. Follow this
exact decision order:

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

OpenCode, not Nowa, owns steps 3–12. If a change cannot be classified or represented in the
repository, it is not ready to commit.

## Classification decision table

Every **retained** Nowa change must be classified during reconciliation. Allowed classifications
are exactly the six below.

| Classification | Meaning | Action |
|----------------|---------|--------|
| `semantic_token` | An existing B.1E semantic token already governs the visual decision. | Change the appropriate theme/token/client/direction override instead of leaving an arbitrary widget literal. |
| `client_override` | Intentional and client-specific visual decision. | Represent it in an approved client-level semantic/config boundary where supported. |
| `direction_override` | Intentional visual difference between experience directions. | Keep it within approved direction-level semantic overrides. |
| `reusable_candidate` | Potentially valuable across multiple clients or patterns. | Propose promotion into B.1E semantic tokens, the Design Contract, shared Flutter UI, or a reusable preset. |
| `implementation_detail` | Legitimate local Flutter implementation detail that does not represent reusable/client semantic intent. | Keep in Flutter code; document only when material. |
| `reject` | Change bypasses architecture, duplicates an existing contract, introduces unsupported one-off styling, or cannot be justified. | Revert or replace with governed implementation. |

## Reconciliation checklist

Use this as the working checklist for the handoff in the previous section. Do not commit until
every applicable item is done.

- [ ] Inspect `git diff` and confirm every changed file is expected.
- [ ] List the material visual changes (spacing, radius, color, density, motion, typography,
      layout, composition, ordering, proportions, direction differentiation).
- [ ] Classify each material change using the decision table above.
- [ ] For `semantic_token`, replace the arbitrary literal with the governing semantic token.
- [ ] For `client_override`, move the decision into the approved client-level boundary and confirm
      it does not leak into agency-wide defaults.
- [ ] For `direction_override`, keep it inside the approved direction-level semantic overrides.
- [ ] For `reusable_candidate`, promote it only through a normal governed contract change
      (B.1E semantic token, Design Contract, shared Flutter UI, or reusable preset) — never as an
      unnamed permanent client-local variant.
- [ ] For `implementation_detail`, keep it in Flutter code and document it only when material.
- [ ] For `reject`, revert it or replace it with a governed implementation.
- [ ] Confirm client-specific changes do not leak into agency-wide defaults.
- [ ] Run B.1D/B.1E validation (bindings + resolved themes freshness, repository validation).
- [ ] Run the Flutter verification appropriate to the changed scope (analyze/tests, and build web
      when the prototype is client-facing).
- [ ] Commit only the reconciled result.

## B.1D Design Contract protection

B.1F preserves canonical component/pattern IDs and governed Flutter bindings.

- Canonical component and pattern IDs from `design-contract/` stay authoritative.
- Flutter bindings (`design-contract/bindings/flutter/`, projected into
  `apps/prototype_app/lib/registry/generated_design_bindings.dart`) stay authoritative.
- Nowa may visually rearrange or configure components, but must **not** invent a second
  naming/identity layer for components or patterns.
- If a visual refinement implies a new reusable component variant, OpenCode proposes a Design
  Contract change rather than encoding an unnamed permanent variant only in client Flutter code.

## B.1E token/theme protection

B.1F preserves the Token + Theme Contract (`docs/token-theme-contract.md`). Map every governed
visual decision to its semantic representation:

| Nowa change | Governed representation |
|-------------|-------------------------|
| Spacing | Semantic spacing token where applicable |
| Radius | Semantic radius token |
| Brand color | Client brand override |
| Density | Canonical `compact \| normal \| spacious` semantics |
| Motion timing | Semantic motion token |
| Typography | Semantic typography / theme configuration |
| Component variant behavior | Design Contract / shared Flutter component change |

Client-specific changes must not leak into agency-wide defaults. Nowa must not become a path for
silently introducing duplicate hard-coded styling that conflicts with governed values.

## Git and commit rules

- Nowa may edit the working tree.
- Nowa is **not** the source of truth; GitHub is.
- Do not maintain a parallel Nowa-only project as the review artifact.
- Do not commit governed-semantic changes without OpenCode reconciliation.
- Do not commit directly from the workbench when the changes affect governed semantics.
- All retained state must be ordinary repository code/config.
- Any retained change that cannot be represented as ordinary repository code/config is
  non-authoritative and must not be required to reproduce the prototype.

Recommended session flow:

```text
feature/client prototype branch
  -> OpenCode baseline commit
  -> Nowa edits same working tree
  -> OpenCode reviews git diff
  -> reconciliation commit(s)
  -> existing CI
```

## CI verification

Existing B.1D and B.1E checks remain authoritative. A reconciled Nowa change must continue to pass
the repository and Flutter checks.

Canonical repository commands:

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform tooling.validation.test_workflow_runtime tooling.validation.test_client_input_contract tooling.validation.test_prototype_platform tooling.validation.test_prototype_workflow_integration tooling.validation.test_resource_selection tooling.validation.test_resource_integration tooling.validation.test_runtime_bundle tooling.validation.test_flutter_bindings tooling.validation.test_theme_contract tooling.validation.test_refinement_notes -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
python -m tooling.workflow.validate_workflow
python -m tooling.prototype.validate_prototype
python -m tooling.design_contract.generate_flutter_bindings --check
python -m tooling.design_contract.generate_resolved_themes --check
```

Flutter verification (per package/app: `apps/prototype_app`, `packages/agency_flutter_ui`,
`apps/widgetbook`):

```bash
flutter analyze
flutter test
```

For the client-facing prototype app also run:

```bash
flutter build web
```

The repository validation run covers: repository validation, Flutter binding freshness,
resolved-theme freshness, and the relevant Python validation tests. Flutter CI covers analyze,
tests, and the Flutter Web build.

## What must never remain Nowa-only

Any retained decision or state that cannot be represented as ordinary repository code/config is
non-authoritative. It must not be required to reproduce, build, or review the prototype.

Examples of forbidden Nowa-only authority include:

- a visual decision that exists only inside the workbench;
- a component/pattern identity that exists only in Nowa;
- a token, theme, spacing, or density value that exists only in a Nowa project file;
- review/approval state recorded only in the workbench;
- generated/exported code kept as the primary review artifact.

If you cannot point to the committed repository artifact that carries a decision, that decision
does not exist yet — reconcile and commit it.

## Example refinement-notes.yaml

An optional, checked-in example lives at
`client-projects/examples/prototype-demo/prototype/refinement-notes.yaml`:

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

This file is optional non-runtime metadata validated by `tooling/prototype/refinement_notes.py`; it
is never consumed by the runtime and is never required to render the prototype.
