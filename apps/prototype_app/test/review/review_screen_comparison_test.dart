import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_screen_comparison.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Three-direction runtime where some `(screen, direction)` pairs are
/// unsupported, so availability handling is exercised deterministically:
/// `a` = home/search, `b` = search/plp, `c` = pdp/plp.
PrototypeRuntime buildRuntime({Map<String, Map<String, Object?>>? directionThemes}) {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
      // Compact spacing keeps the shared ProductCard within its fixed grid
      // extent at panel widths (a shared-component concern, not a C.2 one).
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
      directionThemes: directionThemes,
    ),
  );
}

void main() {
  late PrototypeRuntime runtime;
  late FixtureRepository fixtures;
  late ReviewController controller;

  setUp(() {
    runtime = buildRuntime();
    fixtures = FixtureRepository.fromRuntime(runtime);
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );
  });

  ReviewController controllerWith(String? selectedDirection) {
    return ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      initialState: ReviewState(
        version: ReviewState.currentVersion,
        clientId: runtime.clientId,
        reviewRound: 1,
        status: ReviewStatus.inReview,
        selectedDirection: selectedDirection,
        screenSelections: const <String, ReviewScreenDecision>{},
        comments: const <ReviewComment>[],
      ),
    );
  }

  Future<void> pumpSurface(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewScreenComparison(
            runtime: runtime,
            fixtures: fixtures,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the governed screen selector defaulting to the first sorted screen',
      (tester) async {
    await pumpSurface(tester, const Size(1200, 800));

    expect(find.byKey(ReviewScreenComparison.screenSelectorKey), findsOneWidget);

    // Governed union, sorted: home, pdp, plp, search.
    for (final id in const [
      'commerce.home',
      'commerce.pdp',
      'commerce.plp',
      'commerce.search',
    ]) {
      expect(
        find.byKey(ReviewScreenComparison.screenChipKey(id)),
        findsOneWidget,
        reason: 'missing governed screen chip $id',
      );
    }

    final homeChip = tester.widget<ChoiceChip>(
      find.byKey(ReviewScreenComparison.screenChipKey('commerce.home')),
    );
    expect(homeChip.selected, isTrue);
    final searchChip = tester.widget<ChoiceChip>(
      find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
    );
    expect(searchChip.selected, isFalse);

    // Labels are the governed registry labels, not raw IDs.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
  });

  testWidgets('wide surface renders the selected screen for exactly the supporting directions',
      (tester) async {
    await pumpSurface(tester, const Size(1200, 800));

    await tester.tap(
      find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
    );
    await tester.pumpAndSettle();

    // search is supported by a and b only.
    expect(find.byType(ReviewComparisonHost), findsNWidgets(2));
    expect(find.byKey(ReviewScreenComparison.unavailableKey('c')), findsOneWidget);
    expect(find.text('This screen is not part of Direction C'), findsOneWidget);
  });

  testWidgets('does not substitute a screen for an unsupported direction',
      (tester) async {
    await pumpSurface(tester, const Size(1200, 800));

    // commerce.home is supported only by direction a.
    expect(find.byKey(ReviewComparisonLayout.panelKey('c')), findsOneWidget);
    expect(find.byKey(ReviewScreenComparison.unavailableKey('c')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ReviewScreenComparison.unavailableKey('c')),
        matching: find.byType(ReviewComparisonHost),
      ),
      findsNothing,
    );
    expect(find.byType(ReviewComparisonHost), findsOneWidget);
  });

  testWidgets('compact surface shows the switcher and only the active direction panel',
      (tester) async {
    await pumpSurface(tester, const Size(400, 800));

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('b')), findsNothing);
    expect(find.byKey(ReviewComparisonLayout.panelKey('c')), findsNothing);
  });

  testWidgets('restored selection seeds the compact preview', (tester) async {
    controller = controllerWith('c');

    await pumpSurface(tester, const Size(400, 800));

    expect(find.byKey(ReviewComparisonLayout.panelKey('c')), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsNothing);
  });

  testWidgets('runtime default is used only when no selection exists',
      (tester) async {
    controller = controllerWith(null);

    await pumpSurface(tester, const Size(400, 800));

    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('c')), findsNothing);
    expect(controller.state.selectedDirection, isNull);
  });

  testWidgets('a selection restored after the first build seeds the preview',
      (tester) async {
    controller = controllerWith(null);

    await pumpSurface(tester, const Size(400, 800));
    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsOneWidget);

    await controller.selectDirection('c');
    await tester.pumpAndSettle();

    expect(find.byKey(ReviewComparisonLayout.panelKey('c')), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsNothing);
  });

  testWidgets('a user preview wins over a later selection and never selects',
      (tester) async {
    await pumpSurface(tester, const Size(400, 800));

    await tester.tap(
      find.descendant(
        of: find.byKey(ReviewComparisonLayout.switcherKey),
        matching: find.text('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
    expect(find.byKey(ReviewComparisonLayout.panelKey('b')), findsOneWidget);

    await controller.selectDirection('c');
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, 'c');
    expect(find.byKey(ReviewComparisonLayout.panelKey('b')), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('c')), findsNothing);
  });

  testWidgets('compact switcher swaps the active direction panel',
      (tester) async {
    await pumpSurface(tester, const Size(400, 800));
    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(ReviewComparisonLayout.switcherKey),
        matching: find.text('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ReviewComparisonLayout.panelKey('b')), findsOneWidget);
    expect(find.byKey(ReviewComparisonLayout.panelKey('a')), findsNothing);
  });

  testWidgets('wide surface exposes the side-by-side/focused toggle',
      (tester) async {
    await pumpSurface(tester, const Size(1200, 800));

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsNothing);
    expect(find.byKey(ReviewComparisonLayout.modeToggleKey), findsOneWidget);
  });

  testWidgets('supported panels use the direction-resolved theme', (tester) async {
    runtime = buildRuntime(
      directionThemes: {
        'a': resolvedThemeMap(primary: '#1155CC', cardSpacing: 12, tileGap: 8),
        'b': resolvedThemeMap(primary: '#CC1155', cardSpacing: 12, tileGap: 8),
      },
    );
    fixtures = FixtureRepository.fromRuntime(runtime);
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );

    await pumpSurface(tester, const Size(1200, 800));
    await tester.tap(
      find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
    );
    await tester.pumpAndSettle();

    final expectedA =
        AgencyTheme.light(runtime.themeForDirection('a')).colorScheme.primary;
    final expectedB =
        AgencyTheme.light(runtime.themeForDirection('b')).colorScheme.primary;
    expect(expectedA, isNot(expectedB));

    for (final entry in {'a': expectedA, 'b': expectedB}.entries) {
      final host = find.descendant(
        of: find.byKey(ReviewComparisonLayout.panelKey(entry.key)),
        matching: find.byType(ReviewComparisonHost),
      );
      final theme = tester.widget<Theme>(
        find.descendant(of: host, matching: find.byType(Theme)).first,
      );
      expect(theme.data.colorScheme.primary, entry.value);
    }
  });

  testWidgets('viewing a screen and switching preview never mutates selection state',
      (tester) async {
    await pumpSurface(tester, const Size(400, 800));

    await tester.tap(
      find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(ReviewComparisonLayout.switcherKey),
        matching: find.text('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
    expect(controller.state.screenSelections, isEmpty);
  });

  testWidgets('renders without overflow at a narrow width', (tester) async {
    await pumpSurface(tester, const Size(360, 800));

    expect(tester.takeException(), isNull);
  });
}
