# Visual QA

## PURPOSE
Run technical and visual quality checks on rendered direction prototypes and record structured findings.

## READ
- `client-projects/<client>/prototype/prototype-manifest.yaml`
- `client-projects/<client>/prototype/qa/screenshot-manifest.yaml`
- `VISUAL_QA.md`
- direction configs and selected resources

## PROCESS
1. Build or serve `apps/prototype_app` for Flutter Web.
2. Use the screenshot manifest to capture A/B/C at 360×800, 390×844, 430×932, 768×1024, and 1440×900.
3. Review hierarchy, spacing, clipping, density, imagery, responsiveness, accessibility, interaction clarity, and broken states.
4. Record every issue using the structured visual finding contract.
5. Resolve or explicitly accept findings; unresolved critical findings block client review.
6. Re-render affected screens after fixes.

## WRITE
- screenshots under `client-projects/<client>/prototype/screenshots/`
- `client-projects/<client>/prototype/qa/visual-findings.yaml`

## VALIDATE
- Screenshot manifest exists.
- Visual findings validate structurally.
- No unresolved critical findings remain before client review.

## DO NOT
- Do not declare UI complete from static analysis alone.
- Do not hide unresolved critical findings.
- Do not change the client strategy merely to make visual QA easier.

## NEXT
`07-client-review.md`
