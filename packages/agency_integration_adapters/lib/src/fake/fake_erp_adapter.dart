import 'package:agency_production_core/agency_production_core.dart';

import 'fake_integration_scenario.dart';

/// Deterministic fake ERP system.
///
/// [requestQuotation] and [syncOrder] honor the caller's [IdempotencyKey];
/// [fetchInventory] is a read and returns a fixed deterministic availability.
/// Provider faults are surfaced only as a provider-neutral [DomainFailure].
final class FakeErpAdapter implements ErpPort {
  FakeErpAdapter({this.scenario = FakeIntegrationScenario.success});

  final FakeIntegrationScenario scenario;
  final FakeIdempotencyStore _store = FakeIdempotencyStore();

  @override
  Future<List<InventoryAvailability>> fetchInventory(
    Iterable<String> variantIds,
  ) async {
    const operation = 'ErpPort.fetchInventory';
    fakeGuard(scenario, operation);
    return variantIds
        .map(
          (variantId) => InventoryAvailability(
            variantId: variantId,
            available: 42,
            warehouseId: 'fake-warehouse',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Quotation> requestQuotation({
    required Rfq rfq,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'ErpPort.requestQuotation';
    fakeGuard(scenario, operation);
    return fakeIdempotentResult(
      scenario: scenario,
      store: _store,
      operation: operation,
      key: idempotencyKey,
      requestFingerprint: _rfqFingerprint(rfq),
      create: () {
        final totalMinor = rfq.items.fold<int>(
          0,
          (total, item) => total + item.lineTotalMinor,
        );
        return Quotation(
          id: 'quo_${rfq.id}_${idempotencyKey.value}',
          rfqId: rfq.id,
          totalMinor: totalMinor,
          status: QuotationStatus.sent,
        );
      },
    );
  }

  @override
  Future<ErpSyncReceipt> syncOrder({
    required Order order,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'ErpPort.syncOrder';
    fakeGuard(scenario, operation);
    return fakeIdempotentResult(
      scenario: scenario,
      store: _store,
      operation: operation,
      key: idempotencyKey,
      requestFingerprint: _orderFingerprint(order),
      create: () => ErpSyncReceipt(
        erpReference: 'erp_${order.id}_${idempotencyKey.value}',
        accepted: true,
      ),
    );
  }
}

String _orderFingerprint(Order order) => fakeFingerprint([
      order.id,
      ...order.items.expand(
        (item) => [
          item.productId,
          item.variantId,
          item.quantity,
          item.unitPriceMinor,
        ],
      ),
    ]);

String _rfqFingerprint(Rfq rfq) => fakeFingerprint([
      rfq.id,
      ...rfq.items.expand(
        (item) => [
          item.productId,
          item.variantId,
          item.quantity,
          item.unitPriceMinor,
        ],
      ),
    ]);
