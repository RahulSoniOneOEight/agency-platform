import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_mixed_preview.dart';
import 'package:prototype_app/review/review_selection.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// `commerce.plp` is declared by `a` and `c` only and both expose
/// `commerce.product-card`, so a real cross-direction section mix exists for it.
/// `commerce.search` is declared by `b` only. The `a` and `c` themes differ so
/// the source-direction theme of a section override is observable.
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
            primary: '#CC1155', cardSpacing: 12, tileGap: 8, cardRadius: 28),
      },
    ),
  );
}

void main() {
  late PrototypeRuntime runtime;
  late FixtureRepository fixtures;
  late MemoryReviewRepository repository;
  late ReviewController controller;

  setUp(() {
    runtime = buildSelectionRuntime();
    fixtures = FixtureRepository.fromRuntime(runtime);
    repository = MemoryReviewRepository();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: repository,
      runtime: runtime,
    );
  });

  Future<void> pumpSelection(
    WidgetTester tester, {
    Size size = const Size(1200, 2400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewSelection(
            runtime: runtime,
            controller: controller,
            fixtures: fixtures,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapOption(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder optionText(Key groupKey, String text) => find.descendant(
        of: find.byKey(groupKey),
        matching: find.text(text),
      );

  RadioListTile<String?> tileWithValue(
    WidgetTester tester,
    Key groupKey,
    String? value,
  ) {
    return tester.widget<RadioListTile<String?>>(
      find.descendant(
        of: find.byKey(groupKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is RadioListTile<String?> && widget.value == value,
        ),
      ),
    );
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

  testWidgets('overall selection is nullable and never silently defaults',
      (tester) async {
    await pumpSelection(tester);

    expect(runtime.defaultDirection, 'a');
    expect(controller.state.selectedDirection, isNull);
    expect(find.text('No selection yet'), findsOneWidget);
    expect(find.text('Overall: Not selected'), findsOneWidget);

    final group = tester.widget<RadioGroup<String?>>(
      find.byKey(ReviewSelection.overallGroupKey),
    );
    expect(group.groupValue, isNull);
    expect(overallDirectionValues(tester), containsAll(<String>['a', 'b', 'c']));
  });

  testWidgets('selecting a runtime direction persists it through the controller',
      (tester) async {
    await pumpSelection(tester);

    await tapOption(tester, find.text('Beta Direction'));

    expect(controller.state.selectedDirection, 'b');
    expect(find.text('Overall: B'), findsOneWidget);
    final persisted = await repository.load('prototype-demo');
    expect(persisted, isNotNull);
    expect(persisted!.selectedDirection, 'b');
  });

  testWidgets('screen chooser offers inherit-from-overall plus every direction',
      (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester);

    final groupKey = ReviewSelection.screenGroupKey('commerce.plp');
    expect(optionText(groupKey, 'Inherit from overall (A)'), findsOneWidget);
    for (final id in const ['A', 'B', 'C']) {
      expect(optionText(groupKey, 'Direction $id'), findsOneWidget);
    }
    // The inherit option is selected while the screen has no explicit override.
    expect(tileWithValue(tester, groupKey, null).value, isNull);
  });

  testWidgets('a direction that does not declare the screen is disabled with a reason',
      (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester);

    final groupKey = ReviewSelection.screenGroupKey('commerce.plp');
    expect(tileWithValue(tester, groupKey, 'b').enabled, isFalse);
    expect(
      optionText(groupKey, 'Direction B does not include Product listing'),
      findsOneWidget,
    );
    expect(tileWithValue(tester, groupKey, 'a').enabled, isTrue);
    expect(tileWithValue(tester, groupKey, 'c').enabled, isTrue);
  });

  testWidgets('explicit screen override persists and clearing restores inheritance',
      (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester);

    final groupKey = ReviewSelection.screenGroupKey('commerce.plp');
    await tapOption(tester, optionText(groupKey, 'Direction C'));

    expect(controller.state.screenSelections['commerce.plp']!.direction, 'c');
    expect(find.text('Base: C (Explicit)'), findsOneWidget);
    expect(
      (await repository.load('prototype-demo'))!
          .screenSelections['commerce.plp']!
          .direction,
      'c',
    );

    await tapOption(tester, optionText(groupKey, 'Inherit from overall (A)'));

    expect(controller.state.screenSelections.containsKey('commerce.plp'), isFalse);
    expect(find.text('Base: A (Inherited)'), findsWidgets);
    expect(
      (await repository.load('prototype-demo'))!
          .screenSelections
          .containsKey('commerce.plp'),
      isFalse,
    );
  });

  testWidgets('section chooser offers inherit plus every direction with reasons',
      (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester);

    final groupKey =
        ReviewSelection.sectionGroupKey('commerce.plp', 'plp.product-grid');
    expect(
      optionText(groupKey, 'Inherit from Product listing (A)'),
      findsOneWidget,
    );
    expect(tileWithValue(tester, groupKey, null).enabled, isTrue);
    expect(tileWithValue(tester, groupKey, 'a').enabled, isTrue);
    expect(tileWithValue(tester, groupKey, 'c').enabled, isTrue);
    expect(tileWithValue(tester, groupKey, 'b').enabled, isFalse);
    expect(optionText(groupKey, 'Not present in Direction B'), findsOneWidget);
  });

  testWidgets('an explicit section override persists and updates the live preview',
      (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester);

    final groupKey =
        ReviewSelection.sectionGroupKey('commerce.plp', 'plp.product-grid');
    await tapOption(tester, optionText(groupKey, 'Direction C'));

    expect(
      controller.state.screenSelections['commerce.plp']!.sections['plp.product-grid'],
      'c',
    );
    expect(
      (await repository.load('prototype-demo'))!
          .screenSelections['commerce.plp']!
          .sections['plp.product-grid'],
      'c',
    );

    expect(find.byKey(ReviewSelection.previewHostKey), findsOneWidget);
    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.product-grid')),
      findsOneWidget,
    );

    final source = AgencyTheme.light(runtime.themeForDirection('c'));
    final gridTheme = Theme.of(tester.element(
      find.descendant(
        of: find.byKey(ReviewMixedPreview.sectionKey('plp.product-grid')),
        matching: find.byType(ProductGridSection),
      ),
    ));
    expect(gridTheme.colorScheme.primary, source.colorScheme.primary);
  });

  testWidgets('clearing a section override restores inheritance and the preview',
      (tester) async {
    await controller.selectDirection('a');
    await controller.setSectionDirection('commerce.plp', 'plp.product-grid', 'c');
    await pumpSelection(tester);

    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.product-grid')),
      findsOneWidget,
    );

    final groupKey =
        ReviewSelection.sectionGroupKey('commerce.plp', 'plp.product-grid');
    await tapOption(tester, optionText(groupKey, 'Inherit from Product listing (A)'));

    expect(controller.state.screenSelections.containsKey('commerce.plp'), isFalse);
    expect(
      (await repository.load('prototype-demo'))!
          .screenSelections
          .containsKey('commerce.plp'),
      isFalse,
    );
    expect(
      find.byKey(ReviewMixedPreview.overrideThemeKey('plp.product-grid')),
      findsNothing,
    );
    expect(find.text('Product grid: A (Inherited)'), findsWidgets);
  });

  testWidgets('reset screen mix requires confirmation and removes all overrides',
      (tester) async {
    await controller.selectDirection('a');
    await controller.setScreenDirection('commerce.plp', 'c');
    await controller.setSectionDirection('commerce.plp', 'plp.product-grid', 'a');
    await pumpSelection(tester);

    expect(controller.state.screenSelections['commerce.plp']!.direction, 'c');
    expect(
      controller.state.screenSelections['commerce.plp']!.sections['plp.product-grid'],
      'a',
    );

    final reset = find.byKey(ReviewSelection.resetScreenButtonKey('commerce.plp'));

    await tapOption(tester, reset);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tapOption(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(controller.state.screenSelections.containsKey('commerce.plp'), isTrue);

    await tapOption(tester, reset);
    await tapOption(tester, find.widgetWithText(TextButton, 'Reset'));

    expect(controller.state.screenSelections.containsKey('commerce.plp'), isFalse);
    expect(
      (await repository.load('prototype-demo'))!
          .screenSelections
          .containsKey('commerce.plp'),
      isFalse,
    );
  });

  testWidgets('effective summary distinguishes inherited and explicit values',
      (tester) async {
    await controller.selectDirection('a');
    await controller.setScreenDirection('commerce.plp', 'c');
    await pumpSelection(tester);

    expect(find.text('Overall: A'), findsOneWidget);
    expect(find.text('Base: C (Explicit)'), findsOneWidget);
    // commerce.search inherits the overall direction.
    expect(find.text('Base: A (Inherited)'), findsOneWidget);
    // commerce.plp's section inherits the explicit screen base.
    expect(find.text('Product grid: C (Inherited)'), findsOneWidget);
  });

  testWidgets('preview screen navigation never mutates saved decisions',
      (tester) async {
    await controller.selectDirection('a');
    await controller.setScreenDirection('commerce.plp', 'c');
    await pumpSelection(tester);

    final selectionsBefore = Map.of(controller.state.screenSelections);

    await tapOption(
      tester,
      find.descendant(
        of: find.byKey(ReviewSelection.previewScreenSelectorKey),
        matching: find.text('Search'),
      ),
    );

    expect(controller.state.selectedDirection, 'a');
    expect(controller.state.screenSelections, selectionsBefore);
  });

  testWidgets('renders without overflow at a compact 360px width', (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester, size: const Size(360, 900));

    expect(find.byKey(ReviewSelection.previewHostKey), findsOneWidget);
    expect(find.text('Overall: A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow at a wide width', (tester) async {
    await controller.selectDirection('a');
    await pumpSelection(tester, size: const Size(1200, 900));

    expect(find.byKey(ReviewSelection.previewHostKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting decisions never mutates the runtime directions',
      (tester) async {
    final patternsSnapshot = {
      for (final entry in runtime.directions.entries)
        entry.key: List<String>.of(entry.value.patterns),
    };
    final instances = Map.of(runtime.directions);

    await controller.selectDirection('a');
    await pumpSelection(tester);
    await tapOption(
      tester,
      optionText(ReviewSelection.screenGroupKey('commerce.plp'), 'Direction C'),
    );

    for (final id in patternsSnapshot.keys) {
      expect(identical(runtime.directions[id], instances[id]), isTrue);
      expect(runtime.directions[id]!.patterns, equals(patternsSnapshot[id]));
    }
  });
}
