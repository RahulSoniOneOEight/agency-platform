import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry resolves canonical pattern ids', () {
    expect(PatternRegistry.resolve('home'), isNotNull);
    expect(PatternRegistry.resolve('rfq'), isNotNull);
    expect(PatternRegistry.resolve('trade-dashboard'), isNotNull);
  });

  test('registry rejects unknown pattern ids', () {
    expect(() => PatternRegistry.resolve('made-up-pattern'), throwsArgumentError);
  });
}
