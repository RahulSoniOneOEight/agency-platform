import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReleaseOutcome exposes healthy, degraded, and failed', () {
    expect(ReleaseOutcome.values, hasLength(3));
    expect(
      ReleaseOutcome.values,
      containsAll(<ReleaseOutcome>[
        ReleaseOutcome.healthy,
        ReleaseOutcome.degraded,
        ReleaseOutcome.failed,
      ]),
    );
  });

  test('ReleaseOutcome values are distinct', () {
    expect(ReleaseOutcome.healthy, isNot(ReleaseOutcome.degraded));
    expect(ReleaseOutcome.degraded, isNot(ReleaseOutcome.failed));
    expect(ReleaseOutcome.healthy, isNot(ReleaseOutcome.failed));
    expect(
      ReleaseOutcome.values.toSet(),
      hasLength(ReleaseOutcome.values.length),
    );
  });
}
