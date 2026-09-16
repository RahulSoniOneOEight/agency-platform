import 'dart:convert';
import 'dart:io';

import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_direction_comparison.dart';
import 'package:prototype_app/review/review_screen_availability.dart';
import 'package:prototype_app/review/review_screen_comparison.dart';
import 'package:prototype_app/review/review_section_compatibility.dart';
import 'package:prototype_app/review/review_section_registry.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

/// Loads the committed reference-client bundle exactly as the app does.
///
/// Tests run on the VM from `apps/prototype_app`, so the relative asset path
/// resolves against the package root.
PrototypeRuntime _loadReferenceRuntime() {
  final decoded =
      json.decode(File('assets/generated/prototype-demo.json').readAsStringSync())
          as Map;
  return PrototypeRuntime.fromMap(Map<String, dynamic>.from(decoded));
}

ReviewController _freshController(PrototypeRuntime runtime) => ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );

Future<void> _pumpScreenComparison(
  WidgetTester tester,
  PrototypeRuntime runtime,
  ReviewController controller,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReviewScreenComparison(
          runtime: runtime,
          fixtures: FixtureRepository.fromRuntime(runtime),
          controller: controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final runtime = _loadReferenceRuntime();

  group('reference client · direction order and availability', () {
    test('orderedDirections is the runtime declared order', () {
      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(<String>['a', 'b', 'c']),
      );
      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(runtime.allowedDirections),
      );
    });

    test('per-pair availability matches the declared direction patterns', () {
      // NOTE: the committed reference bundle declares
      //   a = search/plp/pdp/cart/rfq
      //   b = trade-dashboard/reorder/cart
      //   c = home/plp/pdp/rfq/trade-dashboard
      // so `commerce.search` is declared only by a; b and c are unavailable.
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.search'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.search'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'c', 'commerce.search'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'c', 'commerce.home'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.home'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.trade-dashboard'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.reorder'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.cart'),
        isTrue,
      );
    });

    test('screens is the sorted union of every direction pattern', () {
      final expected = <String>{
        for (final direction in runtime.directions.values) ...direction.patterns,
      }.toList()
        ..sort();

      expect(ReviewScreenAvailability.screens(runtime), equals(expected));
      expect(
        ReviewScreenAvailability.screens(runtime),
        containsAll(<String>[
          'commerce.home',
          'commerce.search',
          'commerce.trade-dashboard',
        ]),
      );
    });

    test('directions resolve to distinct direction themes', () {
      final dataA = AgencyTheme.light(runtime.themeForDirection('a'));
      final dataB = AgencyTheme.light(runtime.themeForDirection('b'));
      final dataC = AgencyTheme.light(runtime.themeForDirection('c'));

      // The committed reference bundle intentionally shares one brand primary
      // (#1155CC) across all three directions, so `colorScheme.primary` does
      // NOT discriminate them. Directions differ through B.1E theme overrides
      // (density, section spacing, card radius); lock those discriminating
      // values instead of the shared brand color.
      final tokensA = dataA.extension<AgencyThemeTokens>()!;
      final tokensB = dataB.extension<AgencyThemeTokens>()!;
      final tokensC = dataC.extension<AgencyThemeTokens>()!;

      expect(tokensA.density, isNot(tokensB.density));
      expect(tokensA.sectionSpacing, isNot(tokensB.sectionSpacing));
      expect(tokensA.cardRadius, isNot(tokensB.cardRadius));

      expect(tokensA.density, isNot(tokensC.density));
      expect(tokensA.sectionSpacing, isNot(tokensC.sectionSpacing));
      expect(tokensA.cardRadius, isNot(tokensC.cardRadius));
    });
  });

  group('reference client · screen comparison', () {
    // CAVEAT: do NOT render `commerce.home` or `commerce.plp` with the real
    // reference theme in widget tests. Those two shared patterns have a
    // pre-existing `ProductCard`/`mainAxisExtent` overflow (also present in
    // normal prototype mode) that is out of C.2 scope. `commerce.search`,
    // `commerce.pdp`, and `commerce.cart` are safe.
    testWidgets(
        'wide surface renders the supporting directions and the unavailable state',
        (tester) async {
      final controller = _freshController(runtime);
      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1600, 900),
      );

      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
      );
      await tester.pumpAndSettle();

      // commerce.search is declared only by direction a; b and c show the
      // neutral unavailable state (b declares trade-dashboard/reorder/cart).
      expect(find.byType(ReviewComparisonHost), findsOneWidget);
      expect(
        find.byKey(ReviewScreenComparison.unavailableKey('b')),
        findsOneWidget,
      );
      expect(
        find.byKey(ReviewScreenComparison.unavailableKey('c')),
        findsOneWidget,
      );
      expect(
        find.text('This screen is not part of Direction B'),
        findsOneWidget,
      );
      expect(
        find.text('This screen is not part of Direction C'),
        findsOneWidget,
      );
      expect(controller.state.selectedDirection, isNull);
    });

    testWidgets('supported panels use the direction-resolved theme',
        (tester) async {
      final controller = _freshController(runtime);
      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1600, 900),
      );

      // commerce.cart is declared by a and b, so two real panels render.
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.cart')),
      );
      await tester.pumpAndSettle();

      final supported = const ['a', 'b']
          .where((id) =>
              ReviewScreenAvailability.isSupported(runtime, id, 'commerce.cart'))
          .toList();
      expect(supported, equals(<String>['a', 'b']));

      for (final id in supported) {
        final expected = AgencyTheme.light(runtime.themeForDirection(id));
        final host = find.descendant(
          of: find.byKey(ReviewComparisonLayout.panelKey(id)),
          matching: find.byType(ReviewComparisonHost),
        );
        final rendered = tester.widget<Theme>(
          find.descendant(of: host, matching: find.byType(Theme)).first,
        );
        expect(
          rendered.data.colorScheme.primary,
          expected.colorScheme.primary,
          reason: 'direction $id did not use its resolved primary',
        );
        expect(
          rendered.data.scaffoldBackgroundColor,
          expected.scaffoldBackgroundColor,
          reason: 'direction $id did not use its resolved surface',
        );

        // The shared brand primary cannot discriminate directions; the
        // direction-resolved tokens can (and catch a base-theme leak).
        final tokens = rendered.data.extension<AgencyThemeTokens>()!;
        expect(tokens.sectionSpacing, runtime.themeForDirection(id).spacing['section']);
        expect(tokens.density, runtime.themeForDirection(id).density);
      }
    });
  });

  group('reference client · directions comparison', () {
    testWidgets('renders all three real direction names', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewDirectionComparison(
              runtime: runtime,
              controller: _freshController(runtime),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final id in const ['a', 'b', 'c']) {
        expect(
          find.text(runtime.directions[id]!.name),
          findsOneWidget,
          reason: 'missing real direction name for $id',
        );
      }
    });
  });

  group('reference client · section availability and compatibility', () {
    ReviewSectionCompatibilityResult evaluate({
      required String screenId,
      required String sectionId,
      required String source,
      String base = 'a',
    }) {
      return ReviewSectionCompatibility.evaluate(
        runtime: runtime,
        screenId: screenId,
        sectionId: sectionId,
        sourceDirectionId: source,
        baseDirectionId: base,
      );
    }

    test('governed sections exist for the composed reference screens', () {
      expect(
        ReviewSectionRegistry.sectionsForScreen('commerce.plp').map((d) => d.id),
        contains('plp.product-grid'),
      );
      expect(
        ReviewSectionRegistry.sectionsForScreen('commerce.pdp').map((d) => d.id),
        contains('pdp.price'),
      );
    });

    test('plp.product-grid mixes from c into a base a (both declare plp)', () {
      final result = evaluate(
        screenId: 'commerce.plp',
        sectionId: 'plp.product-grid',
        source: 'c',
      );
      expect(result.allowed, isTrue);
    });

    test('pdp.price mixes from c into a base a (both declare pdp)', () {
      final result = evaluate(
        screenId: 'commerce.pdp',
        sectionId: 'pdp.price',
        source: 'c',
      );
      expect(result.allowed, isTrue);
    });

    test('plp.product-grid is unavailable from b (b does not declare plp)', () {
      final result = evaluate(
        screenId: 'commerce.plp',
        sectionId: 'plp.product-grid',
        source: 'b',
      );
      expect(result.allowed, isFalse);
      expect(result.reason, 'Not present in Direction B');
    });

    test('search.search-field is unavailable from c (c does not declare search)', () {
      final result = evaluate(
        screenId: 'commerce.search',
        sectionId: 'search.search-field',
        source: 'c',
      );
      expect(result.allowed, isFalse);
      expect(result.reason, 'Not present in Direction C');
    });
  });
}
