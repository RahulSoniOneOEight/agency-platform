import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/review/review_mixed_preview.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// `commerce.plp` is declared by `a` and `c`; each exposes product-card, and
/// their resolved themes differ by primary so theme scoping is observable.
PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.plp'],
        'b': ['commerce.search'],
        'c': ['commerce.plp'],
      },
      components: const {
        'a': ['commerce.product-card'],
        'b': ['commerce.product-card'],
        'c': ['commerce.product-card'],
      },
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
      directionThemes: {
        'a': resolvedThemeMap(
            primary: '#1155CC', cardSpacing: 12, tileGap: 8, cardRadius: 12),
        'c': resolvedThemeMap(
            primary: '#CC1155', cardSpacing: 28, tileGap: 8, cardRadius: 28),
      },
    ),
  );
}

ReviewState stateWith({
  String? selected,
  Map<String, String> sections = const {},
}) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: 'prototype-demo',
    reviewRound: 1,
    status: ReviewStatus.inReview,
    selectedDirection: selected,
    screenSelections: {
      if (sections.isNotEmpty)
        'commerce.plp': ReviewScreenDecision(sections: sections),
    },
    comments: const [],
  );
}

void main() {
  late PrototypeRuntime runtime;
  late FixtureRepository fixtures;

  setUp(() {
    runtime = buildRuntime();
    fixtures = FixtureRepository.fromRuntime(runtime);
  });

  Future<void> pump(
    WidgetTester tester,
    ReviewState state, {
    String screenId = 'commerce.plp',
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewMixedPreview(
            runtime: runtime,
            fixtures: fixtures,
            screenId: screenId,
            state: state,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ThemeData themeAt(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder));

  testWidgets('renders a neutral prompt when no base direction is selected',
      (tester) async {
    await pump(tester, stateWith());

    expect(find.byKey(ReviewMixedPreview.noBaseKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inherited sections render under the effective screen theme',
      (tester) async {
    await pump(tester, stateWith(selected: 'a'));

    final base = AgencyTheme.light(runtime.themeForDirection('a'));
    final strip = themeAt(tester, find.byType(FilterChipStripSection));
    expect(strip.colorScheme.primary, base.colorScheme.primary);
    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.product-grid')),
      findsNothing,
    );
  });

  testWidgets('an overridden section uses the source-direction theme only',
      (tester) async {
    await pump(
      tester,
      stateWith(selected: 'a', sections: const {'plp.product-grid': 'c'}),
    );

    final base = AgencyTheme.light(runtime.themeForDirection('a'));
    final source = AgencyTheme.light(runtime.themeForDirection('c'));
    expect(base.colorScheme.primary, isNot(source.colorScheme.primary));

    // Overridden grid section -> source theme.
    final grid = themeAt(
      tester,
      find.descendant(
        of: find.byKey(ReviewMixedPreview.sectionKey('plp.product-grid')),
        matching: find.byType(ProductGridSection),
      ),
    );
    expect(grid.colorScheme.primary, source.colorScheme.primary);

    // Sibling (inherited filter strip) stays under the base theme.
    final strip = themeAt(tester, find.byType(FilterChipStripSection));
    expect(strip.colorScheme.primary, base.colorScheme.primary);

    // Token isolation (not just color): the override carries source tokens while
    // the sibling keeps base tokens.
    final sourceTokens = source.extension<AgencyThemeTokens>()!;
    final gridTokens = AgencyThemeTokens.of(tester.element(
      find.descendant(
        of: find.byKey(ReviewMixedPreview.sectionKey('plp.product-grid')),
        matching: find.byType(ProductGridSection),
      ),
    ));
    expect(gridTokens.cardRadius, sourceTokens.cardRadius);
    expect(gridTokens.cardSpacing, sourceTokens.cardSpacing);

    final baseTokens = base.extension<AgencyThemeTokens>()!;
    final stripTokens =
        AgencyThemeTokens.of(tester.element(find.byType(FilterChipStripSection)));
    expect(stripTokens.cardRadius, baseTokens.cardRadius);
    expect(stripTokens.cardSpacing, baseTokens.cardSpacing);

    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.product-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.filter-strip')),
      findsNothing,
    );
  });

  testWidgets('reuses the shared section implementation', (tester) async {
    await pump(
      tester,
      stateWith(selected: 'a', sections: const {'plp.product-grid': 'c'}),
    );

    expect(find.byType(ProductGridSection), findsOneWidget);
    expect(find.byType(FilterChipStripSection), findsOneWidget);
  });

  testWidgets('does not mutate the runtime', (tester) async {
    final directionsBefore = Map.of(runtime.directions);
    final themesBefore = Map.of(runtime.directionThemes);
    final allowedBefore = List<String>.of(runtime.allowedDirections);

    await pump(
      tester,
      stateWith(selected: 'a', sections: const {'plp.product-grid': 'c'}),
    );

    for (final id in directionsBefore.keys) {
      expect(identical(runtime.directions[id], directionsBefore[id]), isTrue);
    }
    for (final id in themesBefore.keys) {
      expect(identical(runtime.directionThemes[id], themesBefore[id]), isTrue);
    }
    expect(runtime.allowedDirections, allowedBefore);
  });

  testWidgets('an explicit screen direction override chooses the base',
      (tester) async {
    final state = ReviewState(
      version: ReviewState.currentVersion,
      clientId: 'prototype-demo',
      reviewRound: 1,
      status: ReviewStatus.inReview,
      selectedDirection: 'a',
      screenSelections: {
        'commerce.plp': ReviewScreenDecision(direction: 'c'),
      },
      comments: const [],
    );

    await pump(tester, state);

    final source = AgencyTheme.light(runtime.themeForDirection('c'));
    final strip = themeAt(tester, find.byType(FilterChipStripSection));
    expect(strip.colorScheme.primary, source.colorScheme.primary);
  });

  testWidgets('an unknown base direction renders the neutral prompt',
      (tester) async {
    await pump(tester, stateWith(selected: 'zzz'));

    expect(find.byKey(ReviewMixedPreview.noBaseKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incompatible override falls back to the base section',
      (tester) async {
    // Direction b does not declare commerce.plp, so the override must never
    // reach the renderer.
    await pump(
      tester,
      stateWith(selected: 'a', sections: const {'plp.product-grid': 'b'}),
    );

    final base = AgencyTheme.light(runtime.themeForDirection('a'));
    final grid = themeAt(
      tester,
      find.descendant(
        of: find.byKey(ReviewMixedPreview.sectionKey('plp.product-grid')),
        matching: find.byType(ProductGridSection),
      ),
    );
    expect(grid.colorScheme.primary, base.colorScheme.primary);
    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.product-grid')),
      findsNothing,
    );
  });

  testWidgets('a non-section screen still uses the base direction theme',
      (tester) async {
    await pump(tester, stateWith(selected: 'a'), screenId: 'commerce.cart');

    final base = AgencyTheme.light(runtime.themeForDirection('a'));
    final cart = themeAt(tester, find.byType(CartPattern));
    expect(cart.colorScheme.primary, base.colorScheme.primary);
    expect(tester.takeException(), isNull);
  });
}
