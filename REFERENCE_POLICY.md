# Reference Policy

## Purpose

This policy controls how external references enter the agency platform. External material is a source of ideas and reusable structure, not production code by default.

## Supported sources

- GitHub repositories and code references
- `pub.dev` packages
- Penpot files, components, patterns, and UI kits
- icon libraries
- images and illustrations
- motion/animation libraries
- screenshots and UX examples

## Required lifecycle

Every new external reference follows this path:

```text
external source
→ resources/incoming/
→ review
→ resources/approved/ OR resources/rejected/
→ normalization
→ design contract / agency_flutter_ui
→ client usage
```

Registry metadata belongs under `resources/registry/`.

## Mandatory review

Before approving a reference, evaluate:

1. license and permitted commercial use
2. Flutter compatibility where relevant
3. dependency quality and maintenance health
4. maintainability and implementation complexity
5. duplication with existing agency components or patterns
6. visual and UX usefulness
7. accessibility implications
8. whether the reference can be generalized beyond one client

## Approval does not mean production-ready

An approved reference must still be normalized before it enters `packages/agency_flutter_ui/` or a client project.

Normalization should:

- keep the useful structure, interaction, or idea
- remove source-specific styling and unnecessary dependencies
- map colors to agency color tokens
- map spacing to agency spacing tokens
- map typography to agency typography tokens
- map radius/elevation to agency tokens
- map icons to agency icon rules
- map imagery to agency image rules
- map motion to agency motion rules
- generalize the component API
- decide whether the result is reuse, extension, a variant, or a genuinely new component

## Prohibited shortcut

Never copy an external component directly into `client-projects/`.

If an external component is useful, normalize it first and place the reusable result in the shared agency system before client consumption unless the implementation is demonstrably client-specific.

## Relationship to AGENTS.md

`AGENTS.md` is the master agent operating contract. Agents performing reference discovery, evaluation, adoption, or normalization must read and follow this file before implementation.
