import 'package:agency_integration_adapters/agency_integration_adapters.dart';
import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single mutating port operation exercised by the shared contract suite.
///
/// Each subject wires one representative externally-mutating method of an
/// adapter. [invoke] uses a fixed payload; [invokeWithDifferentPayload] uses
/// the same method with a different payload but the caller-supplied key, so the
/// suite can prove the idempotency key (not the payload) governs the result.
final class MutatingContractSubject {
  const MutatingContractSubject({
    required this.name,
    required this.build,
    required this.invoke,
    required this.invokeWithDifferentPayload,
    required this.describe,
  });

  final String name;
  final Object Function(FakeIntegrationScenario scenario) build;
  final Future<Object> Function(Object adapter, IdempotencyKey key) invoke;
  final Future<Object> Function(Object adapter, IdempotencyKey key)
      invokeWithDifferentPayload;
  final Object Function(Object result) describe;
}

/// A read-only port operation exercised for determinism and failure
/// normalization.
final class ReadContractSubject {
  const ReadContractSubject({
    required this.name,
    required this.build,
    required this.invoke,
    required this.describe,
  });

  final String name;
  final Object Function(FakeIntegrationScenario scenario) build;
  final Future<Object?> Function(Object adapter) invoke;
  final Object? Function(Object? result) describe;
}

Future<DomainFailure> captureFailure(Future<Object?> future) async {
  try {
    await future;
  } on DomainFailure catch (failure) {
    return failure;
  } catch (error) {
    fail('Expected a DomainFailure but got ${error.runtimeType}: $error');
  }
  fail('Expected a DomainFailure but the call succeeded');
}

final _keyA = IdempotencyKey('key-a');
final _keyB = IdempotencyKey('key-b');

Order _order(String id) => Order(
      id: id,
      items: [
        OrderItem(
          productId: 'product-1',
          variantId: 'variant-1',
          quantity: 2,
          unitPriceMinor: 500,
        ),
      ],
    );

Rfq _rfq(String id) => Rfq(
      id: id,
      accountId: 'account-1',
      items: [
        CartItem(
          productId: 'product-1',
          variantId: 'variant-1',
          quantity: 2,
          unitPriceMinor: 500,
        ),
      ],
    );

final List<MutatingContractSubject> mutatingSubjects = [
  MutatingContractSubject(
    name: 'FakePaymentAdapter.authorizePayment',
    build: (scenario) => FakePaymentAdapter(scenario: scenario),
    invoke: (adapter, key) => (adapter as FakePaymentAdapter).authorizePayment(
      orderId: 'order-1',
      amountMinor: 1000,
      currency: 'USD',
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakePaymentAdapter).authorizePayment(
      orderId: 'order-2',
      amountMinor: 2000,
      currency: 'EUR',
      idempotencyKey: key,
    ),
    describe: (result) {
      final payment = result as PaymentResult;
      return {
        'paymentId': payment.paymentId,
        'status': payment.status,
        'amountMinor': payment.amountMinor,
        'currency': payment.currency,
      };
    },
  ),
  MutatingContractSubject(
    name: 'FakePaymentAdapter.refundPayment',
    build: (scenario) => FakePaymentAdapter(scenario: scenario),
    invoke: (adapter, key) => (adapter as FakePaymentAdapter).refundPayment(
      paymentId: 'payment-1',
      amountMinor: 500,
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakePaymentAdapter).refundPayment(
      paymentId: 'payment-2',
      amountMinor: 750,
      idempotencyKey: key,
    ),
    describe: (result) {
      final payment = result as PaymentResult;
      return {
        'paymentId': payment.paymentId,
        'status': payment.status,
        'amountMinor': payment.amountMinor,
        'currency': payment.currency,
      };
    },
  ),
  MutatingContractSubject(
    name: 'FakeShippingAdapter.createShipment',
    build: (scenario) => FakeShippingAdapter(scenario: scenario),
    invoke: (adapter, key) => (adapter as FakeShippingAdapter).createShipment(
      orderId: 'order-1',
      destinationAddress: '1 Test Street',
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakeShippingAdapter).createShipment(
      orderId: 'order-2',
      destinationAddress: '2 Test Street',
      idempotencyKey: key,
    ),
    describe: (result) {
      final shipment = result as Shipment;
      return {
        'shipmentId': shipment.shipmentId,
        'orderId': shipment.orderId,
        'carrier': shipment.carrier,
        'trackingNumber': shipment.trackingNumber,
        'status': shipment.status,
      };
    },
  ),
  MutatingContractSubject(
    name: 'FakeErpAdapter.syncOrder',
    build: (scenario) => FakeErpAdapter(scenario: scenario),
    invoke: (adapter, key) => (adapter as FakeErpAdapter).syncOrder(
      order: _order('order-1'),
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakeErpAdapter).syncOrder(
      order: _order('order-2'),
      idempotencyKey: key,
    ),
    describe: (result) {
      final receipt = result as ErpSyncReceipt;
      return {'erpReference': receipt.erpReference, 'accepted': receipt.accepted};
    },
  ),
  MutatingContractSubject(
    name: 'FakeErpAdapter.requestQuotation',
    build: (scenario) => FakeErpAdapter(scenario: scenario),
    invoke: (adapter, key) => (adapter as FakeErpAdapter).requestQuotation(
      rfq: _rfq('rfq-1'),
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakeErpAdapter).requestQuotation(
      rfq: _rfq('rfq-2'),
      idempotencyKey: key,
    ),
    describe: (result) {
      final quotation = result as Quotation;
      return {
        'id': quotation.id,
        'rfqId': quotation.rfqId,
        'totalMinor': quotation.totalMinor,
        'status': quotation.status,
      };
    },
  ),
  MutatingContractSubject(
    name: 'FakeCrmAdapter.recordActivity',
    build: (scenario) => FakeCrmAdapter(scenario: scenario),
    invoke: (adapter, key) => (adapter as FakeCrmAdapter).recordActivity(
      identityId: 'user-1',
      activityType: 'note',
      attributes: const {'source': 'contract-test'},
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakeCrmAdapter).recordActivity(
      identityId: 'user-2',
      activityType: 'call',
      attributes: const {'source': 'other'},
      idempotencyKey: key,
    ),
    describe: (result) {
      final receipt = result as CrmActivityReceipt;
      return {'activityId': receipt.activityId, 'recorded': receipt.recorded};
    },
  ),
  MutatingContractSubject(
    name: 'FakeWhatsAppAdapter.sendTemplateMessage',
    build: (scenario) => FakeWhatsAppAdapter(scenario: scenario),
    invoke: (adapter, key) =>
        (adapter as FakeWhatsAppAdapter).sendTemplateMessage(
      toPhoneNumber: '+15550001111',
      templateName: 'order_confirmation',
      parameters: const {'orderId': 'order-1'},
      idempotencyKey: key,
    ),
    invokeWithDifferentPayload: (adapter, key) =>
        (adapter as FakeWhatsAppAdapter).sendTemplateMessage(
      toPhoneNumber: '+15550002222',
      templateName: 'shipping_update',
      parameters: const {'orderId': 'order-2'},
      idempotencyKey: key,
    ),
    describe: (result) {
      final receipt = result as WhatsAppMessageReceipt;
      return {'messageId': receipt.messageId, 'accepted': receipt.accepted};
    },
  ),
];

final List<ReadContractSubject> readSubjects = [
  ReadContractSubject(
    name: 'FakeShippingAdapter.trackShipment',
    build: (scenario) => FakeShippingAdapter(scenario: scenario),
    invoke: (adapter) async {
      final shipping = adapter as FakeShippingAdapter;
      final shipment = await shipping.createShipment(
        orderId: 'order-1',
        destinationAddress: '1 Test Street',
        idempotencyKey: _keyA,
      );
      return shipping.trackShipment(shipment.shipmentId);
    },
    describe: (result) {
      final shipment = result as Shipment?;
      return shipment == null
          ? null
          : {
              'shipmentId': shipment.shipmentId,
              'orderId': shipment.orderId,
              'carrier': shipment.carrier,
              'trackingNumber': shipment.trackingNumber,
              'status': shipment.status,
            };
    },
  ),
  ReadContractSubject(
    name: 'FakeErpAdapter.fetchInventory',
    build: (scenario) => FakeErpAdapter(scenario: scenario),
    invoke: (adapter) => (adapter as FakeErpAdapter)
        .fetchInventory(const ['variant-1', 'variant-2']),
    describe: (result) {
      final availability = (result as List<InventoryAvailability>)
          .map(
            (item) => {
              'variantId': item.variantId,
              'available': item.available,
              'warehouseId': item.warehouseId,
            },
          )
          .toList();
      return availability;
    },
  ),
];

void main() {
  group('fake integration adapter contract — mutating operations', () {
    for (final subject in mutatingSubjects) {
      group(subject.name, () {
        test('returns a deterministic success result', () async {
          final first = await subject.invoke(
            subject.build(FakeIntegrationScenario.success),
            _keyA,
          );
          final second = await subject.invoke(
            subject.build(FakeIntegrationScenario.success),
            _keyA,
          );
          expect(subject.describe(first), equals(subject.describe(second)));
        });

        test('honors the idempotency key for repeated identical requests',
            () async {
          final adapter = subject.build(FakeIntegrationScenario.success);
          final original = await subject.invoke(adapter, _keyA);
          final repeated = await subject.invoke(adapter, _keyA);
          expect(repeated, same(original));
        });

        test('returns the original result when the key repeats with a new '
            'payload', () async {
          final adapter = subject.build(FakeIntegrationScenario.success);
          final original = await subject.invoke(adapter, _keyA);
          final repeated = await subject.invokeWithDifferentPayload(
            adapter,
            _keyA,
          );
          expect(repeated, same(original));
        });

        test('treats a different idempotency key as a new request', () async {
          final adapter = subject.build(FakeIntegrationScenario.success);
          final first = await subject.invoke(adapter, _keyA);
          final second = await subject.invoke(adapter, _keyB);
          expect(second, isNot(same(first)));
        });

        test('duplicate returns the same result as the original request',
            () async {
          final adapter = subject.build(FakeIntegrationScenario.duplicate);
          final original = await subject.invoke(adapter, _keyA);
          final repeated = await subject.invoke(adapter, _keyA);
          final repeatedWithNewPayload =
              await subject.invokeWithDifferentPayload(adapter, _keyA);
          expect(repeated, same(original));
          expect(repeatedWithNewPayload, same(original));
        });

        test('validationFailure is a non-retryable DomainFailure', () async {
          final failure = await captureFailure(
            subject.invoke(
              subject.build(FakeIntegrationScenario.validationFailure),
              _keyA,
            ),
          );
          expect(failure, isA<DomainFailure>());
          expect(failure.runtimeType, DomainFailure);
          expect(failure.code, DomainFailureCode.validation);
          expect(failure.retryable, isFalse);
        });

        test('timeout is a retryable DomainFailure', () async {
          final failure = await captureFailure(
            subject.invoke(
              subject.build(FakeIntegrationScenario.timeout),
              _keyA,
            ),
          );
          expect(failure.runtimeType, DomainFailure);
          expect(failure.code, DomainFailureCode.timeout);
          expect(failure.retryable, isTrue);
        });

        test('unavailable is a retryable DomainFailure', () async {
          final failure = await captureFailure(
            subject.invoke(
              subject.build(FakeIntegrationScenario.unavailable),
              _keyA,
            ),
          );
          expect(failure.runtimeType, DomainFailure);
          expect(failure.code, DomainFailureCode.unavailable);
          expect(failure.retryable, isTrue);
        });

        test('retryableFailure is a retryable DomainFailure', () async {
          final failure = await captureFailure(
            subject.invoke(
              subject.build(FakeIntegrationScenario.retryableFailure),
              _keyA,
            ),
          );
          expect(failure.runtimeType, DomainFailure);
          expect(failure.retryable, isTrue);
        });
      });
    }
  });

  group('fake integration adapter contract — read operations', () {
    for (final subject in readSubjects) {
      group(subject.name, () {
        test('returns a deterministic success result', () async {
          final first = await subject.invoke(
            subject.build(FakeIntegrationScenario.success),
          );
          final second = await subject.invoke(
            subject.build(FakeIntegrationScenario.success),
          );
          expect(subject.describe(first), equals(subject.describe(second)));
        });

        test('normalizes every failure scenario to DomainFailure', () async {
          for (final scenario in const [
            FakeIntegrationScenario.validationFailure,
            FakeIntegrationScenario.timeout,
            FakeIntegrationScenario.unavailable,
            FakeIntegrationScenario.retryableFailure,
          ]) {
            final failure = await captureFailure(
              subject.invoke(subject.build(scenario)),
            );
            expect(failure.runtimeType, DomainFailure);
            expect(failure.operation, isNotEmpty);
          }
        });

        test('maps retryability per scenario', () async {
          final validation = await captureFailure(
            subject.invoke(
              subject.build(FakeIntegrationScenario.validationFailure),
            ),
          );
          final timeout = await captureFailure(
            subject.invoke(subject.build(FakeIntegrationScenario.timeout)),
          );
          final unavailable = await captureFailure(
            subject.invoke(subject.build(FakeIntegrationScenario.unavailable)),
          );
          final retryable = await captureFailure(
            subject.invoke(
              subject.build(FakeIntegrationScenario.retryableFailure),
            ),
          );
          expect(validation.retryable, isFalse);
          expect(timeout.retryable, isTrue);
          expect(unavailable.retryable, isTrue);
          expect(retryable.retryable, isTrue);
        });
      });
    }
  });

  test('no fake adapter leaks a provider-specific exception', () async {
    for (final subject in mutatingSubjects) {
      for (final scenario in const [
        FakeIntegrationScenario.validationFailure,
        FakeIntegrationScenario.timeout,
        FakeIntegrationScenario.unavailable,
        FakeIntegrationScenario.retryableFailure,
      ]) {
        final failure = await captureFailure(
          subject.invoke(subject.build(scenario), _keyA),
        );
        expect(failure.runtimeType, DomainFailure);
      }
    }
  });
}
