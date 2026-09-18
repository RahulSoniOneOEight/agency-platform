# Milestone H.2 — SDD Progress Ledger

Plan: `docs/superpowers/plans/2026-09-18-milestone-h2-production-hardening-authorized-release-implementation.md`
Spec: `docs/superpowers/specs/2026-09-18-milestone-h2-production-hardening-authorized-release-design.md`
Branch: `milestone-h2-production-hardening-release`
Base: `b3b18ff1877e72447381c3e7bdfaf31889616f78` (H.2 design + plan docs on top of H.1 `2ab3243`)

## Execution model

Subagent-driven development: one fresh implementer per task, an independent
reviewer after every task (spec-compliance verdict + code-quality verdict), a
scoped fix loop with re-review, and one whole-branch review at the end.

**Routing deviation:** only `general`/`explore` subagents are exposed in this
session. The plan's `@strategy` / `@builder` / `@worker` / `@reviewer` model
routing is approximated with fresh `general` implementers and separate fresh
`general` reviewers. No implementer ever reviews its own task. This mirrors the
recorded H.1 deviation.

## Task status

| Task | Title | Status | Commit | Tests | Review |
|------|-------|--------|--------|-------|--------|
| 1 | Provider-neutral operations core | pending | | | |
| 2 | ReleaseCandidate + ReleaseRecord models | pending | | | |
| 3 | Sentry / GA4 / Cloudflare reference adapters | pending | | | |
| 4 | Hardening policies + validators | pending | | | |
| 5 | Candidate build manifest + artifact integrity | pending | | | |
| 6 | Hardening gates | pending | | | |
| 7 | Staging deployment, smoke, hardening report | pending | | | |
| 8 | Bridge H.2 candidate to G authorization | pending | | | |
| 9 | Production release, smoke, telemetry, ReleaseRecord | pending | | | |
| 10 | Recovery coordinator | pending | | | |
| 11 | Production-release workflow + no-rebuild | pending | | | |
| 12 | Workflow integration + authority boundaries | pending | | | |
| 13 | Reference-commerce e2e proof | pending | | | |
| 14 | Regression, whole-branch review, ledger, PR | pending | | | |

## Preflight interface scan (completed)

- Toolchain: Python 3.12.10 (`py -3.12`), Flutter 3.47.4 stable, Dart 3.13.3.
- G release gate: `tooling.production_authorization.release_gate.verify_release_gate(authorization, candidate, invalidation_events=()) -> None`; pass/fail by exception. H.2 MUST call it and MUST NOT call `ProductionAuthorizationCoordinator.authorize` or `FileProductionAuthorizationRepository.create`.
- G candidate identity = full canonical JSON of all candidate fields (pretty, sorted). No expiry concept.
- H.1 identity convention: compact canonical JSON (`sort_keys=True, separators=(",", ":")`) + `sha256:` prefix, stripping the identity key. Copy-per-module (no shared helper).
- Hardening evidence dir: `client-projects/reference-commerce/production/evidence/` (currently only `h1-foundation-report.json`).
- Config allowlist: `tooling.production.validate_config.ALLOWED_KEYS`; forbidden fragments list.
- Migrations: `supabase/migrations/*.sql`, 12–14 digit version, `-- migration-class:` header.
- Workflow runtime: stage list is fixed at 8 in `tooling/workflow/state.py::STAGES`; stage-09 requires edits to state, schema (2 enums), router, validate_workflow, 08 contract/MD, and the fixed-eight tests.
- CI: `validate.yml` has a single long unittest line (must append new modules) plus per-validator steps; `flutter-ci.yml` auto-discovers packages under `packages/**` via `find`.
- New Dart packages auto-included by `melos.yaml` glob; no `pubspec.lock` is ever committed.

## Rulings / deviations

- **R1 (routing):** `general` subagents used for both implementer and reviewer roles; recorded deviation above.
- **R2 (synthetic authorization fixture):** the H.2 reference proof requires a new explicit synthetic-human G authorization fixture bound to the exact H.2 candidate (spec §22, AC 42). It is a static data fixture representing a human release-owner action; no H.2 code path may create, grant, or mutate `ProductionAuthorization` (AC 39). `tooling/release` must not import `ProductionAuthorizationCoordinator` or the repository `create`.
- **R3:** TBD as tasks progress.

## Reviewer findings / fix loop

TBD as tasks progress.
