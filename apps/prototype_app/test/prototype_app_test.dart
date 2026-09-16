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

  testWidgets('malformed fixture data renders a governed error', (tester) async {
    final fixtures = defaultFixtures();
    (fixtures['products'] as List)[0].remove('name');
    final runtime = PrototypeRuntime.fromMap(canonicalBundle(fixtures: fixtures));

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    expect(find.byType(RuntimeErrorScreen), findsOneWidget);
    expect(find.textContaining('Invalid runtime fixtures'), findsOneWidget);
  });

  testWidgets('a product pattern with an empty fixture pack does not crash',
      (tester) async {
    final bundle = canonicalBundle();
    ((bundle['directions'] as Map)['a'] as Map)['patterns'] = ['commerce.pdp'];
    (bundle['fixtures'] as Map)['products'] = <dynamic>[];
    final runtime = PrototypeRuntime.fromMap(bundle);

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('No products available'), findsOneWidget);
  });

  testWidgets('renders with the bundle resolved theme, not a seed fallback',
      (tester) async {
    final runtime = PrototypeRuntime.fromMap(canonicalBundle());

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, const Color(0xFF1155CC));
    expect(app.theme!.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
  });

  testWidgets('uses the active direction theme when the bundle declares one',
      (tester) async {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(directionThemes: {
        'a': resolvedThemeMap(primary: '#AA0000'),
      }),
    );

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, const Color(0xFFAA0000));
  });

  testWidgets('switching directions swaps the active direction theme',
      (tester) async {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(directionThemes: {
        'a': resolvedThemeMap(primary: '#AA0000'),
        'b': resolvedThemeMap(primary: '#00AA00'),
      }),
    );

    await tester.pumpWidget(PrototypeApp(runtime: runtime, requestedDirection: 'a'));

    Color primaryOf() => tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .colorScheme
        .primary;

    expect(primaryOf(), const Color(0xFFAA0000));

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(primaryOf(), const Color(0xFF00AA00));
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
