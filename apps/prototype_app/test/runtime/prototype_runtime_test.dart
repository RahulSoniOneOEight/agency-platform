import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

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

  group('PrototypeRuntime', () {
    test('parses a valid generated client bundle', () {
      final runtime = PrototypeRuntime.fromMap(canonicalBundle());

      expect(runtime.clientId, 'prototype-demo');
      expect(runtime.defaultDirection, 'a');
      expect(runtime.directions.keys, ['a', 'b']);
      expect(runtime.allowedDirections, ['a', 'b']);
      expect(runtime.queryParameter, 'direction');
      expect(runtime.seedColor, '#6750A4');
      expect(runtime.fixtures['industry'], 'electronics-appliances');

      final hero = runtime.resource('asset.home.hero');
      expect(hero, isNotNull);
      expect(hero!.candidateId, 'pexels-42');
      expect(hero.source, 'pexels');
      expect(hero.type, 'image');
      expect(hero.asset['url'], 'https://example.test/hero.jpg');
      expect(hero.providerExtension, {'license': 'Pexels'});

      final override = runtime.overridesFor('b')['asset.home.hero'];
      expect(override, isNotNull);
      expect(override!.candidateId, 'client-hero');
      expect(runtime.overridesFor('a'), isEmpty);
    });

    test('accepts two and three declared directions', () {
      expect(PrototypeRuntime.fromMap(canonicalBundle()).directions.length, 2);
      expect(
        PrototypeRuntime.fromMap(
          canonicalBundle(directionIds: const ['a', 'b', 'c']),
        ).directions.length,
        3,
      );
    });

    test('requires the default direction to exist', () {
      final bundle = canonicalBundle()..['default_direction'] = 'c';

      expect(() => PrototypeRuntime.fromMap(bundle), throwsFormatException);
    });

    test('requires allowed directions to match declared directions', () {
      final bundle = canonicalBundle();
      (bundle['review'] as Map)['allowed_directions'] = ['a'];

      expect(() => PrototypeRuntime.fromMap(bundle), throwsFormatException);
    });

    test('rejects missing client id and malformed directions', () {
      final noClient = canonicalBundle()..remove('client_id');
      expect(() => PrototypeRuntime.fromMap(noClient), throwsFormatException);

      final oneDirection = canonicalBundle(directionIds: const ['a']);
      expect(() => PrototypeRuntime.fromMap(oneDirection), throwsFormatException);
    });

    test('rejects malformed resource bindings', () {
      final bundle = canonicalBundle();
      (bundle['resources'] as Map)['asset.home.hero'] = {'type': 'image'};

      expect(() => PrototypeRuntime.fromMap(bundle), throwsFormatException);
    });

    test('rejects unknown override direction ids', () {
      final bundle = canonicalBundle();
      (bundle['resources'] as Map)['direction_overrides'] = {
        'z': {'asset.home.hero': {}},
      };

      expect(() => PrototypeRuntime.fromMap(bundle), throwsFormatException);
    });

    test('rejects malformed override groups', () {
      final bundle = canonicalBundle();
      (bundle['resources'] as Map)['direction_overrides'] = {'b': []};

      expect(() => PrototypeRuntime.fromMap(bundle), throwsFormatException);
    });

    test('rejects an invalid theme seed color', () {
      final bundle = canonicalBundle();
      bundle['theme'] = {'seed_color': '6750A4'};

      expect(() => PrototypeRuntime.fromMap(bundle), throwsFormatException);
    });
  });
}
