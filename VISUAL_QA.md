# Visual QA Policy

## Purpose

Code inspection alone is not sufficient for UI approval. Meaningful UI work must be rendered and visually reviewed before it is considered complete.

## Component review

Use `apps/widgetbook/` for reviewing:

- components
- states
- variants
- themes
- density
- responsive behavior at component/pattern level

## Full-screen review

Use `apps/prototype_app/` for reviewing:

- direction A/B/C
- complete screen/pattern composition
- navigation and primary journeys
- responsive layouts
- transaction-model differences
- interactions dependent on real composition

Flutter Web supports stable review URLs:

```text
/?client=<client-id>&direction=a
/?client=<client-id>&direction=b
/?client=<client-id>&direction=c
```

## Standard viewports

Capture/review:

- 360 × 800
- 390 × 844
- 430 × 932
- 768 × 1024
- 1440 × 900

The client screenshot manifest under `prototype/qa/` is the machine-readable source for these capture jobs.

## Visual inspection checklist

Check for:

- spacing consistency
- alignment
- clipping and overflow
- text wrapping
- visual hierarchy
- inconsistent card or tile sizing
- image aspect ratios and cropping
- typography hierarchy
- icon consistency
- responsive behavior
- density appropriateness
- direction-level journey clarity
- design-system/token violations
- obvious accessibility issues
- broken or misleading interactions

## Structured findings

Write findings to:

`client-projects/<client>/prototype/qa/visual-findings.yaml`

Each finding must include:

- `severity`: low / medium / high / critical
- `screen`
- `direction`: a / b / c
- `viewport`
- `issue`
- `status`: open / resolved / accepted
- optional `evidence`

Unresolved critical findings block client review.

## Required loop

```text
OpenCode changes Flutter/config
→ render prototype / Widgetbook
→ capture required screenshots
→ visual inspection / AI vision review
→ record structured findings
→ map issue to config/component/pattern/token/resource
→ OpenCode fixes
→ rerender
→ resolve/accept finding
→ golden regression where stable and valuable
```

## Automation boundary

Milestone B provides deterministic screenshot manifests and capture-job planning. Browser/image capture can be executed locally or in a suitable UI runner; CI must at minimum validate the capture manifest and QA contracts even when browser capture is not available.

## Completion rule

Do not declare meaningful UI work visually complete solely because Dart analysis or unit tests pass. Required visual artifacts must exist and no unresolved critical findings may remain.

## Relationship to AGENTS.md

`AGENTS.md` is the master control file. Agents completing meaningful shared or client UI work must read and follow this policy before completion.
