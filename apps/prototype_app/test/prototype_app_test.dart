import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/prototype_app.dart';

void main() {
  testWidgets('prototype app renders direction selector and active direction', (tester) async {
    await tester.pumpWidget(const PrototypeApp(initialDirection: 'b'));
    expect(find.text('Direction B'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });
}
