import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';

void main() {
  test('prototype direction parses strategy config', () {
    final direction = PrototypeDirection.fromMap({
      'id': 'a',
      'name': 'Search-led Trade',
      'strategic_goal': 'reduce order time',
      'navigation': 'search-led',
      'primary_journey': 'search-to-order',
      'discovery_model': 'sku-search',
      'merchandising': 'availability-and-price',
      'density': 'dense',
      'transaction_model': 'checkout-plus-rfq',
      'patterns': ['search', 'plp', 'pdp', 'rfq'],
      'components': ['product-card', 'price-display', 'quote-card'],
    });
    expect(direction.id, 'a');
    expect(direction.patterns, contains('rfq'));
    expect(direction.isTrade, isTrue);
  });

  test('prototype direction rejects unknown density', () {
    expect(
      () => PrototypeDirection.fromMap({
        'id': 'a', 'name': 'Bad', 'strategic_goal': 'x', 'navigation': 'x',
        'primary_journey': 'x', 'discovery_model': 'x', 'merchandising': 'x',
        'density': 'massive', 'transaction_model': 'checkout',
        'patterns': ['home'], 'components': ['product-card'],
      }),
      throwsFormatException,
    );
  });
}
