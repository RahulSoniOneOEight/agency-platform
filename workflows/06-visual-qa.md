# Visual QA

Detailed operating stages: **14. Visual AI QA** + **15. Correction loop**.

## PURPOSE
Review rendered direction prototypes visually, record structured findings, and fix issues at the correct shared/client layer until the prototype reaches client-review quality.

## READ
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/qa/screenshot-manifest.yaml`
- `client-projects/<client>/directions/`
- `client-projects/<client>/resources/selection.yaml` when present
- `VISUAL_QA.md`
- relevant Design Contract and shared Flutter implementation

## PROCESS
1. Build or serve `apps/prototype_app` for Flutter Web.
2. Capture A/B/C at 360×800, 390×844, 430×932, 768×1024, and 1440×900 according to the screenshot manifest.
3. Review hierarchy, spacing, clipping, density, imagery, responsiveness, accessibility, interaction clarity, consistency, and broken states.
4. Record every issue using the structured visual finding contract.
5. Map each finding to the correct layer: token, component, pattern, resource, direction config, or client-only override.
6. Apply fixes at that layer, rerender affected screens, and update finding status.
7. Resolve or explicitly accept findings; unresolved critical findings block client review.

## WRITE
- screenshots under `client-projects/<client>/prototype/screenshots/`
- `client-projects/<client>/prototype/qa/visual-findings.yaml`
- corrected shared package/pattern/config/resource files where justified

## VALIDATE
- Screenshot manifest exists and required routes/viewports are represented.
- Visual findings validate structurally.
- Corrections are applied at the appropriate layer rather than hidden by client-specific hacks.
- No unresolved critical findings remain before client review.

## DO NOT
- Do not declare UI complete from static analysis alone.
- Do not hide unresolved critical findings.
- Do not change the client strategy merely to make visual QA easier.
- Do not patch shared components for a one-off client need without confirming reuse value.

## NEXT
`07-client-review.md`
