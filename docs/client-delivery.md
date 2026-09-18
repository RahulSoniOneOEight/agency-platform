# Client Delivery Model

## Composition

Future client applications should be assembled as:

```text
Agency Flutter UI
      +
Starter
      +
Reference / Asset Library
      +
Client Theme
      +
Selected UX Variants
      +
Client-specific workflows
      =
Client App
```

## Delivery principles

- Do not start every project from a blank `flutter create` application once a suitable starter exists.
- Reuse the agency Flutter UI package before introducing client-local components.
- Keep brand differences in themes/tokens where possible.
- Use controlled pattern/component variants for meaningful UX alternatives.
- Create client-local code only for genuinely unique requirements.
- Feed reusable improvements back into the agency layer when they generalize beyond one client.

## Client review

Penpot may be used for selected client-facing design files or prototypes, but it is not the production source of truth. Flutter remains the complete working implementation.

## Productionization (stage 08)

`08-productionize.md` hardens the approved client experience into production
software: provider-neutral production ports, a reference Supabase/Postgres +
Supabase Auth adapter, deterministic fake ERP/payment/shipping/CRM/WhatsApp
adapters, validated dev/staging/production configuration, versioned migrations,
and production-path tests.

Completion of stage 08 is **production-capable** — it is **not** production
authorized and **not** deployed. Stage 08 performs no production deployment and
cannot create or rewrite a `ProductionAuthorization`. It writes the deterministic
H.1 foundation evidence to
`client-projects/<client>/production/evidence/h1-foundation-report.json` and
routes to stage 09 `release`.

## Release lifecycle (stage 09)

`09-release.md` is the H.2B authorized release lifecycle. It is a single,
staging-first, no-rebuild sequence:

```text
exact candidate build
→ staging deploy
→ H.2A hardening gates (security, performance, accessibility, analytics,
  observability, migrations) + staging smoke
→ candidate freeze (source SHA + artifact digest + migration set + config identity)
→ exact human Milestone-G ProductionAuthorization
→ production promotion of the exact staging-tested artifact (no rebuild)
→ production smoke
→ bounded telemetry health window
→ immutable ReleaseRecord
```

Rules:

- Stage 09 consumes H.1 foundation evidence, H.2A hardening evidence, and the
  exact G authorization; it never creates, grants, or mutates an authorization.
- Authorization remains human/Milestone-G authority. The reference proof uses a
  synthetic human authorization fixture bound to the exact candidate, committed
  under `release/reference-proof/` as a permission artifact — never under
  `production/` and never inside the G authorization area.
- A new source SHA, artifact digest, migration set, environment, or
  release-relevant configuration identity is a different candidate and requires
  new hardening evidence and a new G authorization.
- Workflow-state authority remains with `tooling.workflow.runner`; stage 09
  completes only after the `h2-hardening`, `production-authorization`, and
  `h2-release-record` validators pass, at checkpoints `staging-validated`,
  `candidate-authorized`, and `production-released`.
- The immutable release evidence is
  `client-projects/<client>/production/evidence/release-record.json`.
- Healthy, degraded, and failed outcomes are explicit; degraded/failed releases
  retain incident/advisory evidence and route through governed recovery. Blind
  database rollback is prohibited.
- Normal CI requires no production credentials; privileged provider credentials
  remain CI/server secrets.
