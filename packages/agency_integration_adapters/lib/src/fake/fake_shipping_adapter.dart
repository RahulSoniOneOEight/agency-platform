import 'package:agency_production_core/agency_production_core.dart';

import 'fake_integration_scenario.dart';

/// Deterministic fake shipping provider.
///
/// [createShipment] honors the caller's [IdempotencyKey]; [trackShipment] is a
/// read and only returns shipments this adapter previously created. Provider
/// faults are surfaced only as a provider-neutral [DomainFailure].
final class FakeShippingAdapter implements ShippingPort {
  FakeShippingAdapter({this.scenario = FakeIntegrationScenario.success});

  final FakeIntegrationScenario scenario;
  final FakeIdempotencyStore _store = FakeIdempotencyStore();
  final Map<String, Shipment> _shipments = {};

  @override
  Future<Shipment> createShipment({
    required String orderId,
    required String destinationAddress,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'ShippingPort.createShipment';
    fakeGuard(scenario, operation);
    final shipment = fakeIdempotentResult(
      scenario: scenario,
      store: _store,
      operation: operation,
      key: idempotencyKey,
      requestFingerprint: fakeFingerprint([orderId, destinationAddress]),
      create: () => Shipment(
        shipmentId: 'shp_${orderId}_${idempotencyKey.value}',
        orderId: orderId,
        carrier: 'FakeCarrier',
        trackingNumber: 'trk_${idempotencyKey.value}',
        status: ShipmentStatus.created,
      ),
    );
    _shipments[shipment.shipmentId] = shipment;
    return shipment;
  }

  @override
  Future<Shipment?> trackShipment(String shipmentId) async {
    const operation = 'ShippingPort.trackShipment';
    fakeGuard(scenario, operation);
    return _shipments[shipmentId];
  }
}
