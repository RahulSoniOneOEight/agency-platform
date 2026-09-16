import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime buildRuntime({Map<String, Map<String, Object?>>? directionThemes}) =>
    PrototypeRuntime.fromMap(canonicalBundle(directionThemes: directionThemes));

FixtureRepository fixturesFor(PrototypeRuntime runtime) =>
    FixtureRepository.fromRuntime(runtime);

Widget wrap(
  PrototypeRuntime runtime,
  FixtureRepository fixtures, {
  String directionId = 'a',
  String screenId = 'commerce.search',
}) {
  return MaterialApp(
    home: Scaffold(
      body: ReviewComparisonHost(
        runtime: runtime,
        fixtures: fixtures,
        directionId: directionId,
        screenId: screenId,
      ),
    ),
  );
}

void main() {
  testWidgets('renders the governed prototype pattern for the screen', (tester) async {
    final runtime = buildRuntime();
    final fixtures = fixturesFor(runtime);

    await tester.pumpWidget(wrap(runtime, fixtures));

    expect(find.byType(SearchPattern), findsOneWidget);
  });

  testWidgets('renders the same implementation as PrototypeRegistry.buildPattern', (tester) async {
    final runtime = buildRuntime();
    final fixtures = fixturesFor(runtime);
    final expected = PrototypeRegistry.buildPattern(
      'commerce.search',
      runtime.directions['a']!,
      fixtures,
    );

    await tester.pumpWidget(wrap(runtime, fixtures));

    expect(expected, isA<SearchPattern>());
    final rendered = tester.widget(find.byType(SearchPattern));
    expect(rendered.runtimeType, expected.runtimeType);
  });

  testWidgets('wraps only the client surface in the direction resolved theme', (tester) async {
    final runtime = buildRuntime(
      directionThemes: {
        'a': resolvedThemeMap(primary: '#1155CC'),
        'b': resolvedThemeMap(primary: '#CC1155'),
      },
    );
    final fixtures = fixturesFor(runtime);
    final primaryA = AgencyTheme.light(runtime.themeForDirection('a')).colorScheme.primary;
    final primaryB = AgencyTheme.light(runtime.themeForDirection('b')).colorScheme.primary;
    expect(primaryA, isNot(equals(primaryB)));

    await tester.pumpWidget(wrap(runtime, fixtures, directionId: 'a'));
    final themeA = tester.widget<Theme>(
      find.descendant(of: find.byType(ReviewComparisonHost), matching: find.byType(Theme)),
    );
    expect(themeA.data.colorScheme.primary, primaryA);
    expect(
      find.descendant(of: find.byType(Theme), matching: find.byType(SearchPattern)),
      findsOneWidget,
    );

    await tester.pumpWidget(wrap(runtime, fixtures, directionId: 'b'));
    final themeB = tester.widget<Theme>(
      find.descendant(of: find.byType(ReviewComparisonHost), matching: find.byType(Theme)),
    );
    expect(themeB.data.colorScheme.primary, primaryB);
  });

  testWidgets('forwards the requested direction into the reused pattern', (tester) async {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(
        names: const {'a': 'Alpha Direction', 'b': 'Beta Direction'},
        patterns: const {
          'a': ['commerce.home'],
          'b': ['commerce.home'],
        },
      ),
    );
    final fixtures = fixturesFor(runtime);

    await tester.pumpWidget(
      wrap(runtime, fixtures, directionId: 'a', screenId: 'commerce.home'),
    );

    expect(
      tester.widget<HomePattern>(find.byType(HomePattern)).title,
      'Alpha Direction',
    );
  });

  testWidgets('throws ArgumentError for an unknown direction id', (tester) async {
    final runtime = buildRuntime();
    final fixtures = fixturesFor(runtime);

    await tester.pumpWidget(wrap(runtime, fixtures, directionId: 'Z'));

    expect(tester.takeException(), isA<ArgumentError>());
  });

  testWidgets('throws ArgumentError for an unknown screen id', (tester) async {
    final runtime = buildRuntime();
    final fixtures = fixturesFor(runtime);

    await tester.pumpWidget(wrap(runtime, fixtures, screenId: 'commerce.unknown'));

    expect(tester.takeException(), isA<ArgumentError>());
  });
}
