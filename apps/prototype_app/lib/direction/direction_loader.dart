import 'prototype_direction.dart';

abstract final class DirectionLoader {
  static Map<String, PrototypeDirection> defaults() {
    return {
      'a': PrototypeDirection.fromMap({
        'id': 'a',
        'name': 'Direction A',
        'strategic_goal': 'Fast known-item ordering',
        'navigation': 'search-led',
        'primary_journey': 'search-to-order',
        'discovery_model': 'sku-search',
        'merchandising': 'availability-and-price',
        'density': 'dense',
        'transaction_model': 'checkout-plus-rfq',
        'patterns': ['search', 'plp', 'pdp', 'cart', 'rfq'],
        'components': ['product-card', 'price-display', 'search-field', 'quote-card'],
      }),
      'b': PrototypeDirection.fromMap({
        'id': 'b',
        'name': 'Direction B',
        'strategic_goal': 'Repeat-order account productivity',
        'navigation': 'dashboard',
        'primary_journey': 'reorder-to-order',
        'discovery_model': 'account-history',
        'merchandising': 'reorder-and-credit',
        'density': 'balanced',
        'transaction_model': 'trade-account-ordering',
        'patterns': ['trade-dashboard', 'plp', 'cart'],
        'components': ['credit-summary', 'quote-card', 'product-card'],
      }),
      'c': PrototypeDirection.fromMap({
        'id': 'c',
        'name': 'Direction C',
        'strategic_goal': 'Complex bulk procurement',
        'navigation': 'rfq-led',
        'primary_journey': 'rfq-to-quote',
        'discovery_model': 'guided-specification',
        'merchandising': 'bulk-and-negotiated-pricing',
        'density': 'balanced',
        'transaction_model': 'rfq-first',
        'patterns': ['home', 'plp', 'pdp', 'rfq', 'trade-dashboard'],
        'components': ['product-card', 'price-display', 'quote-card', 'credit-summary'],
      }),
    };
  }

  static PrototypeDirection resolve(String id) {
    final directions = defaults();
    return directions[id] ?? directions['a']!;
  }
}
