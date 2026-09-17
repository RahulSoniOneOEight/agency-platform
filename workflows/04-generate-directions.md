# Generate Experience Directions

## PURPOSE
Generate the best 2–3 client-specific product strategies from the client context and shared agency intelligence.

## READ
- `client-projects/<client>/derived/client-profile.yaml`
- `client-projects/<client>/resolved-intelligence.yaml`
- `client-projects/<client>/derived/resource-requirements.yaml` when present
- `client-projects/<client>/resources/selection.yaml` when present
- `experience-patterns/`
- `design-contract/`
- `presets/`
- `templates/direction.yaml`
- `templates/direction-comparison.yaml`

## PROCESS
1. Generate 6–10 relevant candidate experience strategies.
2. Adapt each candidate to the actual client objectives, personas, jobs, business model, industry, use cases, constraints, and available resources.
3. Score candidates for client fit, objective fit, persona/JTBD fit, business/industry fit, feasibility, agency reuse, accessibility, and resource availability.
4. Reject low-fit candidates.
5. Enforce strategic diversity across information architecture, primary journey, navigation, discovery/merchandising, interaction model, transaction model, density, personalization, or procurement/service logic.
6. Select the best three when three materially different viable strategies exist; otherwise select two and explain why.
7. State rationale, strengths, trade-offs, risks, success metrics, and implementation implications.
8. Where directions need materially different high-impact imagery or motion, record direction-specific resource implications without bypassing the B.1C selection/provenance contracts.

## WRITE
- `client-projects/<client>/directions/direction-a.yaml`
- `client-projects/<client>/directions/direction-b.yaml`
- `client-projects/<client>/directions/direction-c.yaml` when three are selected
- `client-projects/<client>/directions/comparison.yaml`

## VALIDATE
- Direction files must use the canonical template structure.
- Selected directions must be materially different strategies.
- References to design-contract elements/resources must resolve.

## DO NOT
- Do not force Discovery-first, Search-first, or Trade-first merely because they are default archetypes.
- Do not create theme/color-only alternatives.
- Do not begin Flutter implementation in this stage.
- Do not embed raw provider URLs or bypass resource provenance in directions.

## NEXT
`05-build-prototype.md`

## RUNTIME
Execute through `tooling.workflow.runner`; the machine-readable contract is `workflows/contracts/04-generate-directions.yaml`.
