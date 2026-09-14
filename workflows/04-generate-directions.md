# Generate Experience Directions

Detailed operating stages: **7. Generate experience directions** + **8. Validate directions**.

## PURPOSE
Generate the best 2–3 client-specific product strategies from canonical client context and shared agency intelligence, then validate that they are coherent and materially distinct.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/derived/resolved-presets.yaml`
- `client-projects/<client>/derived/intelligence-map.yaml`
- `client-projects/<client>/derived/capability-map.yaml`
- `client-projects/<client>/derived/gaps.yaml`
- `client-projects/<client>/resources/selection.yaml` when present
- `experience-patterns/`
- `design-contract/`
- `presets/`
- `templates/direction.yaml`
- `templates/direction-comparison.yaml`

## PROCESS
1. Generate 6–10 relevant candidate experience strategies.
2. Adapt candidates to objectives, personas, jobs, business model, industry, use cases, constraints, gaps, and available resources.
3. Score candidates for client fit, objective fit, persona/JTBD fit, business/industry fit, feasibility, agency reuse, accessibility, and resource availability.
4. Reject low-fit candidates.
5. Enforce strategic diversity across information architecture, primary journey, navigation, discovery/merchandising, interaction model, transaction model, density, personalization, or procurement/service logic.
6. Select the best three when three materially different viable strategies exist; otherwise select two and explain why.
7. State rationale, strengths, trade-offs, risks, success metrics, and implementation implications.
8. Validate each direction against the direction contract and implementation registries before advancing.

## WRITE
- `client-projects/<client>/directions/direction-a.yaml`
- `client-projects/<client>/directions/direction-b.yaml`
- `client-projects/<client>/directions/direction-c.yaml` when three are selected
- `client-projects/<client>/directions/comparison.yaml`

## VALIDATE
- Direction files use the canonical template structure.
- Selected directions are materially different strategies, not visual variants.
- References to Design Contract elements/resources resolve.
- `tooling/knowledge/direction_engine.py` and `tooling/prototype/validate_direction.py` contracts pass where applicable.

## DO NOT
- Do not force Discovery-first, Search-first, or Trade-first merely because they are default archetypes.
- Do not create theme/color-only alternatives.
- Do not begin Flutter implementation in this stage.

## NEXT
`05-build-prototype.md`
