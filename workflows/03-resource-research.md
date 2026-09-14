# Resource Research

Detailed operating stages: **5. Detect resource needs** + **6. Resource search & evaluation**.

## PURPOSE
Turn known experience/capability needs into structured resource requests, then source and govern only approved resources with provenance.

## READ
- `client-projects/<client>/input/`
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/derived/intelligence-map.yaml`
- `client-projects/<client>/derived/capability-map.yaml`
- `client-projects/<client>/derived/gaps.yaml`
- `resources/registry/`
- `resources/policies/`
- `REFERENCE_POLICY.md`

## PROCESS
1. Detect required imagery, icons, fonts, motion, Flutter packages, references, maps, video, or demo assets.
2. Write each need as a structured resource requirement before searching.
3. Search client-owned and already-approved resources first.
4. Route unmet requirements to approved external source/provider categories.
5. Evaluate license/status, fit, compatibility, quality, maintenance, accessibility, and provenance requirements.
6. Rank/select only approved or approved-with-rules resources and record provenance.
7. If no external resource is required, skip resource search explicitly with a reason while retaining the resource-requirements artifact.

## WRITE
- `client-projects/<client>/derived/resource-requirements.yaml`
- `client-projects/<client>/resources/selection.yaml` when resources are selected
- `resources/incoming/`, `resources/approved/`, `resources/rejected/`, and registry metadata when shared resource governance is affected

## VALIDATE
- Resource requirements exist before resource selection.
- Every selected external resource has an allowed status and traceable provenance.
- A skipped resource-search stage has an explicit reason.

## DO NOT
- Do not use blocked resources.
- Do not bypass normalization for external Flutter/UI references.
- Do not search externally before checking client-owned and approved agency resources.
- Do not silently skip this stage.

## NEXT
`04-generate-directions.md`
