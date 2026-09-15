# Client Runtime Loading (B.1B)

Milestone B.1B makes the single shared Flutter prototype app load generated,
client-specific runtime bundles instead of hard-coded demo directions, fixtures,
theme, and resource bindings.

## Flow

```text
client artifacts (directions + fixtures + B.1C resources)
→ tooling/prototype/build_prototype.py (compose_prototype)
→ client-projects/<client>/prototype/prototype-manifest.yaml
→ tooling/prototype/build_runtime_bundle.py
→ apps/prototype_app/assets/generated/<client-id>.json
→ Flutter RuntimeLoader
→ ?client=<client-id>&direction=<direction-id>
```

Generation is build-time. The Flutter prototype never reads repository YAML and
never calls external providers; it consumes only the generated JSON bundle.

## Bundle contract

Each bundle is one self-contained JSON document:

```json
{
  "version": 1,
  "client_id": "prototype-demo",
  "default_direction": "a",
  "directions": {
    "a": {
      "id": "a",
      "name": "Search-led Trade",
      "strategic_goal": "reduce known-item order time",
      "navigation_model": "search-led",
      "primary_journey": "search-to-order",
      "discovery_model": "sku-search",
      "merchandising_model": "availability-and-price",
      "density": "compact",
      "transaction_model": "checkout-plus-rfq",
      "patterns": ["commerce.search", "commerce.plp"],
      "components": ["commerce.product-card"],
      "component_variants": [{"component": "commerce.product-card", "variant": "b2b"}],
      "required_resources": []
    }
  },
  "fixtures": {"products": [], "services": []},
  "theme": {"seed_color": "#6750A4"},
  "resources": {},
  "review": {"query_parameter": "direction", "allowed_directions": ["a", "b"]}
}
```

- Direction fields use the B.1A canonical runtime contract. Density vocabulary
  is `compact | normal | spacious`; the Flutter app maps these to its internal
  `AgencyDensity` values.
- `patterns` and `components` are canonical Design Contract IDs, copied
  unchanged. Generation never rewrites them to Flutter implementation keys.
- `resources` carries canonical B.1C bindings keyed by semantic IDs such as
  `asset.home.hero`, `icon.commerce.cart`, and `motion.checkout.success`.
  `resources.direction_overrides.<direction-id>.<canonical-resource-id>` is
  preserved alongside the base bindings.
- A valid client declares exactly two or three directions; A and B are mandatory
  and C is optional.

## URL contract

```text
/?client=<client-id>&direction=<direction-id>
```

- `client` selects the generated bundle `assets/generated/<client-id>.json`.
  When omitted, the app uses the checked-in regression client `prototype-demo`.
  This is a declared local default, not a fallback for invalid client IDs.
- `direction` selects a direction declared by that client. When omitted, the
  client's `default_direction` is used.
- An explicitly supplied unknown client or direction shows a governed error
  screen. The app never silently switches to Direction A.

## Error behavior

Runtime loading failures surface through typed `RuntimeException` codes:

- `client_not_found` — the bundle asset is missing, or the client ID is unsafe.
- `invalid_bundle` — malformed JSON, non-object root, invalid bundle shape, or a
  bundle whose `client_id` does not match the requested client.
- `direction_not_found` — the requested direction is not declared by the client.

The error screen shows the requested client/direction and a concise remediation
message. Stack traces are never shown to client reviewers.

## Determinism and validation

- `build_runtime_bundle.py` writes UTF-8 JSON with `indent=2`, `sort_keys=True`,
  LF newlines, and a trailing newline, so repeated runs are byte-identical.
- `validate_runtime_bundle(bundle)` is the intrinsic, repository-independent
  bundle validator. `validate_runtime_bundle_against_design_contract(root, bundle)`
  is the root-aware validator that resolves every referenced pattern, component,
  and component variant against the authoritative `design-contract/` catalogs at
  the supplied repository root.
- Repository validation (`tooling/validation/validate_repo.py`) checks every
  client whose prototype manifest exists: the generated bundle must exist, pass
  both validators, and be identical to a fresh projection of the strategic
  sources. Stale checked-in bundles fail validation.

## Canonical pattern adapter

Generated bundles keep canonical pattern IDs. The only app-specific translation
lives in `apps/prototype_app/lib/registry/canonical_pattern_adapter.dart`, an
explicit allowlisted canonical-to-internal map (for example the canonical
pattern `commerce.plp` maps to the internal `plp` registry key). Heuristic
prefix stripping is forbidden, two canonical IDs must not collide on one
internal key, and a valid canonical ID with no Flutter implementation fails
visibly.

## Regenerating a client bundle

```text
python -m tooling.prototype.build_prototype   # composes manifest + generated bundle
python tooling/validation/validate_repo.py    # proves bundles exist, validate, and are fresh
```
