import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tokens expose semantic spacing and radius', () {
    expect(AgencyTokens.spaceMd, greaterThan(AgencyTokens.spaceSm));
    expect(AgencyTokens.radiusMd, greaterThan(0));
  });

  test('theme factory returns Material 3 theme', () {
    final theme = AgencyTheme.lightDefault();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, isNotNull);
    expect(theme.extension<AgencyThemeTokens>(), isNotNull);
  });

  testWidgets('agency button renders label and callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: AgencyTheme.lightDefault(),
      home: Scaffold(
        body: AgencyButton(label: 'Continue', onPressed: () => tapped = true),
      ),
    ));
    await tester.tap(find.text('Continue'));
    expect(tapped, isTrue);
  });
}
