import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_shell.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Reference runtime with three directions and multiple governed patterns, so
/// the shell has real directions and a real governed screen registry to expose.
PrototypeRuntime buildReviewRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
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
    );

Widget wrap(PrototypeRuntime runtime, ReviewController controller) => MaterialApp(
      home: ReviewShell(runtime: runtime, controller: controller),
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
    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Directions');

    await tester.tap(find.text('Beta Direction').first);
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, isNull);
  });

  testWidgets('Select this direction persists the previewed direction', (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Directions');

    await tester.tap(find.text('Beta Direction').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select this direction'));
    await tester.pumpAndSettle();

    expect(controller.state.selectedDirection, 'b');
  });

  testWidgets('screens renders a governed screen label and the comparison host',
      (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Screens');

    expect(find.byType(ReviewComparisonHost), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('selection and comments render real read-only summaries', (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Selection');

    expect(find.text('Overall direction: Not selected'), findsOneWidget);
    expect(find.text('No screens mixed yet.'), findsOneWidget);

    await tapDestination(tester, 'Comments');

    expect(find.text('Comment count: 0'), findsOneWidget);
    expect(find.text('No comments yet.'), findsOneWidget);
  });

  testWidgets('switching destinations preserves the controller selection', (tester) async {
    await tester.pumpWidget(wrap(runtime, controller));
    await tapDestination(tester, 'Directions');
    await tester.tap(find.text('Beta Direction').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select this direction'));
    await tester.pumpAndSettle();

    await tapDestination(tester, 'Overview');
    expect(find.text('Overall direction: b'), findsOneWidget);

    await tapDestination(tester, 'Selection');
    expect(find.text('Overall direction: b'), findsOneWidget);

    expect(controller.state.selectedDirection, 'b');
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
}
