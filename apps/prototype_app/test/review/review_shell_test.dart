import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_direction_summary.dart';
import 'package:prototype_app/review/review_selection.dart';
import 'package:prototype_app/review/review_shell.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

const ReviewActor _reviewer = ReviewActor(
  id: 'reviewer-1',
  name: 'Reviewer',
  role: ReviewRole.reviewer,
);

/// Reference runtime with three directions and multiple governed patterns, so
/// the shell has real directions and a real governed screen registry to expose.
PrototypeRuntime buildReviewRuntime({Map<String, Object?>? theme}) {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      theme: theme,
      directionIds: const ['a', 'b', 'c'],
      names: const {
        'a': 'Alpha Direction',
        'b': 'Beta Direction',
        'c': 'Gamma Direction',
      },
      strategicGoals: const {
        'a': 'reduce known-item order time',
        'b': 'expand discovery breadth',
        'c': 'grow average basket size',
      },
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
    ),
  );
}

ReviewController buildController(PrototypeRuntime runtime) => ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );

Widget wrap(PrototypeRuntime runtime, ReviewController controller) => MaterialApp(
      home: ReviewShell(
        runtime: runtime,
        controller: controller,
        coordinator: ReviewCoordinator(
          controller: controller,
          feedbackRepository: MemoryFeedbackRepository(),
          approvalRepository: MemoryApprovalRepository(),
        ),
        actor: _reviewer,
      ),
    );

Future<void> tapDestination(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  late PrototypeRuntime runtime;
  late ReviewController controller;

  setUp(() {
    runtime = buildReviewRuntime();
    controller = buildController(runtime);
  });

  testWidgets('renders all five review destinations', (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tester.pumpAndSettle();

    for (final label in const [
      'Overview',
      'Directions',
      'Screens',
      'Selection',
      'Comments',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing destination $label');
    }
  });

  testWidgets('overview renders client identity, round, status and no selection',
      (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tester.pumpAndSettle();

    expect(find.text('Client: prototype-demo'), findsOneWidget);
    expect(find.text('Review round: 1'), findsOneWidget);
    expect(find.text('Status: in_review'), findsOneWidget);
    expect(find.text('Overall direction: Not selected'), findsOneWidget);
    expect(find.text('Mixed screens: 0'), findsOneWidget);
    expect(find.text('Comments: 0'), findsOneWidget);
  });

  testWidgets('no overall direction is auto-selected on first render', (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
    expect(find.text('Overall direction: Not selected'), findsOneWidget);
  });

  testWidgets('directions lists the actual runtime directions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Directions');

    expect(find.text('Alpha Direction'), findsWidgets);
    expect(find.text('Beta Direction'), findsWidgets);
    expect(find.text('Gamma Direction'), findsWidgets);
    expect(find.textContaining('reduce known-item order time'), findsWidgets);
    expect(find.textContaining('expand discovery breadth'), findsWidgets);
    expect(find.textContaining('grow average basket size'), findsWidgets);
  });

  testWidgets('previewing a direction does not select it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Directions');

    await tester.tap(
      find.descendant(
        of: find.byKey(ReviewComparisonLayout.switcherKey),
        matching: find.text('B'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
  });

  testWidgets('explicit per-direction select routes through the controller',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Directions');

    final button = find.byKey(ReviewDirectionSummary.selectButtonKey('b'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, 'b');
  });

  testWidgets('screens renders a governed screen label and the comparison host',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Compact spacing keeps the reviewed product card within its grid cell at
    // comparison panel width (the shared ProductCard's fixed grid extent is not
    // a C.2 concern and is unchanged here).
    final screensRuntime = buildReviewRuntime(
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
    );
    final screensController = buildController(screensRuntime);

    await tester.pumpWidget(wrap(screensRuntime, screensController));
    await tapDestination(tester, 'Screens');

    expect(find.byType(ReviewComparisonHost), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('selection workspace and comments render real summaries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Selection');

    expect(find.text('Overall: Not selected'), findsOneWidget);
    expect(find.text('Screen mix'), findsOneWidget);
    expect(find.byKey(ReviewSelection.previewHostKey), findsOneWidget);

    await tapDestination(tester, 'Comments');

    expect(find.text('Comment count: 0'), findsOneWidget);
    expect(find.text('No comments yet.'), findsOneWidget);
  });

  testWidgets('navigating destinations never mutates saved mix decisions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Compact spacing keeps the reviewed product cards within their cells while
    // the Screens comparison surface is visited.
    final navRuntime = buildReviewRuntime(
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
    );
    final navController = buildController(navRuntime);
    await navController.selectDirection('a');
    await navController.setScreenDirection('commerce.plp', 'c');

    await tester.pumpWidget(wrap(navRuntime, navController));
    await tester.pumpAndSettle();

    for (final label in const [
      'Screens',
      'Directions',
      'Overview',
      'Comments',
      'Selection',
    ]) {
      await tapDestination(tester, label);
    }

    expect(navController.state.selectedDirection, 'a');
    expect(navController.state.screenSelections.length, 1);
    expect(navController.state.screenSelections['commerce.plp']!.direction, 'c');
  });

  testWidgets('switching destinations preserves the controller selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The Selection destination renders the live mixed preview; compact spacing
    // keeps the shared ProductCard within its grid cell at panel width.
    final compactRuntime = buildReviewRuntime(
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
    );
    final compactController = buildController(compactRuntime);

    await tester.pumpWidget(wrap(compactRuntime, compactController));
    await tapDestination(tester, 'Directions');

    final button = find.byKey(ReviewDirectionSummary.selectButtonKey('b'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    await tapDestination(tester, 'Overview');
    expect(find.text('Overall direction: b'), findsOneWidget);

    await tapDestination(tester, 'Selection');
    expect(find.text('Overall: B'), findsOneWidget);

    expect(compactController.state.selectedDirection, 'b');
  });

  testWidgets('uses a NavigationBar at compact widths and a NavigationRail when wide',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(runtime, controller));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('renders the Screens destination at a compact phone width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Compact spacing keeps the reviewed product card within its grid cell at
    // phone width (the shared ProductCard's fixed grid extent is not a C.1
    // concern and is unchanged here).
    final compactRuntime = buildReviewRuntime(
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
    );
    final compactController = buildController(compactRuntime);

    await tester.pumpWidget(wrap(compactRuntime, compactController));
    await tester.pumpAndSettle();
    await tapDestination(tester, 'Screens');

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(ReviewComparisonHost), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
