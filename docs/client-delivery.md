# Client Delivery Model

## Composition

Future client applications should be assembled as:

```text
Agency Flutter UI
      +
Starter
      +
Reference / Asset Library
      +
Client Theme
      +
Selected UX Variants
      +
Client-specific workflows
      =
Client App
```

## Delivery principles

- Do not start every project from a blank `flutter create` application once a suitable starter exists.
- Reuse the agency Flutter UI package before introducing client-local components.
- Keep brand differences in themes/tokens where possible.
- Use controlled pattern/component variants for meaningful UX alternatives.
- Create client-local code only for genuinely unique requirements.
- Feed reusable improvements back into the agency layer when they generalize beyond one client.

## Client review

Penpot may be used for selected client-facing design files or prototypes, but it is not the production source of truth. Flutter remains the complete working implementation.

## Productionization

Later phases will add technical hardening, automated tests, visual QA, CI gates, and release workflows. Step 1 only establishes repository structure and governance.
