import 'package:agency_widgetbook/widgetbook_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';

void main() {
  testWidgets('agency Widgetbook exposes the component library', (tester) async {
    await tester.pumpWidget(buildAgencyWidgetbook());
    expect(find.byType(Widgetbook), findsOneWidget);
  });
}
