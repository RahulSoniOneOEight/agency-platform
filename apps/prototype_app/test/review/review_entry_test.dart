import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/main.dart';
import 'package:prototype_app/prototype_app.dart';
import 'package:prototype_app/review/review_shell.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';
import 'package:prototype_app/runtime/runtime_exception.dart';
import 'package:prototype_app/screens/runtime_error_screen.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime _demoRuntime() => PrototypeRuntime.fromMap(canonicalBundle());

Future<PrototypeRuntime> Function(String) _loader(
  List<String> requested, {
  Set<String> failing = const {},
}) {
  return (String clientId) async {
    requested.add(clientId);
    if (failing.contains(clientId)) {
      throw RuntimeException(
        code: RuntimeException.clientNotFound,
        message: 'No generated runtime bundle for client "$clientId".',
        clientId: clientId,
      );
    }
    return _demoRuntime();
  };
}

void main() {
  testWidgets('review URL loads the requested client and renders ReviewShell',
      (tester) async {
    final requested = <String>[];

    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/review?client=prototype-demo'),
        loadRuntime: _loader(requested),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, ['prototype-demo']);
    expect(find.byType(ReviewShell), findsOneWidget);
    expect(find.textContaining('prototype-demo'), findsWidgets);
  });

  testWidgets('review URL without a client renders a governed error', (tester) async {
    final requested = <String>[];

    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/review'),
        loadRuntime: _loader(requested),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RuntimeErrorScreen), findsOneWidget);
    expect(
      find.textContaining('Review Mode requires an explicit client id'),
      findsOneWidget,
    );
    expect(requested, isEmpty);
  });

  testWidgets('normal URL still renders PrototypeApp', (tester) async {
    final requested = <String>[];

    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/?client=prototype-demo'),
        loadRuntime: _loader(requested),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, ['prototype-demo']);
    expect(find.byType(PrototypeApp), findsOneWidget);
    expect(find.byType(ReviewShell), findsNothing);
  });

  testWidgets('normal URL without a client uses the declared default client',
      (tester) async {
    final requested = <String>[];

    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/'),
        loadRuntime: _loader(requested),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, [kDefaultClientId]);
    expect(find.byType(PrototypeApp), findsOneWidget);
  });

  testWidgets('explicit unknown client renders a governed error', (tester) async {
    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/?client=ghost'),
        loadRuntime: _loader(<String>[], failing: {'ghost'}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RuntimeErrorScreen), findsOneWidget);
    expect(find.textContaining('ghost'), findsWidgets);
  });

  testWidgets('normal URL with an unknown direction never falls back to A',
      (tester) async {
    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/?client=prototype-demo&direction=z'),
        loadRuntime: _loader(<String>[]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RuntimeErrorScreen), findsOneWidget);
    expect(find.textContaining('Direction "z" is not available'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('review mode starts with no overall direction selected', (tester) async {
    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/review?client=prototype-demo'),
        loadRuntime: _loader(<String>[]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Overall direction: Not selected'), findsOneWidget);
    expect(find.textContaining('Overall direction: A'), findsNothing);
  });

  testWidgets('a direction query parameter does not select a review direction',
      (tester) async {
    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse(
          'https://example.test/review?client=prototype-demo&direction=b',
        ),
        loadRuntime: _loader(<String>[]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReviewShell), findsOneWidget);
    expect(find.textContaining('Overall direction: Not selected'), findsOneWidget);
    expect(find.textContaining('Overall direction: B'), findsNothing);
  });

  testWidgets('an empty review client is rejected governedly', (tester) async {
    await tester.pumpWidget(
      PrototypeBootstrap(
        uri: Uri.parse('https://example.test/review?client='),
        loadRuntime: _loader(<String>[]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RuntimeErrorScreen), findsOneWidget);
    expect(find.byType(ReviewShell), findsNothing);
  });
}
