import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_selection.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Reference runtime with three real directions and four governed screens so the
/// selection screen has a genuine runtime direction set and screen registry.
PrototypeRuntime buildSelectionRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      names: const {
        'a': 'Alpha Direction',
        'b': 'Beta Direction',
        'c': 'Gamma Direction',
      },
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
    ),
  );
}

void main() {
  late PrototypeRuntime runtime;
  late MemoryReviewRepository repository;
  late ReviewController controller;

  setUp(() {
    runtime = buildSelectionRuntime();
    repository = MemoryReviewRepository();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: repository,
      runtime: runtime,
    );
  });

  Future<void> pumpSelection(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewSelection(runtime: runtime, controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Set<String> overallDirectionValues(WidgetTester tester) {
    return tester
        .widgetList<RadioListTile<String?>>(
          find.descendant(
            of: find.byKey(ReviewSelection.overallGroupKey),
            matching: find.byType(RadioListTile<String?>),
          ),
        )
        .map((tile) => tile.value)
        .whereType<String>()
        .toSet();
  }

  testWidgets('initial state has no overall selection', (tester) async {
    await pumpSelection(tester);

    expect(controller.state.selectedDirection, isNull);
    expect(find.text('No selection yet'), findsOneWidget);

    final group = tester.widget<RadioGroup<String?>>(
      find.byKey(ReviewSelection.overallGroupKey),
    );
    expect(group.groupValue, isNull);
  });

  testWidgets('selecting a runtime direction persists it to the repository',
      (tester) async {
    await pumpSelection(tester);

    await tester.tap(find.text('Beta Direction'));
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, 'b');
    final persisted = await repository.load('prototype-demo');
    expect(persisted, isNotNull);
    expect(persisted!.selectedDirection, 'b');
  });

  testWidgets('runtime default direction is not auto-selected on first render',
      (tester) async {
    expect(runtime.defaultDirection, 'a');

    await pumpSelection(tester);

    expect(controller.state.selectedDirection, isNull);
    final group = tester.widget<RadioGroup<String?>>(
      find.byKey(ReviewSelection.overallGroupKey),
    );
    expect(group.groupValue, isNull);
    expect(overallDirectionValues(tester), contains('a'));
  });

  testWidgets('choosing a screen mix updates only that screen and persists',
      (tester) async {
    await controller.setScreenDirection('commerce.home', 'a');
    await pumpSelection(tester);
    expect(controller.state.screenSelections, {
      'commerce.home': ReviewScreenDecision(direction: 'a'),
    });

    final searchGroup = find.byKey(ReviewSelection.screenGroupKey('commerce.search'));
    await tester.tap(find.descendant(of: searchGroup, matching: find.text('B')));
    await tester.pumpAndSettle();

    expect(controller.state.screenSelections['commerce.search']!.direction, 'b');
    expect(controller.state.screenSelections['commerce.home']!.direction, 'a');
    expect(
      controller.state.screenSelections.keys.toSet(),
      {'commerce.home', 'commerce.search'},
    );

    final persisted = await repository.load('prototype-demo');
    expect(persisted, isNotNull);
    expect(persisted!.screenSelections['commerce.search']!.direction, 'b');
    expect(persisted.screenSelections['commerce.home']!.direction, 'a');
  });

  testWidgets('clear selection resets overall direction but keeps the mix',
      (tester) async {
    await controller.selectDirection('b');
    await controller.setScreenDirection('commerce.search', 'a');
    await pumpSelection(tester);

    await tester.tap(find.text('Clear selection'));
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
    expect(controller.state.screenSelections['commerce.search']!.direction, 'a');

    final persisted = await repository.load('prototype-demo');
    expect(persisted, isNotNull);
    expect(persisted!.selectedDirection, isNull);
    expect(persisted.screenSelections['commerce.search']!.direction, 'a');
  });

  testWidgets('direction options come only from the runtime directions',
      (tester) async {
    await pumpSelection(tester);

    final overallValues = overallDirectionValues(tester);
    expect(overallValues, equals(runtime.allowedDirections.toSet()));
    expect(overallValues.difference(runtime.directions.keys.toSet()), isEmpty);

    final searchSegments = tester
        .widget<SegmentedButton<String>>(
          find.byKey(ReviewSelection.screenGroupKey('commerce.search')),
        )
        .segments
        .map((segment) => segment.value)
        .toSet();
    // Screen options are restricted to directions that expose the screen:
    // commerce.search is declared by a and b only.
    expect(searchSegments, equals(<String>{'a', 'b'}));
    expect(searchSegments.difference(runtime.directions.keys.toSet()), isEmpty);
  });

  testWidgets('selecting a screen direction does not mutate runtime directions',
      (tester) async {
    final patternsSnapshot = {
      for (final entry in runtime.directions.entries)
        entry.key: List<String>.of(entry.value.patterns),
    };
    final instances = Map<String, PrototypeDirection>.of(runtime.directions);

    await pumpSelection(tester);
    final searchGroup = find.byKey(ReviewSelection.screenGroupKey('commerce.search'));
    await tester.tap(find.descendant(of: searchGroup, matching: find.text('B')));
    await tester.pumpAndSettle();

    expect(controller.state.screenSelections['commerce.search']!.direction, 'b');
    expect(runtime.directions.keys.toSet(), equals(patternsSnapshot.keys.toSet()));
    for (final id in patternsSnapshot.keys) {
      expect(identical(runtime.directions[id], instances[id]), isTrue);
      expect(runtime.directions[id]!.patterns, equals(patternsSnapshot[id]));
    }
  });

  testWidgets('deselecting a screen mix clears only that screen', (tester) async {
    await controller.setScreenDirection('commerce.search', 'b');
    await controller.setScreenDirection('commerce.home', 'a');
    await pumpSelection(tester);

    final searchGroup = find.byKey(ReviewSelection.screenGroupKey('commerce.search'));
    await tester.tap(find.descendant(of: searchGroup, matching: find.text('B')));
    await tester.pumpAndSettle();

    expect(controller.state.screenSelections.containsKey('commerce.search'), isFalse);
    expect(controller.state.screenSelections['commerce.home']!.direction, 'a');
    expect(
      (await repository.load('prototype-demo'))!.screenSelections.containsKey('commerce.search'),
      isFalse,
    );
  });

  testWidgets('renders a section-only decision without crashing', (tester) async {
    // A canonical v2 screen may carry section overrides with no explicit screen
    // direction (inherited). The selection UI must not force-unwrap a null
    // direction.
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: repository,
      runtime: runtime,
      initialState: ReviewState(
        version: ReviewState.currentVersion,
        clientId: runtime.clientId,
        reviewRound: 1,
        status: ReviewStatus.inReview,
        selectedDirection: 'a',
        screenSelections: {
          'commerce.search': ReviewScreenDecision(
            sections: const {'search.results-grid': 'b'},
          ),
        },
        comments: const [],
      ),
    );

    await pumpSelection(tester);

    expect(tester.takeException(), isNull);
    expect(controller.state.screenSelections['commerce.search']!.direction, isNull);
  });

  testWidgets('only offers directions that expose the screen', (tester) async {
    await pumpSelection(tester);

    final homeSegments = tester
        .widget<SegmentedButton<String>>(
          find.byKey(ReviewSelection.screenGroupKey('commerce.home')),
        )
        .segments
        .map((segment) => segment.value)
        .toList();

    // commerce.home is declared only by direction a; offering b/c would now be
    // rejected by the validating controller.
    expect(homeSegments, equals(<String>['a']));
    expect(tester.takeException(), isNull);
  });
}
