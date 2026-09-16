import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/review/review_screen_registry.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

void main() {
  group('ReviewScreenRegistry.screenIdsFor', () {
    test('unions the canonical pattern ids of every runtime direction', () {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(
          directionIds: const ['a', 'b'],
          patterns: const {
            'a': ['commerce.home', 'commerce.search'],
            'b': ['commerce.search', 'commerce.plp'],
          },
        ),
      );

      expect(
        ReviewScreenRegistry.screenIdsFor(runtime),
        equals(<String>{'commerce.home', 'commerce.search', 'commerce.plp'}),
      );
    });

    test('returns ids in deterministic sorted order', () {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(
          directionIds: const ['a', 'b'],
          patterns: const {
            'a': ['commerce.search', 'commerce.home'],
            'b': ['commerce.plp', 'commerce.search'],
          },
        ),
      );

      expect(
        ReviewScreenRegistry.screenIdsFor(runtime).toList(),
        equals(['commerce.home', 'commerce.plp', 'commerce.search']),
      );
    });

    test('uses canonical pattern ids and never invents review aliases', () {
      final runtime = PrototypeRuntime.fromMap(canonicalBundle());

      final ids = ReviewScreenRegistry.screenIdsFor(runtime);

      expect(ids, contains('commerce.search'));
      expect(ids, isNot(contains('home_v2')));
      expect(ids.every((id) => id.startsWith('commerce.')), isTrue);
    });
  });

  group('ReviewScreenRegistry.labelFor', () {
    test('delegates to PrototypeRegistry.labelFor', () {
      expect(
        ReviewScreenRegistry.labelFor('commerce.search'),
        PrototypeRegistry.labelFor('commerce.search'),
      );
      expect(ReviewScreenRegistry.labelFor('commerce.search'), 'Search');
    });

    test('throws ArgumentError for an unknown canonical pattern id', () {
      expect(
        () => ReviewScreenRegistry.labelFor('commerce.unknown'),
        throwsArgumentError,
      );
    });
  });
}
