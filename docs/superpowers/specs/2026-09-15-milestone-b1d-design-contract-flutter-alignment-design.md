# Milestone B.1D — Design Contract ↔ Flutter Alignment

## Purpose

Make `design-contract/` the explicit canonical authority for Flutter component and pattern implementations, including supported variants, states, density, and implementation bindings. B.1D builds on B.1B's canonical runtime IDs and removes remaining ad-hoc knowledge from app-local adapters.

## Current State

B.1B established that generated runtime bundles preserve canonical Design Contract IDs and that Flutter may translate them only through explicit app-boundary mappings. The current prototype has an explicit canonical pattern adapter, while `agency_flutter_ui` still exposes an internal short-key registry. Component contracts already declare metadata such as `variants`, `states`, `density`, `requires`, and `status`, but those declarations are not yet enforced against Flutter implementations.

## Authority Boundary

1. `design-contract/` is authoritative for canonical IDs and supported UX metadata.
2. Flutter registry keys, Dart class names, enum names, and widget factories are implementation details.
3. Runtime bundles must continue to carry canonical IDs unchanged.
4. Translation to Flutter implementation identifiers must be explicit and allowlisted; heuristic prefix stripping or convention-based inference is forbidden.
5. A canonical contract may exist without a Flutter implementation, but a prototype direction that references it must fail governed validation until an approved binding exists.

## Architecture

```text
design-contract/components/*.yaml
design-contract/patterns/*.yaml
            │
            ▼
Flutter Implementation Bindings
            │
            ├── canonical ID
            ├── internal registry key / implementation ID
            ├── supported variants
            ├── supported states
            └── supported density
            │
            ▼
Repository Validator
            │
            ▼
Generated client runtime bundle
            │ canonical IDs preserved
            ▼
Prototype Runtime Resolver
            │
            ▼
agency_flutter_ui implementation
```

## Implementation Binding Contract

Add machine-readable Flutter bindings under:

`design-contract/bindings/flutter/`

Each binding is keyed by canonical Design Contract ID. Example:

```yaml
id: commerce.product-card
kind: component
status: approved
implementation:
  package: agency_flutter_ui
  registry_key: product-card
  symbol: ProductCard
variants:
  standard: standard
  premium: premium
  b2b: b2b
  marketplace: marketplace
states:
  loading: supported
  normal: supported
  out-of-stock: supported
  disabled: supported
density:
  compact: compact
  normal: normal
  spacious: spacious
```

Pattern bindings use the same principle but target `PatternRegistry` internal keys.

Bindings are explicit metadata, not executable Dart generation. Flutter remains responsible for actual factories/widgets; repository validation proves the two sides agree.

## Canonical ID Resolution

B.1D replaces the prototype-only `CanonicalPatternAdapter` as the source of canonical mapping knowledge with a generated/checked projection derived from the binding catalog.

The preferred shape is:

```text
Design Contract binding YAML
        ↓
Python validation/projection
        ↓
checked generated Dart binding table
        ↓
PrototypeRegistry / agency_flutter_ui registry
```

The checked generated Dart file is deterministic and must match a fresh projection in CI. Manual edits to generated mapping output are forbidden.

## Components

For every approved component referenced by a runtime direction:

- canonical component contract must exist;
- component contract status must be `approved`;
- approved Flutter binding must exist;
- every requested runtime variant must exist in the component contract;
- every requested runtime variant must map to a Flutter-supported variant;
- requested density must be accepted by the component contract and binding;
- required component dependencies must themselves resolve to approved contracts;
- if state metadata is used by a prototype fixture/runtime path, that state must be declared and supported.

B.1D does not require all agency components to become runtime-rendered immediately. It requires governed parity for components used by the current prototype runtime.

## Patterns

For every pattern referenced by a runtime direction:

- canonical pattern contract must exist and be approved;
- an approved Flutter pattern binding must exist;
- the binding target must exist in `agency_flutter_ui`'s internal pattern registry;
- two canonical pattern IDs may not resolve to the same internal registry key unless a future explicit alias contract is introduced; B.1D introduces no aliases;
- missing implementation must fail visibly and deterministically.

## Variants

`component_variants` in the B.1A runtime direction remains the canonical client runtime input.

Resolution flow:

```text
runtime component_variants
        ↓
canonical component contract
        ↓
Flutter binding variant map
        ↓
Flutter enum/internal variant
```

Unknown or unsupported variants are validation errors before client review.

## Density

Canonical runtime density remains:

- `compact`
- `normal`
- `spacious`

Design Contract density declarations are authoritative. Flutter may map those to internal enum values, but the translation must be explicit and total for any referenced implementation.

## States

B.1D governs state capability metadata but does not introduce a new state machine. Component contracts declare supported states; bindings declare which of those states the Flutter implementation supports. Repository validation rejects contradictions.

## Validation

Add a root-aware validator that checks:

1. every binding references an existing Design Contract record;
2. binding kind matches source catalog (`component` or `pattern`);
3. source contract is approved before binding can be approved;
4. variants/states/density in a binding are subsets of the canonical contract;
5. all current runtime directions resolve every pattern/component/variant;
6. every bound internal pattern key exists in `PatternRegistry`;
7. component implementation identifiers are unique where required;
8. canonical IDs are unique;
9. deterministic generated Dart projection is fresh;
10. no heuristic canonical-ID conversion remains in runtime code.

Validation errors must be stable-sorted for deterministic CI output.

## Flutter Boundary

`agency_flutter_ui` remains generic and does not parse repository YAML at runtime.

The prototype app consumes a generated binding projection. Recommended files:

```text
apps/prototype_app/lib/registry/generated_design_bindings.dart
apps/prototype_app/lib/registry/design_contract_resolver.dart
```

The resolver accepts canonical IDs and returns governed internal implementation metadata. Unknown canonical IDs produce a governed runtime error, never a fallback.

## Migration

1. Create binding schema/catalog.
2. Seed pattern bindings for all currently implemented canonical patterns.
3. Seed component bindings for components referenced by current A/B/C runtime directions.
4. Generate deterministic Dart projection.
5. Replace hand-authored canonical pattern adapter knowledge with the generated projection/resolver.
6. Add component variant/density parity validation.
7. Keep B.1B runtime bundle shape backward-compatible; no runtime direction schema change is required.

## Testing

### Python

- valid binding catalog passes;
- missing contract fails;
- unapproved contract/binding fails;
- unsupported variant fails;
- unsupported density fails;
- duplicate/colliding implementation mapping fails;
- current runtime directions resolve successfully;
- generated Dart projection byte-matches fresh generation;
- stable error ordering regardless of YAML/map insertion order.

### Flutter

- every generated canonical pattern binding resolves to a valid `PatternRegistry` key;
- every current canonical component binding resolves to a known implementation descriptor;
- requested variants resolve correctly;
- compact/normal/spacious map explicitly;
- unknown canonical ID throws governed error;
- no silent fallback or heuristic prefix stripping.

### Full Verification

- repository validation;
- knowledge/prototype validators;
- `flutter analyze` for prototype app, shared UI package, Widgetbook;
- Flutter tests for all three packages;
- Flutter Web build.

## Non-Goals

B.1D does not:

- create a full token/theme system (B.1E);
- add visual screenshot automation;
- add new backend/data integrations;
- redesign existing widgets merely for stylistic consistency;
- render every Design Contract component dynamically;
- introduce aliases between canonical IDs;
- change the B.1A strategic direction schema.

## Success Criteria

B.1D is complete when:

1. `design-contract/` remains the single canonical authority for IDs and supported UI metadata;
2. current runtime directions can be proven to resolve to approved Flutter implementations;
3. component variants and density are validated across Design Contract → binding → Flutter;
4. canonical pattern mapping is generated from governed binding metadata rather than hand-maintained app knowledge;
5. invalid/missing bindings fail deterministically before client review;
6. Flutter runtime continues to use canonical IDs at the boundary and explicit internal IDs only after resolution;
7. repository and Flutter CI pass with deterministic parity tests.

## Dependency on Later Milestones

B.1E will build the token/theme contract on top of this governed implementation layer. Workflow Hardening is independent operationally but should follow B.1E so the transition API can validate the final design/runtime artifacts produced by both milestones.
