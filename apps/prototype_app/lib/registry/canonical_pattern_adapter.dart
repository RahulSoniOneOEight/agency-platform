/// Explicit, allowlisted mapping from canonical B.1A pattern IDs to internal
/// `agency_flutter_ui` registry keys.
///
/// Canonical IDs are the cross-boundary contract and are preserved unchanged in
/// generated bundles. This adapter is the only place where an app-specific
/// translation happens. Heuristic prefix stripping is forbidden, and two
/// canonical IDs must never map to the same internal key.
abstract final class CanonicalPatternAdapter {
  static const Map<String, String> canonicalToRegistry = {
    'commerce.home': 'home',
    'commerce.search': 'search',
    'commerce.plp': 'plp',
    'commerce.pdp': 'pdp',
    'commerce.cart': 'cart',
    'commerce.rfq': 'rfq',
    'commerce.reorder': 'reorder',
    'commerce.trade-dashboard': 'trade-dashboard',
  };

  static Iterable<String> get canonicalIds => canonicalToRegistry.keys;

  static String toRegistryKey(String canonicalId) {
    final key = canonicalToRegistry[canonicalId];
    if (key == null) {
      throw ArgumentError.value(
        canonicalId,
        'canonicalId',
        'No Flutter implementation for canonical pattern',
      );
    }
    return key;
  }
}
