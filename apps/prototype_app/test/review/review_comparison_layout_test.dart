import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';

ReviewComparisonPanel _panel(String id) {
  return ReviewComparisonPanel(
    id: id,
    label: 'Panel $id',
    child: KeyedSubtree(
      key: Key('panel-body-$id'),
      child: Text('Panel $id body'),
    ),
  );
}

List<ReviewComparisonPanel> _threePanels() =>
    <ReviewComparisonPanel>[_panel('0'), _panel('1'), _panel('2')];

Widget _host({
  required List<ReviewComparisonPanel> panels,
  int activeIndex = 0,
  ValueChanged<int>? onActiveIndexChanged,
  bool allowModeToggle = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ReviewComparisonLayout(
        panels: panels,
        activeIndex: activeIndex,
        onActiveIndexChanged: onActiveIndexChanged ?? (_) {},
        allowModeToggle: allowModeToggle,
      ),
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('wide viewport shows all panels side by side without a switcher',
      (tester) async {
    await _setSurface(tester, const Size(1200, 800));

    await tester.pumpWidget(_host(panels: _threePanels()));

    expect(find.text('Panel 0 body'), findsOneWidget);
    expect(find.text('Panel 1 body'), findsOneWidget);
    expect(find.text('Panel 2 body'), findsOneWidget);
    expect(
      find.byKey(ReviewComparisonLayout.switcherKey),
      findsNothing,
    );
  });

  testWidgets('compact viewport shows the switcher and only the active panel',
      (tester) async {
    await _setSurface(tester, const Size(400, 800));

    await tester.pumpWidget(_host(panels: _threePanels(), activeIndex: 1));

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsOneWidget);
    expect(find.text('Panel 1 body'), findsOneWidget);
    expect(find.text('Panel 0 body'), findsNothing);
    expect(find.text('Panel 2 body'), findsNothing);
  });

  testWidgets('tapping a switcher segment reports the tapped index',
      (tester) async {
    await _setSurface(tester, const Size(400, 800));
    final selected = <int>[];

    await tester.pumpWidget(
      _host(
        panels: _threePanels(),
        activeIndex: 0,
        onActiveIndexChanged: selected.add,
      ),
    );

    await tester.tap(find.text('Panel 2'));
    await tester.pumpAndSettle();

    expect(selected, equals(<int>[2]));
  });

  testWidgets('wide mode toggle switches between side-by-side and focused',
      (tester) async {
    await _setSurface(tester, const Size(1200, 800));

    await tester.pumpWidget(
      _host(panels: _threePanels(), allowModeToggle: true),
    );

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsNothing);
    expect(find.text('Panel 0 body'), findsOneWidget);
    expect(find.text('Panel 1 body'), findsOneWidget);
    expect(find.text('Panel 2 body'), findsOneWidget);

    await tester.tap(find.byKey(ReviewComparisonLayout.modeToggleKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsOneWidget);
    expect(find.text('Panel 0 body'), findsOneWidget);
    expect(find.text('Panel 1 body'), findsNothing);
    expect(find.text('Panel 2 body'), findsNothing);

    await tester.tap(find.byKey(ReviewComparisonLayout.modeToggleKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsNothing);
    expect(find.text('Panel 0 body'), findsOneWidget);
    expect(find.text('Panel 1 body'), findsOneWidget);
    expect(find.text('Panel 2 body'), findsOneWidget);
  });

  testWidgets('compact viewport never shows the mode toggle', (tester) async {
    await _setSurface(tester, const Size(400, 800));

    await tester.pumpWidget(
      _host(panels: _threePanels(), activeIndex: 2, allowModeToggle: true),
    );

    expect(find.byKey(ReviewComparisonLayout.modeToggleKey), findsNothing);
    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsOneWidget);
    expect(find.text('Panel 2 body'), findsOneWidget);
    expect(find.text('Panel 0 body'), findsNothing);
  });

  testWidgets('empty panels renders without throwing', (tester) async {
    await _setSurface(tester, const Size(1200, 800));

    await tester.pumpWidget(_host(panels: const <ReviewComparisonPanel>[]));

    expect(tester.takeException(), isNull);
    expect(find.byKey(ReviewComparisonLayout.panelKey('0')), findsNothing);
    expect(find.byKey(ReviewComparisonLayout.switcherKey), findsNothing);
  });

  testWidgets('out-of-range activeIndex renders the clamped active panel',
      (tester) async {
    await _setSurface(tester, const Size(400, 800));

    await tester.pumpWidget(
      _host(panels: <ReviewComparisonPanel>[_panel('0'), _panel('1')],
          activeIndex: 5),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Panel 1 body'), findsOneWidget);
    expect(find.text('Panel 0 body'), findsNothing);
  });

  testWidgets('negative activeIndex renders the clamped active panel',
      (tester) async {
    await _setSurface(tester, const Size(400, 800));

    await tester.pumpWidget(_host(panels: _threePanels(), activeIndex: -3));

    expect(tester.takeException(), isNull);
    expect(find.text('Panel 0 body'), findsOneWidget);
    expect(find.text('Panel 1 body'), findsNothing);
  });

  testWidgets('uses the same panel child instances in both modes',
      (tester) async {
    await _setSurface(tester, const Size(1200, 800));

    await tester.pumpWidget(
      _host(panels: _threePanels(), allowModeToggle: true),
    );

    final sideBySideChild = tester
        .widget<KeyedSubtree>(
          find.byKey(ReviewComparisonLayout.panelKey('0')),
        )
        .child;

    await tester.tap(find.byKey(ReviewComparisonLayout.modeToggleKey));
    await tester.pumpAndSettle();

    final focusedChild = tester
        .widget<KeyedSubtree>(
          find.byKey(ReviewComparisonLayout.panelKey('0')),
        )
        .child;

    expect(identical(sideBySideChild, focusedChild), isTrue);
  });
}
