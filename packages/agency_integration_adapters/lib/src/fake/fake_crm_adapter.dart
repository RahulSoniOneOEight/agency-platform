import 'package:agency_production_core/agency_production_core.dart';

import 'fake_integration_scenario.dart';

/// Deterministic fake CRM.
///
/// [recordActivity] honors the caller's [IdempotencyKey]. Provider faults are
/// surfaced only as a provider-neutral [DomainFailure].
final class FakeCrmAdapter implements CrmPort {
  FakeCrmAdapter({this.scenario = FakeIntegrationScenario.success});

  final FakeIntegrationScenario scenario;
  final FakeIdempotencyStore _store = FakeIdempotencyStore();

  @override
  Future<CrmActivityReceipt> recordActivity({
    required String identityId,
    required String activityType,
    required Map<String, String> attributes,
    required IdempotencyKey idempotencyKey,
  }) async {
    const operation = 'CrmPort.recordActivity';
    fakeGuard(scenario, operation);
    return _store.resolve(operation, idempotencyKey, () {
      return CrmActivityReceipt(
        activityId: 'crm_${identityId}_${activityType}_${idempotencyKey.value}',
        recorded: true,
      );
    });
  }
}
