# B.1B Runtime Binding Boundaries

- **Status:** Approved clarification
- **Date:** 2026-09-15
- **Scope:** Milestone B.1B generated runtime bundles and Flutter runtime parsing

## Ruling

Generated bundles preserve canonical B.1A pattern IDs unchanged. The authoritative Flutter adapter belongs at the app boundary in `apps/prototype_app/lib/registry/canonical_pattern_adapter.dart`, immediately before `PrototypeRegistry` dispatches to internal `agency_flutter_ui` registry keys. It must be an explicit allowlisted canonical-to-internal map; identity entries are allowed, heuristic prefix stripping is forbidden, and two canonical IDs must not map to the same internal key.

Within `resources`, only the top-level `direction_overrides` key is excluded from the base binding map. Every base canonical entry is parsed as a `ResourceBinding`; every nested `resources.direction_overrides.<direction-id>.<canonical-resource-id>` entry is preserved and also parsed as a `ResourceBinding`. Override direction IDs must exist in the bundle's `directions`; malformed override groups or nested bindings fail bundle parsing. Selecting or merging base and override bindings remains outside B.1B.

## Rationale

Canonical IDs are the cross-boundary contract and remain independent of Flutter implementation names. An app-layer allowlist isolates internal widget keys while preserving deterministic artifacts. Typed parsing of both resource levels preserves the complete B.1C shape without treating its structural key as a resource.

## Rejected Alternative

Rewriting canonical pattern IDs during bundle generation to match Flutter registry keys was rejected. It would couple the generated contract to one consumer, obscure provenance, and create contract drift between B.1A artifacts and the runtime bundle.

## Consequences

- Bundle generation copies canonical pattern IDs without renaming them.
- Adapter tests cover every supported canonical ID, assert mapping uniqueness, and require unsupported but valid canonical IDs to fail visibly as missing Flutter implementations.
- Upstream validation rejects malformed or noncanonical IDs; that contract error remains distinct from a valid canonical ID lacking a Flutter implementation.
- Resource tests cover base and nested bindings, unknown override direction IDs, and malformed nested bindings.
- Existing docs and tests that describe short internal registry keys as canonical must be reconciled during B.1B implementation and documentation.

This clarification preserves the approved architecture: canonical generation stays in Python, app-specific translation stays in Flutter, shared UI registry keys remain internal, and B.1B only parses and exposes B.1C bindings.

## Addendum (2026-09-15): Repository-Aware Contract Resolution

At the caller-supplied repository root, the `design-contract/patterns/` and `design-contract/components/` catalogs are authoritative for canonical pattern and component IDs. Every runtime direction `patterns` entry must resolve to an eligible pattern contract, and every `components` entry plus every `component_variants[].component` reference must resolve to an eligible component contract. Flutter registry entries are implementation bindings only and do not create canonical IDs.

Repository-aware validation must receive the repository root explicitly; it must not infer a checkout from `__file__`. Preserve `validate_runtime_bundle(bundle) -> list[str]` as the intrinsic, repository-independent bundle validator, and add a separate root-aware validation boundary for builder and repository validation paths.

The `prototype-demo` short IDs `cart`, `reorder`, and `trade-dashboard` are baseline contract inconsistencies. They require approved namespaced Design Contract entries and regeneration of derived runtime artifacts from their strategic sources, not heuristic prefixing. Adding those three contracts is a governed prerequisite and explicit scope deviation that preserves the approved demo strategy and B.1B architecture; it does not authorize any new widget or component implementation.

The resource-binding ruling above remains unchanged.
