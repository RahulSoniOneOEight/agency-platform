# Reference Policy

## Purpose

The reference pool accelerates delivery without allowing external code, styling, or dependencies to bypass agency governance.

## Lifecycle

### `resources/incoming/`
New, unreviewed references enter here or are registered here by metadata/link.

### `resources/approved/`
References that have passed review and may inform normalization or implementation.

### `resources/rejected/`
References that should not be reused, with the rejection reason retained in registry metadata when appropriate.

### Categorized resource folders
`github/`, `penpot/`, `icons/`, `images/`, and `motion/` organize reusable reference material by source/type. Approval state still governs whether something may influence production work.

### `resources/registry/`
Future machine-readable and human-readable metadata about provenance, license, status, intended use, and replacement/duplication relationships.

## Review criteria

Before approval, check:

- license and redistribution/use constraints;
- Flutter compatibility where applicable;
- dependency quality;
- maintainability;
- visual usefulness;
- duplication with existing agency components/patterns.

## Adoption rule

Approval does not mean direct copying. Adopted references pass through normalization:

1. Keep the useful structure/idea.
2. Remove source-specific styling and unnecessary dependencies.
3. Map design decisions to agency token/rule concepts.
4. Generalize the API.
5. Add only the normalized result to the agency system.

External references never go directly into `client-projects/`.
