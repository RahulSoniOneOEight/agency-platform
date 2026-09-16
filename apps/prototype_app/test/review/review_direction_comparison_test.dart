import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_direction_comparison.dart';
import 'package:prototype_app/review/review_direction_summary.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime buildRuntime({List<String> directionIds = const ['a', 'b']}) {
  return PrototypeRuntime.fromMap(canonicalBundle(directionIds: directionIds));
}

void main() {
  late PrototypeRuntime runtime;
  late ReviewController controller;

  setUp(() {
    runtime = buildRuntime(directionIds: const ['a', 'b', 'c']);
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
        screenSelections: const <String, String>{},
        comments: const <ReviewComment>[],
      ),
    );
  }

  Future<void> pumpComparison(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewDirectionComparison(
            runtime: runtime,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the actual runtime directions in runtime order',
      (tester) async {
    // Non-alphabetical declared order, so a sort()/reorder regression is
    // detectable: a sorted implementation would put 'a' leftmost.
    runtime = buildRuntime(directionIds: const ['c', 'a', 'b']);
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );

    await pumpComparison(tester, const Size(1200, 800));

    expect(runtime.allowedDirections, equals(<String>['c', 'a', 'b']));
    for (final id in runtime.allowedDirections) {
      expect(find.byKey(ReviewDirectionSummary.cardKey(id)), findsOneWidget);
    }

    final dx = [
      for (final id in runtime.allowedDirections)
        tester.getTopLeft(find.byKey(ReviewDirectionSummary.cardKey(id))).dx,
    ];
    expect(dx[0] < dx[1], isTrue);
    expect(dx[1] < dx[2], isTrue);
  });

  testWidgets('compact preview starts on the runtime default direction',
      (tester) async {
    // Default direction 'a' is deliberately not the first declared direction.
    runtime = buildRuntime(directionIds: const ['c', 'a', 'b']);
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );

    await pumpComparison(tester, const Size(400, 800));

    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsNothing);
    expect(find.byKey(ReviewDirectionSummary.cardKey('b')), findsNothing);
  });

  testWidgets('restored selection seeds the compact preview', (tester) async {
    // Default direction 'a' is deliberately not the first declared direction.
    runtime = buildRuntime(directionIds: const ['c', 'a', 'b']);
    controller = controllerWith('c');

    await pumpComparison(tester, const Size(400, 800));

    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsNothing);
  });

  testWidgets('runtime default is used only when no selection exists',
      (tester) async {
    runtime = buildRuntime(directionIds: const ['c', 'a', 'b']);
    controller = controllerWith(null);

    await pumpComparison(tester, const Size(400, 800));

    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsNothing);
    expect(controller.state.selectedDirection, isNull);
  });

  testWidgets('a selection restored after the first build seeds the preview',
      (tester) async {
    runtime = buildRuntime(directionIds: const ['c', 'a', 'b']);
    controller = controllerWith(null);

    await pumpComparison(tester, const Size(400, 800));
    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsOneWidget);

    await controller.selectDirection('c');
    await tester.pumpAndSettle();

    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsNothing);
  });

  testWidgets('a user preview wins over a later selection and never selects',
      (tester) async {
    await pumpComparison(tester, const Size(400, 800));

    await tester.tap(
      find.descendant(
        of: find.byKey(ReviewComparisonLayout.switcherKey),
        matching: find.text('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
    expect(find.byKey(ReviewDirectionSummary.cardKey('b')), findsOneWidget);

    await controller.selectDirection('c');
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, 'c');
    expect(find.byKey(ReviewDirectionSummary.cardKey('b')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsNothing);
  });

  testWidgets('works with a two-direction runtime', (tester) async {
    runtime = buildRuntime(directionIds: const ['a', 'b']);
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );

    await pumpComparison(tester, const Size(1200, 800));

    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('b')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsNothing);
  });

  testWidgets('wide surface shows every direction summary side by side',
      (tester) async {
    await pumpComparison(tester, const Size(1200, 800));

    final tops = [
      for (final id in runtime.allowedDirections)
        tester.getTopLeft(find.byKey(ReviewDirectionSummary.cardKey(id))).dy,
    ];
    expect(tops[0], tops[1]);
    expect(tops[1], tops[2]);
    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsNothing);
  });

  testWidgets('compact surface shows the switcher and only the active summary',
      (tester) async {
    await pumpComparison(tester, const Size(400, 800));

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('b')), findsNothing);
    expect(find.byKey(ReviewDirectionSummary.cardKey('c')), findsNothing);
  });

  testWidgets('switching the preview does not select a direction',
      (tester) async {
    await pumpComparison(tester, const Size(400, 800));

    expect(controller.state.selectedDirection, isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(ReviewComparisonLayout.switcherKey),
        matching: find.text('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
    expect(find.byKey(ReviewDirectionSummary.cardKey('b')), findsOneWidget);
    expect(find.byKey(ReviewDirectionSummary.cardKey('a')), findsNothing);
  });

  testWidgets('explicit selection routes through the controller',
      (tester) async {
    await pumpComparison(tester, const Size(1200, 800));

    final button = find.byKey(ReviewDirectionSummary.selectButtonKey('b'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, 'b');
    expect(find.text('Selected'), findsOneWidget);
  });

  testWidgets('renders no ranking or recommendation vocabulary',
      (tester) async {
    final banned = RegExp(
      'best|recommend|winner|rank|score|rating|prefer|favorite|better|ideal',
      caseSensitive: false,
    );

    await pumpComparison(tester, const Size(1200, 800));
    expect(find.textContaining(banned), findsNothing);

    await pumpComparison(tester, const Size(400, 800));
    expect(find.textContaining(banned), findsNothing);
  });

  testWidgets('renders without overflow at a narrow compact width',
      (tester) async {
    await pumpComparison(tester, const Size(360, 800));

    expect(tester.takeException(), isNull);
  });
}
