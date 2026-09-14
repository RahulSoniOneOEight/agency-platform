class AgencyPatternSpec {
  const AgencyPatternSpec(this.id, this.label);

  final String id;
  final String label;
}

abstract final class PatternRegistry {
  static const Map<String, AgencyPatternSpec> _patterns = {
    'home': AgencyPatternSpec('home', 'Home'),
    'search': AgencyPatternSpec('search', 'Search'),
    'plp': AgencyPatternSpec('plp', 'Product listing'),
    'pdp': AgencyPatternSpec('pdp', 'Product detail'),
    'cart': AgencyPatternSpec('cart', 'Cart'),
    'checkout': AgencyPatternSpec('checkout', 'Checkout'),
    'quick-order': AgencyPatternSpec('quick-order', 'Quick order'),
    'rfq': AgencyPatternSpec('rfq', 'Request for quote'),
    'trade-dashboard': AgencyPatternSpec('trade-dashboard', 'Trade dashboard'),
    'reorder': AgencyPatternSpec('reorder', 'Reorder'),
    'booking': AgencyPatternSpec('booking', 'Booking'),
  };

  static AgencyPatternSpec resolve(String id) {
    final value = _patterns[id];
    if (value == null) throw ArgumentError.value(id, 'id', 'Unknown agency pattern');
    return value;
  }

  static Iterable<String> get ids => _patterns.keys;
}
