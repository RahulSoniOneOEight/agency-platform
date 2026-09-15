# B.1B Runtime Binding Boundaries

- **Status:** Approved clarification
- **Date:** 2026-09-15
- **Scope:** Milestone B.1B generated runtime bundles and Flutter runtime parsing

## Ruling

Generated bundles preserve canonical B.1A pattern IDs unchanged. Flutter owns an explicit adapter from those canonical IDs to the existing internal widget registry keys.

Within `resources`, `direction_overrides` is reserved structural metadata. It is not parsed as a base `ResourceBinding`; only canonical base resource entries are.

## Rationale

Canonical IDs are the cross-boundary contract and must remain stable independently of Flutter implementation names. Keeping translation in Flutter isolates internal registry details while preserving deterministic generated artifacts. Treating `direction_overrides` as structural metadata also preserves the B.1C resource shape and prevents a control object from being mistaken for a semantic resource binding.

## Rejected Alternative

Rewriting canonical pattern IDs during bundle generation to match Flutter registry keys was rejected. It would couple the generated contract to one consumer, obscure provenance, and create contract drift between B.1A artifacts and the runtime bundle.

## Consequences

- Bundle generation copies canonical pattern IDs without renaming them.
- Flutter maintains and tests the canonical-to-internal pattern adapter.
- Resource parsing excludes `resources.direction_overrides` from the base binding map and handles it only as reserved structural metadata.
- Unknown canonical pattern IDs and malformed resource structures remain explicit validation or runtime errors rather than implicit rewrites.

This ruling preserves, rather than changes, the approved B.1B architecture.
