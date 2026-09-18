import 'package:agency_production_core/agency_production_core.dart';

import 'fake_integration_scenario.dart';

/// Deterministic fake WhatsApp provider.
///
/// [sendTemplateMessage] honors the caller's [IdempotencyKey]. Provider faults
/// are surfaced only as a provider-neutral [DomainFailure].
final class FakeWhatsAppAdapter implements WhatsAppPort {
  FakeWhatsAppAdapter({this.scenario = FakeIntegrationScenario.success});

  final FakeIntegrationScenario scenario;
  final FakeIdempotencyStore _store = FakeIdempotencyStore();

  @override
  Future<WhatsAppMessageReceipt> sendTemplateMessage({
    required String toPhoneNumber,
    required String templateName,
    required Map<String, String> parameters,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'WhatsAppPort.sendTemplateMessage';
    fakeGuard(scenario, operation);
    return fakeIdempotentResult(
      scenario: scenario,
      store: _store,
      operation: operation,
      key: idempotencyKey,
      requestFingerprint: fakeFingerprint([
        toPhoneNumber,
        templateName,
        fakeMapFingerprint(parameters),
      ]),
      create: () => WhatsAppMessageReceipt(
        messageId: 'wa_${templateName}_${idempotencyKey.value}',
        accepted: true,
      ),
    );
  }
}
