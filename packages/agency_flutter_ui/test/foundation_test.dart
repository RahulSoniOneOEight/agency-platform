import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tokens expose semantic spacing and radius', () {
    expect(AgencyTokens.spaceMd, greaterThan(AgencyTokens.spaceSm));
    expect(AgencyTokens.radiusMd, greaterThan(0));
  });

  test('theme factory returns Material 3 theme', () {
    final theme = AgencyTheme.light(seedColor: const Color(0xFF6750A4));
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, isNotNull);
  });

  testWidgets('agency button renders label and callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgencyButton(label: 'Continue', onPressed: () => tapped = true),
      ),
    ));
    await tester.tap(find.text('Continue'));
    expect(tapped, isTrue);
  });
}
