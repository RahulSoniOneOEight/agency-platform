# Release

## PURPOSE
Execute the H.2B authorized production release for one exact, already-hardened
release candidate. This stage consumes the immutable H.1 production-foundation
evidence, the H.2A hardening evidence, and the exact Milestone-G
`ProductionAuthorization` for the frozen candidate, then produces the immutable
production `ReleaseRecord`.

Completion of this stage is **production-released** — a governed, no-rebuild
promotion of the exact staging-tested artifact, followed by production smoke and
the bounded telemetry health window. This stage never creates, grants, mutates,
or substitutes for a `ProductionAuthorization`: that remains the human
Milestone-G release-permission authority. The workflow runtime owns
workflow-state authority; GitHub Actions, agents, adapters, and QA tooling are
executors only.

## READ
- `client-projects/<client>/production/evidence/h1-foundation-report.json`
- `client-projects/<client>/production/evidence/h2-hardening-report.json`
- `client-projects/<client>/production/evidence/staging-smoke-report.json`
- `client-projects/<client>/production/release/candidate.json`
- `client-projects/<client>/production/release/artifact-manifest.json`
- `client-projects/<client>/production/release/staging-deployment.json`
- `client-projects/<client>/production/release/production-authorization-ref.json`
- `client-projects/<client>/release/reference-proof/production-authorization-v0001.json` (or the authorized G body named by the ref)
- `client-projects/<client>/production/hardening/recovery-policy.yaml`
- `docs/superpowers/specs/2026-09-18-milestone-h2-production-hardening-authorized-release-design.md`
- the G authorization and release-gate contracts

## PROCESS
1. Confirm the `productionize` stage is complete and the H.1 foundation report is present and self-verifying.
2. Re-validate the H.2A hardening evidence against the frozen candidate with the `h2-hardening` validator; blocking findings must be empty and the staging smoke must have passed.
3. Verify the exact G authorization against the exact candidate with the `production-authorization` validator (the existing G release gate); a missing, mismatched, or invalidated authorization blocks the stage. Never create or amend an authorization.
4. Promote the exact staging-tested artifact with no rebuild; verify the artifact digest and the authorized migration set before promotion.
5. Run the intentionally low-risk production smoke, then the bounded 5-sample telemetry health window.
6. Record the immutable `ReleaseRecord` binding approval, H.1 evidence, exact candidate, H.2A evidence, G authorization, deployment, and health result with the `h2-release-record` validator.
7. Route a degraded or failed outcome through the governed recovery coordinator; never blind-rollback the database.

## WRITE
- `client-projects/<client>/production/evidence/release-record.json` immutable release evidence
- `client-projects/<client>/production/evidence/production-smoke-report.json`
- `client-projects/<client>/production/evidence/telemetry-health-report.json`
- governed recovery evidence when the outcome is degraded or failed

## VALIDATE
Release cannot complete until every declared validator passes and the produced
release evidence exists and is recorded on the completion manifest:

- `h2-hardening` — `python -m tooling.hardening.validate <client_dir>` re-validates the committed H.2A hardening and staging-smoke evidence against the frozen candidate.
- `production-authorization` — `python -m tooling.production_authorization.validate <client_dir>` verifies the exact G authorization (existing release gate).
- `h2-release-record` — `python -m tooling.release.release_record <client_dir>` verifies the immutable `ReleaseRecord` and all of its evidence bindings.

Checkpoints: `staging-validated`, `candidate-authorized`, `production-released`.

## DO NOT
- Do not create, grant, rewrite, or substitute for a `ProductionAuthorization`; authorization is human/Milestone-G authority.
- Do not deploy unless the candidate matches a valid G authorization exactly.
- Do not rebuild after authorization; promote the exact staging-tested artifact.
- Do not silently alter the approved experience or reopen the C/D/E/F review authorities.
- Do not duplicate an approval, review, visual-QA, or authorization authority under `production/`.
- Do not blind-rollback the database or commit privileged secrets.

## NEXT
None — `release` is the terminal workflow stage.

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/09-release.yaml`.
