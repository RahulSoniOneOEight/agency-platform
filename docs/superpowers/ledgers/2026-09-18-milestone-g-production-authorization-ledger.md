# SDD ledger — plan: docs/superpowers/plans/2026-09-18-milestone-g-production-authorization-implementation.md

- 2026-09-18 — G planning checkpoint. Milestone F PR #23 merged at `1d81ff107568c6f06ed4c7e3e7b0c2207d6e11f9`.
- Ruling RG1: G core is implemented in Python under `tooling/production_authorization/` because production release authorization is a repository/CI control-plane concern and F evidence is already machine-readable Python/JSON; Flutter review authorities remain untouched. Cost if wrong: H may later need a thin Dart/UI adapter, but authority remains reusable.
- Ruling RG2: The F machine report is supporting regression evidence, not ApprovalSnapshot authority. The release candidate pins approval version/hash/source identity explicitly. Cost if wrong: real-client integration will require the canonical ApprovalRepository adapter in H/production tooling.
- Ruling RG3: Reference-commerce may commit a deterministic synthetic authorization fixture proving the model, but real-client authorization creation remains human-only and never occurs in CI.
