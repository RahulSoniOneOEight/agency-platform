# Resource Intelligence

## B.1C high-impact resource selection

B.1C turns the existing resource registry and Workflow 03 policy into an executable selection pipeline.

### Core rule
Client-first provenance does not mean client-only selection. Identity-critical assets such as logos, SKU imagery, and seller marks are authoritative. High-impact creative surfaces such as heroes, campaign banners, and important category imagery may use comparative or discovery research even when client assets exist.

### Sourcing modes
- `authoritative`: client/official/agency-authorized only.
- `prefer_client`: prefer a suitable client asset; research alternatives when fit/quality is insufficient.
- `comparative`: compare client, agency, and approved external candidates.
- `discovery`: actively research approved sources for differentiated options.

### Main artifacts
- `client-projects/<client>/derived/resource-requirements.yaml`
- `client-projects/<client>/resources/candidates.yaml`
- `client-projects/<client>/resources/selection.yaml`
- `client-projects/<client>/resources/provenance.yaml`

### Provider behavior
Pexels is governed by `resources/registry/providers/pexels.yaml`. The executable adapter reads `PEXELS_API_KEY` from the environment. The key must never be committed. CI uses injected fixtures and does not call Pexels.

Icons and motion are deterministic registries rather than arbitrary internet searches:
- `resources/registry/icons/semantic-icons.yaml`
- `resources/registry/motion/motion-assets.yaml`

### Runtime binding
Selected provider-specific candidates are normalized to stable semantic IDs such as:
- `asset.home.hero`
- `asset.brand.logo`
- `icon.commerce.cart`
- `motion.checkout.success`

`tooling/prototype/build_prototype.py` adds these bindings to the client prototype manifest after validating the B.1C artifacts.

### Execution flow

```text
input assets / references
-> derived resource requirements
-> sourcing policy + provider router
-> normalized candidates
-> deterministic scoring / selection
-> provenance validation
-> canonical resource bindings
-> prototype manifest
-> Flutter runtime
```
