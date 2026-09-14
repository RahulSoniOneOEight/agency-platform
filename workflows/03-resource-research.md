# Resource Research

## PURPOSE
Execute governed resource selection for client-owned, agency-approved, and external resources needed by the experience context.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/derived/resource-requirements.yaml`
- `client-projects/<client>/resolved-intelligence.yaml`
- `client-projects/<client>/input/assets/asset-manifest.yaml`
- `client-projects/<client>/input/references/`
- `resources/registry/`
- `resources/policies/sourcing-policy.yaml`
- `REFERENCE_POLICY.md`

## PROCESS
1. Validate resource requirements and classify each requirement by impact and sourcing mode.
2. Inspect client-owned assets first, but do not stop comparative/discovery research merely because a client candidate exists.
3. Route each requirement through the approved source policy: authoritative, prefer_client, comparative, or discovery.
4. Search approved providers only when permitted; Pexels uses `PEXELS_API_KEY` from the environment and never stores credentials in Git.
5. Normalize client, agency, Pexels, icon, and motion results into the common candidate contract.
6. Evaluate fit, quality, composition, accessibility, provider status, licensing/provenance, and consistency.
7. Select a primary resource and fallback where useful; authoritative assets may only use client/official/agency-authorized sources.
8. Record provenance for every external selection.
9. Normalize selected resources to canonical semantic IDs for prototype/runtime consumption.
10. If no resource research is needed, explicitly skip this stage with a reason.

## WRITE
- `client-projects/<client>/resources/candidates.yaml`
- `client-projects/<client>/resources/selection.yaml`
- `client-projects/<client>/resources/provenance.yaml`
- `client-projects/<client>/resources/generated/` when local normalized files are required

## VALIDATE
- Every critical resource requirement has a valid selection.
- Every selected external resource has traceable provenance.
- Blocked providers/resources are not selected.
- Authoritative requirements never select stock providers.
- Canonical bindings are unique and resolve to known candidates.

## DO NOT
- Do not use blocked resources.
- Do not bypass normalization for external Flutter/UI references.
- Do not silently skip this stage.
- Do not commit provider credentials.
- Do not call external providers from CI validation.

## NEXT
`04-generate-directions.md`
