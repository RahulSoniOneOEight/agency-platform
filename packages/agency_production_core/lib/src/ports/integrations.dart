import '../domain/models.dart';
import 'repositories.dart';

/// Provider-neutral port for the payment provider.
///
/// Implementations translate provider errors into `DomainFailure`; no
/// provider-specific exception may cross this boundary. Mutating methods
/// require an [IdempotencyKey].
abstract interface class PaymentPort {
  Future<PaymentResult> authorizePayment({
    required String orderId,
    required int amountMinor,
    required String currency,
    required IdempotencyKey idempotencyKey,
  });

  Future<PaymentResult> refundPayment({
    required String paymentId,
    required int amountMinor,
    required IdempotencyKey idempotencyKey,
  });
}

enum PaymentStatus { pending, authorized, captured, declined, refunded }

final class PaymentResult {
  const PaymentResult({
    required this.paymentId,
    required this.status,
    required this.amountMinor,
    required this.currency,
  });

  final String paymentId;
  final PaymentStatus status;
  final int amountMinor;
  final String currency;
}

/// Provider-neutral port for the shipping provider.
abstract interface class ShippingPort {
  Future<Shipment> createShipment({
    required String orderId,
    required String destinationAddress,
    required IdempotencyKey idempotencyKey,
  });

  Future<Shipment?> trackShipment(String shipmentId);
}

enum ShipmentStatus { created, inTransit, delivered, failed }

final class Shipment {
  const Shipment({
    required this.shipmentId,
    required this.orderId,
    required this.carrier,
    required this.trackingNumber,
    required this.status,
  });

  final String shipmentId;
  final String orderId;
  final String carrier;
  final String trackingNumber;
  final ShipmentStatus status;
}

/// Provider-neutral port for the ERP system.
abstract interface class ErpPort {
  Future<List<InventoryAvailability>> fetchInventory(
    Iterable<String> variantIds,
  );

  Future<Quotation> requestQuotation({
    required Rfq rfq,
    required IdempotencyKey idempotencyKey,
  });

  Future<ErpSyncReceipt> syncOrder({
    required Order order,
    required IdempotencyKey idempotencyKey,
  });
}

final class ErpSyncReceipt {
  const ErpSyncReceipt({required this.erpReference, required this.accepted});

  final String erpReference;
  final bool accepted;
}

/// Provider-neutral port for the CRM system.
abstract interface class CrmPort {
  Future<CrmActivityReceipt> recordActivity({
    required String identityId,
    required String activityType,
    required Map<String, String> attributes,
    required IdempotencyKey idempotencyKey,
  });
}

final class CrmActivityReceipt {
  const CrmActivityReceipt({required this.activityId, required this.recorded});

  final String activityId;
  final bool recorded;
}

/// Provider-neutral port for WhatsApp messaging.
abstract interface class WhatsAppPort {
  Future<WhatsAppMessageReceipt> sendTemplateMessage({
    required String toPhoneNumber,
    required String templateName,
    required Map<String, String> parameters,
    required IdempotencyKey idempotencyKey,
  });
}

final class WhatsAppMessageReceipt {
  const WhatsAppMessageReceipt({
    required this.messageId,
    required this.accepted,
  });

  final String messageId;
  final bool accepted;
}
