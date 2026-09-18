import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DomainFailure', () {
    test('retains stable machine fields', () {
      final failure = DomainFailure(
        code: DomainFailureCode.unavailable,
        operation: 'load_catalog',
        retryable: true,
        message: 'Service unavailable',
        correlationId: 'req-1',
      );

      expect(failure.code, DomainFailureCode.unavailable);
      expect(failure.operation, 'load_catalog');
      expect(failure.retryable, isTrue);
      expect(failure.message, 'Service unavailable');
      expect(failure.correlationId, 'req-1');
    });

    test('is a throwable Exception', () {
      final failure = DomainFailure(
        code: DomainFailureCode.timeout,
        operation: 'load_catalog',
        retryable: true,
        message: 'Timed out',
      );

      expect(failure, isA<Exception>());
      expect(() => throw failure, throwsA(same(failure)));
      expect(failure.correlationId, isNull);
    });

    test('exposes exactly the governed failure codes', () {
      expect(
        DomainFailureCode.values.map((code) => code.name).toList(),
        <String>[
          'unauthorized',
          'forbidden',
          'validation',
          'conflict',
          'unavailable',
          'timeout',
          'staleData',
          'unknown',
        ],
      );
    });

    test('distinguishes retryable from non-retryable failures', () {
      final timeoutFailure = DomainFailure(
        code: DomainFailureCode.timeout,
        operation: 'load_catalog',
        retryable: true,
        message: 'Timed out',
      );
      final validationFailure = DomainFailure(
        code: DomainFailureCode.validation,
        operation: 'place_order',
        retryable: false,
        message: 'Invalid cart',
      );

      expect(timeoutFailure.retryable, isTrue);
      expect(validationFailure.retryable, isFalse);
    });
  });
}
