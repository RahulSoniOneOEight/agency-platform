import 'package:agency_production_core/agency_production_core.dart';

import 'fake_integration_scenario.dart';

/// Deterministic fake payment provider.
///
/// Honors the caller's [IdempotencyKey]: re-submitting the same key returns the
/// exact result of the original request, so a retry cannot create a second
/// authorization or refund. Provider faults are surfaced only as a
/// provider-neutral [DomainFailure].
final class FakePaymentAdapter implements PaymentPort {
  FakePaymentAdapter({this.scenario = FakeIntegrationScenario.success});

  final FakeIntegrationScenario scenario;
  final FakeIdempotencyStore _store = FakeIdempotencyStore();
  final Map<String, String> _authorizedCurrencies = {};

  @override
  Future<PaymentResult> authorizePayment({
    required String orderId,
    required int amountMinor,
    required String currency,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'PaymentPort.authorizePayment';
    fakeGuard(scenario, operation);
    final result = _store.resolve(operation, idempotencyKey, () {
      return PaymentResult(
        paymentId: 'pay_${orderId}_${idempotencyKey.value}',
        status: PaymentStatus.authorized,
        amountMinor: amountMinor,
        currency: currency,
      );
    });
    _authorizedCurrencies[result.paymentId] = result.currency;
    return result;
  }

  @override
  Future<PaymentResult> refundPayment({
    required String paymentId,
    required int amountMinor,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'PaymentPort.refundPayment';
    fakeGuard(scenario, operation);
    return _store.resolve(operation, idempotencyKey, () {
      return PaymentResult(
        paymentId: paymentId,
        status: PaymentStatus.refunded,
        amountMinor: amountMinor,
        currency: _authorizedCurrencies[paymentId] ?? 'USD',
      );
    });
  }
}
