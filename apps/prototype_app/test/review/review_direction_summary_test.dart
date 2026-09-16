import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/review/review_direction_summary.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b'],
      names: const {'a': 'Alpha Direction', 'b': 'Beta Direction'},
      strategicGoals: const {
        'a': 'reduce known-item order time',
        'b': 'expand discovery breadth',
      },
      patterns: const {
        'a': ['commerce.home'],
        'b': ['commerce.search'],
      },
    ),
  );
}

PrototypeDirection buildDirection([String id = 'a']) =>
    buildRuntime().directions[id]!;

Widget wrap(
  PrototypeDirection direction, {
  bool selected = false,
  VoidCallback? onSelect,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ReviewDirectionSummary(
        direction: direction,
        selected: selected,
        onSelect: onSelect,
      ),
    ),
  );
}

void main() {
  testWidgets('renders every metadata field from the PrototypeDirection',
      (tester) async {
    final runtime = buildRuntime();

    // Two directions with distinct names/goals prove the values come from the
    // direction object rather than hard-coded constants (which could satisfy
    // only one of them).
    for (final id in const ['a', 'b']) {
      final direction = runtime.directions[id]!;

      await tester.pumpWidget(wrap(direction));
      await tester.pumpAndSettle();

      expect(find.byKey(ReviewDirectionSummary.cardKey(direction.id)),
          findsOneWidget);
      expect(find.text(direction.id.toUpperCase()), findsOneWidget);
      expect(find.text(direction.name), findsOneWidget);
      expect(find.text(direction.strategicGoal), findsOneWidget);
      expect(find.text(direction.primaryJourney), findsOneWidget);
      expect(find.text(direction.discoveryModel), findsOneWidget);
      expect(find.text(direction.merchandisingModel), findsOneWidget);
      expect(find.text(direction.transactionModel), findsOneWidget);
      expect(find.text(direction.canonicalDensity), findsOneWidget);
    }
  });

  testWidgets('renders governed pattern labels via PrototypeRegistry.labelFor',
      (tester) async {
    final direction = buildDirection();
    final patternId = direction.patterns.first;
    final expectedLabel = PrototypeRegistry.labelFor(patternId);

    await tester.pumpWidget(wrap(direction));

    expect(find.text(expectedLabel), findsOneWidget);
    expect(find.text(patternId), findsNothing);
  });

  testWidgets('renders canonical component ids', (tester) async {
    final direction = buildDirection();

    await tester.pumpWidget(wrap(direction));

    for (final componentId in direction.components) {
      expect(find.text(componentId), findsOneWidget);
    }
  });

  testWidgets('selected: true shows the Selected indicator', (tester) async {
    final direction = buildDirection();

    await tester.pumpWidget(wrap(direction, selected: true));

    expect(find.text('Selected'), findsOneWidget);
  });

  testWidgets('selected: false hides the Selected indicator', (tester) async {
    final direction = buildDirection();

    await tester.pumpWidget(wrap(direction));

    expect(find.text('Selected'), findsNothing);
  });

  testWidgets('tapping the select button invokes onSelect once', (tester) async {
    final direction = buildDirection();
    var calls = 0;

    await tester.pumpWidget(wrap(direction, onSelect: () => calls++));

    final button = find.byKey(
      ReviewDirectionSummary.selectButtonKey(direction.id),
    );
    expect(button, findsOneWidget);
    expect(find.text('Select this direction'), findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('no select button when onSelect is null', (tester) async {
    final direction = buildDirection();

    await tester.pumpWidget(wrap(direction));

    expect(
      find.byKey(ReviewDirectionSummary.selectButtonKey(direction.id)),
      findsNothing,
    );
    expect(find.text('Select this direction'), findsNothing);
  });

  testWidgets('renders no ranking or recommendation vocabulary', (tester) async {
    final direction = buildDirection();

    await tester.pumpWidget(wrap(direction, selected: true, onSelect: () {}));

    expect(
      find.textContaining(
        RegExp(
          'best|recommend|winner|rank|score|rating|prefer|favorite|better|ideal',
          caseSensitive: false,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('renders without overflow at a narrow width', (tester) async {
    final direction = buildDirection();
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(direction, onSelect: () {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
