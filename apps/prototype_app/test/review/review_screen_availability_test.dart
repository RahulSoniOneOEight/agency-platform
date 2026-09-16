import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_screen_availability.dart';
import 'package:prototype_app/review/review_screen_registry.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search'],
        'c': ['commerce.pdp'],
      },
    ),
  );
}

void main() {
  group('ReviewScreenAvailability.orderedDirections', () {
    test('returns the runtime declared direction order exactly', () {
      final runtime = buildRuntime();

      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(<String>['a', 'b', 'c']),
      );
      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(runtime.allowedDirections),
      );
    });

    test('does not reorder directions', () {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(directionIds: const ['c', 'a', 'b']),
      );

      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(<String>['c', 'a', 'b']),
      );
    });

    test('preserves order for a two-direction runtime', () {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(directionIds: const ['b', 'a']),
      );

      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(<String>['b', 'a']),
      );
    });

    test('returns a copy that cannot mutate runtime state', () {
      final runtime = buildRuntime();
      final result = ReviewScreenAvailability.orderedDirections(runtime);

      expect(identical(result, runtime.allowedDirections), isFalse);
      expect(() => result.add('d'), throwsUnsupportedError);
      expect(runtime.allowedDirections, equals(<String>['a', 'b', 'c']));
    });
  });

  group('ReviewScreenAvailability.screens', () {
    test('delegates to the sorted union from ReviewScreenRegistry', () {
      final runtime = buildRuntime();

      expect(
        ReviewScreenAvailability.screens(runtime),
        equals(ReviewScreenRegistry.screenIdsFor(runtime).toList()),
      );
      expect(
        ReviewScreenAvailability.screens(runtime),
        equals(<String>['commerce.home', 'commerce.pdp', 'commerce.search']),
      );
    });

    test('is deterministically sorted', () {
      final runtime = buildRuntime();
      final screens = ReviewScreenAvailability.screens(runtime);

      expect(screens, equals([...screens]..sort()));
    });

    test('returns a copy that cannot mutate runtime state', () {
      final runtime = buildRuntime();
      final screens = ReviewScreenAvailability.screens(runtime);

      expect(() => screens.add('commerce.extra'), throwsUnsupportedError);
      expect(
        ReviewScreenRegistry.screenIdsFor(runtime),
        isNot(contains('commerce.extra')),
      );
    });
  });

  group('ReviewScreenAvailability.isSupported', () {
    test('is true when the direction declares the screen', () {
      final runtime = buildRuntime();

      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.home'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'c', 'commerce.pdp'),
        isTrue,
      );
    });

    test('is false when the direction does not declare the screen', () {
      final runtime = buildRuntime();

      expect(
        ReviewScreenAvailability.isSupported(runtime, 'c', 'commerce.home'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.pdp'),
        isFalse,
      );
    });

    test('is false without throwing for an unknown direction id', () {
      final runtime = buildRuntime();

      expect(
        ReviewScreenAvailability.isSupported(runtime, 'zzz', 'commerce.home'),
        isFalse,
      );
    });

    test('is false without throwing for an unknown screen id', () {
      final runtime = buildRuntime();

      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.unknown'),
        isFalse,
      );
    });
  });

  group('ReviewScreenAvailability.labelFor', () {
    test('delegates to ReviewScreenRegistry.labelFor', () {
      expect(
        ReviewScreenAvailability.labelFor('commerce.search'),
        ReviewScreenRegistry.labelFor('commerce.search'),
      );
      expect(ReviewScreenAvailability.labelFor('commerce.search'), 'Search');
    });

    test('throws ArgumentError for an unknown screen id', () {
      expect(
        () => ReviewScreenAvailability.labelFor('commerce.unknown'),
        throwsArgumentError,
      );
    });
  });
}
