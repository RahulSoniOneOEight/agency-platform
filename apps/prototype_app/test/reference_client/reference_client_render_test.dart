import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reference_client_fixtures.dart';

void main() {
  group('reference client · bundle contract', () {
    test('loads reference-commerce and declares exactly directions a, b, c', () {
      final runtime = loadReferenceRuntime();

      expect(runtime.clientId, referenceClientId);
      expect(runtime.directions.keys.toList()..sort(), <String>['a', 'b', 'c']);
      expect(runtime.allowedDirections, <String>['a', 'b', 'c']);
      expect(runtime.defaultDirection, 'a');
    });

    test('directions are materially different but share one design system', () {
      final runtime = loadReferenceRuntime();

      final a = runtime.directions['a']!;
      final b = runtime.directions['b']!;
      final c = runtime.directions['c']!;

      // Distinct densities.
      expect(<AgencyDensity>{a.density, b.density, c.density}.length, 3);

      // Pairwise-different pattern sets.
      final patternSets = <Set<String>>[
        a.patterns.toSet(),
        b.patterns.toSet(),
        c.patterns.toSet(),
      ];
      for (var i = 0; i < patternSets.length; i++) {
        for (var j = i + 1; j < patternSets.length; j++) {
          expect(patternSets[i], isNot(equals(patternSets[j])),
              reason: 'directions $i and $j share a pattern set');
        }
      }

      // One design system: every direction resolves the same theme shape.
      final themes =
          <String>['a', 'b', 'c'].map(runtime.themeForDirection).toList();
      for (final theme in themes) {
        expect(theme.colors.keys.toSet(), themes.first.colors.keys.toSet());
        expect(theme.spacing.keys.toSet(), themes.first.spacing.keys.toSet());
        expect(theme.radius.keys.toSet(), themes.first.radius.keys.toSet());
      }

      for (final id in <String>['a', 'b', 'c']) {
        final material = AgencyTheme.light(runtime.themeForDirection(id));
        expect(material.extension<AgencyThemeTokens>(), isNotNull,
            reason: 'direction $id did not resolve agency tokens');
      }
    });
  });

  group('reference client · B2C journeys', () {
    testWidgets('direction a renders search, pdp, and cart without throwing',
        (tester) async {
      final runtime = loadReferenceRuntime();

      for (final screen in <String>[
        'commerce.search',
        'commerce.pdp',
        'commerce.cart',
      ]) {
        await pumpReferencePattern(tester, runtime, 'a', screen);
        expect(tester.takeException(), isNull, reason: screen);
      }
    });

    testWidgets('direction b renders pdp without throwing', (tester) async {
      final runtime = loadReferenceRuntime();

      await pumpReferencePattern(tester, runtime, 'b', 'commerce.pdp');
      expect(tester.takeException(), isNull);
    });
  });

  group('reference client · B2B journeys', () {
    testWidgets('direction c renders the RFQ and trade dashboard B2B copy',
        (tester) async {
      final runtime = loadReferenceRuntime();

      await pumpReferencePattern(tester, runtime, 'c', 'commerce.rfq');
      expect(tester.takeException(), isNull);
      expect(find.text('Request a quote'), findsOneWidget);
      expect(find.text('Send RFQ'), findsOneWidget);

      await pumpReferencePattern(
          tester, runtime, 'c', 'commerce.trade-dashboard');
      expect(tester.takeException(), isNull);
      expect(find.text('Trade dashboard'), findsOneWidget);
      expect(find.text('Trade credit'), findsOneWidget);
      expect(find.text('Quick order'), findsOneWidget);
      expect(find.text('New RFQ'), findsOneWidget);
    });
  });

  group('reference client · runtime immutability', () {
    testWidgets('rendering every safe screen never mutates the runtime',
        (tester) async {
      final runtime = loadReferenceRuntime();
      final before = runtimeSnapshot(runtime);

      for (final id in <String>['a', 'b', 'c']) {
        final patterns = runtime.directions[id]!.patterns;
        for (final screen in safeReferenceScreens) {
          if (!patterns.contains(screen)) continue;
          await pumpReferencePattern(tester, runtime, id, screen);
        }
      }

      expect(runtimeSnapshot(runtime), equals(before));
    });
  });
}
