# Resource Research

## PURPOSE
Find and govern external/client resources needed by the selected experience context.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/resolved-intelligence.yaml`
- `client-projects/<client>/input/references/`
- `resources/registry/`
- `resources/policies/`
- `REFERENCE_POLICY.md`

## PROCESS
1. Detect resource requirements: imagery, icons, fonts, motion, Flutter references/packages, maps, video, or demo assets.
2. Route each request to the approved source hierarchy.
3. Evaluate license/status, fit, compatibility, quality, maintenance, accessibility, and provenance requirements.
4. Rank/select only approved or approved-with-rules resources.
5. If no external resource is needed, explicitly skip this stage with a reason.

## WRITE
- `client-projects/<client>/resources/selection.yaml`
- Client provenance entries when external resources are selected.

## VALIDATE
Every selected external resource must have an allowed status and traceable provenance.

## DO NOT
- Do not use blocked resources.
- Do not bypass normalization for external Flutter/UI references.
- Do not silently skip this stage.

## NEXT
`04-generate-directions.md`
