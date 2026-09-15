import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/prototype_app.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';
import 'package:prototype_app/runtime/runtime_exception.dart';
import 'package:prototype_app/screens/runtime_error_screen.dart';

import 'support/runtime_fixtures.dart';

void main() {
  testWidgets('two-direction runtime renders only A and B', (tester) async {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(directionIds: const ['a', 'b']),
    );

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsNothing);
  });

  testWidgets('three-direction runtime renders A, B and C', (tester) async {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(directionIds: const ['a', 'b', 'c']),
    );

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('selecting a direction updates the title and strategic goal', (tester) async {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(
        directionIds: const ['a', 'b'],
        names: const {'a': 'Search-led', 'b': 'Dashboard-led'},
        strategicGoals: const {'a': 'goal-a', 'b': 'goal-b'},
      ),
    );

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    expect(find.text('Search-led'), findsOneWidget);
    expect(find.textContaining('goal-a'), findsOneWidget);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard-led'), findsOneWidget);
    expect(find.textContaining('goal-b'), findsOneWidget);
  });

  testWidgets('missing direction falls back to the runtime default', (tester) async {
    final runtime = PrototypeRuntime.fromMap(canonicalBundle());

    await tester.pumpWidget(PrototypeApp(runtime: runtime));

    expect(find.byType(RuntimeErrorScreen), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('unknown explicit direction renders a governed error, not direction A',
      (tester) async {
    final runtime = PrototypeRuntime.fromMap(canonicalBundle());

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'z'));

    expect(find.byType(RuntimeErrorScreen), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.textContaining('Direction "z" is not available'), findsOneWidget);
  });

  testWidgets('runtime error screen shows the client without a stack trace',
      (tester) async {
    const error = RuntimeException(
      code: RuntimeException.clientNotFound,
      message: 'No generated runtime bundle for client "ghost".',
      clientId: 'ghost',
    );

    await tester.pumpWidget(const MaterialApp(home: RuntimeErrorScreen(error: error)));

    expect(find.textContaining('ghost'), findsWidgets);
    expect(find.textContaining('RuntimeException'), findsNothing);
    expect(find.textContaining('#0'), findsNothing);
  });
}
