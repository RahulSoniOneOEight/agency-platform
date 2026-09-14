# Milestone B.1C Resource Selection Design

## Goal
Make Resource Intelligence executable so OpenCode can derive, research, compare, select, normalize, and bind high-impact assets into client prototypes while preserving provenance and client/source truth.

## Design principles
- Client-first provenance does not mean client-only selection.
- Authoritative identity assets (logos, SKU images, seller marks) stay client/official-source controlled.
- High-impact visual surfaces (hero, campaign banner, important category imagery) may trigger comparative research even when client assets exist.
- Flutter consumes canonical semantic asset IDs, not raw provider URLs.
- External API credentials never enter Git; Pexels uses `PEXELS_API_KEY` from the environment.
- CI validates deterministic artifacts and never calls external providers.

## Sourcing modes
- `authoritative`: client/official source only.
- `prefer_client`: use client unless quality/fit is materially weak.
- `comparative`: compare client, agency, and approved external candidates.
- `discovery`: actively research alternatives because the experience direction benefits from exploration.

Default policy examples:
- brand logo, product image, seller logo -> authoritative
- home hero, campaign banner, high-impact category imagery -> comparative
- supporting category imagery -> prefer_client
- editorial imagery -> discovery
- icons -> agency semantic registry
- motion -> agency registry/discovery with approved local Lottie/Rive assets

## Data flow

```text
client input/assets + references
        -> derived/resource-requirements.yaml
        -> Workflow 03 Resource Research
        -> client/agency/provider candidate resolvers
        -> resources/candidates.yaml
        -> scoring + selection
        -> resources/selection.yaml
        -> resources/provenance.yaml
        -> normalization to canonical IDs
        -> prototype manifest/runtime binding
        -> Flutter prototype
```

## Repository impact

### Agency resource intelligence
- `resources/registry/providers/pexels.yaml` remains the Pexels governance entry.
- `resources/registry/icons/semantic-icons.yaml` stores canonical semantic icon mappings.
- `resources/registry/motion/motion-assets.yaml` stores approved local motion mappings.
- `resources/registry/schema/` gains resource requirement, candidate, selection, and provenance schemas.
- `resources/policies/sourcing-policy.yaml` owns sourcing mode rules and default asset-role policy.

### Executable tooling
Create `tooling/resources/` with focused modules:
- `requirements.py`: requirement loading/validation helpers.
- `provider_router.py`: determine allowed source routes from sourcing mode/policy.
- `client_assets.py`: normalize client asset-manifest entries into candidate records.
- `pexels_client.py`: search Pexels via `PEXELS_API_KEY`; return normalized candidate records.
- `icon_resolver.py`: resolve canonical semantic icon IDs from approved provider registry.
- `motion_resolver.py`: resolve canonical motion IDs from the approved local registry.
- `scorer.py`: deterministic baseline candidate scoring from declared fit/quality/provenance fields.
- `selector.py`: choose primary and fallback candidates while respecting sourcing mode.
- `normalizer.py`: produce canonical semantic resource bindings.
- `validate_resources.py`: enforce contracts, allowed provider status, provenance, critical coverage, and binding integrity.

### Per-client artifacts
- `derived/resource-requirements.yaml`: OpenCode-generated semantic requirements.
- `resources/candidates.yaml`: normalized candidate pool.
- `resources/selection.yaml`: selected primary/fallback per semantic role and optional direction-specific overrides.
- `resources/provenance.yaml`: traceable provider/source metadata.
- `resources/generated/`: downloaded/normalized prototype-ready files when needed.

### Workflow/runtime integration
- `workflows/02-resolve-intelligence.md`: derive likely resource needs/gaps without searching.
- `workflows/03-resource-research.md`: execute requirement -> route -> candidate -> score -> select -> provenance -> normalize.
- `workflows/04-generate-directions.md`: allow directions to reference resource readiness and direction-specific needs.
- `workflows/05-build-prototype.md`: require critical resource selections before prototype readiness.
- `tooling/prototype/build_prototype.py`: include normalized resource bindings in the prototype manifest when available.

## Candidate model
Candidates from client assets, agency registry, and Pexels share one contract. Required fields include stable ID, resource type, source/provider, semantic role, fit metadata, quality metadata, and provenance status. This lets the selector compare sources without provider-specific branches.

## Scoring
Baseline deterministic weighting for imagery:
- direction/experience fit: 25%
- semantic relevance: 20%
- composition/layout fit: 15%
- brand fit: 10%
- technical quality: 10%
- provenance/license: 10%
- cross-screen/set consistency: 10%

`prefer_client` may add a bounded client preference bonus. `comparative` and `discovery` never stop merely because a client candidate exists.

## Pexels
- Provider metadata remains under `resources/registry/providers/pexels.yaml`.
- The executable adapter reads `PEXELS_API_KEY` from environment only.
- Missing credentials produce a controlled provider-unavailable result, not a crash or secret fallback.
- Search results are normalized; raw Pexels provider IDs/URLs are never the Flutter-facing contract.

## Canonical runtime IDs
Examples:
- `asset.home.hero`
- `asset.category.mobile`
- `asset.banner.trade-in`
- `icon.commerce.cart`
- `icon.trade.rfq`
- `motion.checkout.success`

The runtime binds canonical IDs to local prototype assets or approved package/provider descriptors.

## Validation gates
Fail when:
- a critical requirement has no valid selection,
- a selected external resource lacks provenance,
- a selected provider is blocked,
- an authoritative requirement selects an unauthorized source,
- a selection references an unknown candidate,
- canonical IDs collide,
- prototype runtime references an unknown resource.

CI must not call Pexels or any network provider.

## Scope
### In B.1C
- requirement/selection/provenance contracts
- sourcing modes and routing
- client asset candidate resolver
- Pexels adapter
- semantic icon registry/resolver
- local motion registry/resolver
- deterministic scoring/selection
- normalization
- workflow integration
- prototype manifest resource bindings
- validation/tests/docs

### Deferred
- Maps, YouTube/social providers
- external Lottie marketplace search
- DAM/PIM/ERP media synchronization
- 3D assets
- AI image generation
- production CDN/upload pipeline
