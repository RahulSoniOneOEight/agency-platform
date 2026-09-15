import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';

void main() {
  test('prototype direction parses strategy config', () {
    final direction = PrototypeDirection.fromMap({
      'id': 'a',
      'name': 'Search-led Trade',
      'strategic_goal': 'reduce order time',
      'navigation_model': 'search-led',
      'primary_journey': 'search-to-order',
      'discovery_model': 'sku-search',
      'merchandising_model': 'availability-and-price',
      'density': 'compact',
      'transaction_model': 'checkout-plus-rfq',
      'patterns': ['commerce.search', 'commerce.plp', 'commerce.pdp', 'commerce.rfq'],
      'components': ['commerce.product-card', 'commerce.price-display', 'commerce.quote-card'],
      'component_variants': <dynamic>[],
      'required_resources': <dynamic>[],
    });
    expect(direction.id, 'a');
    expect(direction.patterns, contains('commerce.rfq'));
    expect(direction.isTrade, isTrue);
  });

  test('prototype direction rejects unknown density', () {
    expect(
      () => PrototypeDirection.fromMap({
        'id': 'a', 'name': 'Bad', 'strategic_goal': 'x',
        'navigation_model': 'x', 'primary_journey': 'x', 'discovery_model': 'x',
        'merchandising_model': 'x', 'density': 'massive', 'transaction_model': 'checkout',
        'patterns': ['commerce.home'], 'components': ['commerce.product-card'],
      }),
      throwsFormatException,
    );
  });
}
