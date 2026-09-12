# Visual QA Policy

## Purpose

Code inspection alone is not sufficient for UI approval. Meaningful UI work must be rendered and visually reviewed before it is considered complete.

## Component review

Use Widgetbook for reviewing:

- components
- states
- variants
- themes
- responsive behavior at component level

## Full-screen review

Use `flutter run` for reviewing:

- complete screens
- navigation
- user journeys
- responsive layouts
- interactions that depend on real screen composition

## Standard viewports

At minimum review relevant mobile UI at:

- 360 × 800
- 390 × 844
- 430 × 932

Also review tablet and desktop/web sizes where the product supports them.

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
- design-system or token violations
- obvious accessibility issues

## Required loop

```text
OpenCode changes Flutter
→ render in Flutter / Widgetbook
→ capture screenshot
→ visual inspection / AI vision review
→ record issues
→ OpenCode fixes implementation
→ render again
→ golden regression test where appropriate
```

## Completion rule

Do not declare meaningful UI work visually complete solely because Dart analysis or unit tests pass. The rendered result must also be reviewed.

## Relationship to AGENTS.md

`AGENTS.md` is the master control file. Agents completing meaningful shared or client UI work must read and follow this policy before completion.
