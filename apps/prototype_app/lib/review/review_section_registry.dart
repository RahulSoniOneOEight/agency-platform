/// One governed, reviewable section definition.
///
/// A definition is a thin adapter over existing B.1D identity: [screenId] is a
/// canonical pattern id, [componentId] is a canonical component id, and [slot]
/// names the composition slot exposed by the shared pattern. The registry is not
/// a second Design Contract and invents no identity.
final class ReviewSectionDefinition {
  const ReviewSectionDefinition({
    required this.id,
    required this.screenId,
    required this.label,
    required this.componentId,
    required this.slot,
  });

  /// Stable governed section id (e.g. `plp.product-grid`).
  final String id;

  /// Canonical pattern id this section belongs to (e.g. `commerce.plp`).
  final String screenId;

  /// Human-readable label for the review workspace.
  final String label;

  /// Canonical B.1D component id backing this slot.
  final String componentId;

  /// Short composition-slot name within the screen.
  final String slot;
}

/// Governed review-section registry.
///
/// Only sections that map to a real composition slot AND an independently
/// renderable B.1D component are registered. It renders nothing and defines no
/// parallel component library.
abstract final class ReviewSectionRegistry {
  static const List<ReviewSectionDefinition> _definitions = [
    ReviewSectionDefinition(
      id: 'home.product-grid',
      screenId: 'commerce.home',
      label: 'Product grid',
      componentId: 'commerce.product-card',
      slot: 'product-grid',
    ),
    ReviewSectionDefinition(
      id: 'plp.product-grid',
      screenId: 'commerce.plp',
      label: 'Product grid',
      componentId: 'commerce.product-card',
      slot: 'product-grid',
    ),
    ReviewSectionDefinition(
      id: 'search.search-field',
      screenId: 'commerce.search',
      label: 'Search field',
      componentId: 'commerce.search-field',
      slot: 'search-field',
    ),
    ReviewSectionDefinition(
      id: 'search.results-grid',
      screenId: 'commerce.search',
      label: 'Results',
      componentId: 'commerce.product-card',
      slot: 'results-grid',
    ),
    ReviewSectionDefinition(
      id: 'pdp.price',
      screenId: 'commerce.pdp',
      label: 'Price',
      componentId: 'commerce.price-display',
      slot: 'price',
    ),
  ];

  /// All governed section definitions in deterministic declaration order.
  static List<ReviewSectionDefinition> get all =>
      List<ReviewSectionDefinition>.unmodifiable(_definitions);

  /// Governed sections for [screenId], in deterministic declaration order.
  static List<ReviewSectionDefinition> sectionsForScreen(String screenId) =>
      List<ReviewSectionDefinition>.unmodifiable(
        _definitions.where((definition) => definition.screenId == screenId),
      );

  /// The definition for [sectionId], or `null` when unknown.
  static ReviewSectionDefinition? definition(String sectionId) {
    for (final definition in _definitions) {
      if (definition.id == sectionId) {
        return definition;
      }
    }
    return null;
  }
}
