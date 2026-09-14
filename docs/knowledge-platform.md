# Knowledge Platform

Milestone A turns the Step-2 operating policies into machine-readable agency knowledge that OpenCode can validate and compose.

## Four core layers

### Design Intelligence

Stored in:
- `design-contract/`
- `presets/`

Design contracts describe canonical components, patterns, journeys, variants, states, compatibility, and selection metadata. Presets add reusable business-model, industry, and use-case context without duplicating UI.

### Resource Intelligence

Stored in:
- `resources/registry/`
- `resources/policies/`
- `tooling/normalization/`

External sources are registered, statused, license/compatibility reviewed, and normalized before shared/client use. Resource source routing prefers client-owned and agency-approved material before external providers. Provenance is required.

### Product Consulting

Stored in:
- `experience-patterns/`
- `tooling/knowledge/direction_engine.py`

Experience patterns are strategic archetypes, not templates that must be used. The engine combines client context with resolved presets and scores available archetypes. Final directions must use different strategy families so A/B/C represent materially different product approaches.

### Client Contract

Milestone A defines the client-profile input schema. A later milestone will add client selection/mixing and the final `approved-experience.yaml` contract after runnable prototypes exist.

## Current seed knowledge

- 2 reviewed Flutter references with different governance status.
- normalization manifests for those references.
- canonical commerce components, patterns, and journeys.
- 6 business-model presets.
- 12 industry presets.
- initial reusable use-case presets.
- strategic experience archetypes including discovery, search/SKU, trade, RFQ, quick-order, reorder, editorial, recommendation, comparison, guided selling, marketplace, seller trust, booking, availability, consultation, and room/use-case-led models.
- four validated client fixtures for direction-engine regression coverage.

## OpenCode flow

```text
client brief/profile
→ resolve presets
→ inspect design intelligence
→ identify resource/reference needs
→ generate candidate experience strategies
→ score client fit
→ enforce strategic diversity
→ return best 2–3 directions with rationale/trade-offs
```

Industry presets must never directly determine the three outputs. They contribute candidate knowledge to the engine.

## Validation

Run:

```bash
python -m unittest tooling.validation.test_validate_repo tooling.validation.test_knowledge_platform -v
python tooling/validation/validate_repo.py
python -m tooling.knowledge.validate_knowledge
```

CI runs these checks on pull requests.
