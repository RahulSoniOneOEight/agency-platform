import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';

Map<String, dynamic> canonicalDirection({
  String id = 'a',
  String density = 'compact',
}) {
  return {
    'id': id,
    'name': 'Search-led Trade',
    'strategic_goal': 'reduce known-item order time',
    'navigation_model': 'search-led',
    'primary_journey': 'search-to-order',
    'discovery_model': 'sku-search',
    'merchandising_model': 'availability-and-price',
    'density': density,
    'transaction_model': 'checkout-plus-rfq',
    'patterns': ['commerce.search'],
    'components': ['commerce.product-card'],
    'component_variants': [
      {'component': 'commerce.product-card', 'variant': 'b2b'},
    ],
    'required_resources': ['asset.home.hero'],
  };
}

void main() {
  group('PrototypeDirection', () {
    test('parses the canonical B.1A runtime contract', () {
      final direction = PrototypeDirection.fromMap(canonicalDirection());

      expect(direction.id, 'a');
      expect(direction.name, 'Search-led Trade');
      expect(direction.strategicGoal, 'reduce known-item order time');
      expect(direction.navigationModel, 'search-led');
      expect(direction.primaryJourney, 'search-to-order');
      expect(direction.discoveryModel, 'sku-search');
      expect(direction.merchandisingModel, 'availability-and-price');
      expect(direction.density, AgencyDensity.dense);
      expect(direction.transactionModel, 'checkout-plus-rfq');
      expect(direction.patterns, ['commerce.search']);
      expect(direction.components, ['commerce.product-card']);
      expect(direction.componentVariants, hasLength(1));
      expect(direction.componentVariants.single.component, 'commerce.product-card');
      expect(direction.componentVariants.single.variant, 'b2b');
      expect(direction.requiredResources, ['asset.home.hero']);
      expect(direction.isTrade, isTrue);
    });

    test('maps canonical density vocabulary into UI density', () {
      expect(
        PrototypeDirection.fromMap(canonicalDirection(density: 'compact')).density,
        AgencyDensity.dense,
      );
      expect(
        PrototypeDirection.fromMap(canonicalDirection(density: 'normal')).density,
        AgencyDensity.balanced,
      );
      expect(
        PrototypeDirection.fromMap(canonicalDirection(density: 'spacious')).density,
        AgencyDensity.airy,
      );
    });

    test('rejects legacy density vocabulary', () {
      expect(
        () => PrototypeDirection.fromMap(canonicalDirection(density: 'dense')),
        throwsFormatException,
      );
      expect(
        () => PrototypeDirection.fromMap(canonicalDirection(density: 'balanced')),
        throwsFormatException,
      );
      expect(
        () => PrototypeDirection.fromMap(canonicalDirection(density: 'airy')),
        throwsFormatException,
      );
    });

    test('accepts empty component variants and required resources', () {
      final map = canonicalDirection();
      map['component_variants'] = <dynamic>[];
      map['required_resources'] = <dynamic>[];

      final direction = PrototypeDirection.fromMap(map);

      expect(direction.componentVariants, isEmpty);
      expect(direction.requiredResources, isEmpty);
    });

    test('rejects missing canonical fields', () {
      final map = canonicalDirection()..remove('navigation_model');

      expect(() => PrototypeDirection.fromMap(map), throwsFormatException);
    });
  });
}
