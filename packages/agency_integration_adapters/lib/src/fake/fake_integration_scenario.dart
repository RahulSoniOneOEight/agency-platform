import 'package:agency_production_core/agency_production_core.dart';

/// The deterministic behavior a fake integration adapter exhibits.
///
/// Selection is constructor-injected; there is no randomness, no sleep-based
/// timing, and no network dependency. [success] and [duplicate] are
/// non-failing scenarios; the remaining four normalize to a provider-neutral
/// [DomainFailure] instead of leaking a provider-specific exception.
enum FakeIntegrationScenario {
  success,
  validationFailure,
  timeout,
  unavailable,
  retryableFailure,
  duplicate,
}

extension FakeIntegrationScenarioX on FakeIntegrationScenario {
  /// Whether this scenario models a provider fault.
  bool get isFailure =>
      this != FakeIntegrationScenario.success &&
      this != FakeIntegrationScenario.duplicate;
}

/// Builds the provider-neutral failure a fake adapter must raise for [scenario].
///
/// Mapping (per the H.1 contract):
/// - [FakeIntegrationScenario.validationFailure] -> `validation`, non-retryable
/// - [FakeIntegrationScenario.timeout] -> `timeout`, retryable
/// - [FakeIntegrationScenario.unavailable] -> `unavailable`, retryable
/// - [FakeIntegrationScenario.retryableFailure] -> `unavailable`, retryable
///
/// [success] and [duplicate] never fail, so calling this with them is a
/// programming error.
DomainFailure fakeIntegrationFailure(
  FakeIntegrationScenario scenario,
  String operation,
) {
  switch (scenario) {
    case FakeIntegrationScenario.validationFailure:
      return DomainFailure(
        code: DomainFailureCode.validation,
        operation: operation,
        retryable: false,
        message: 'Fake integration rejected the request as invalid.',
      );
    case FakeIntegrationScenario.timeout:
      return DomainFailure(
        code: DomainFailureCode.timeout,
        operation: operation,
        retryable: true,
        message: 'Fake integration timed out.',
      );
    case FakeIntegrationScenario.unavailable:
      return DomainFailure(
        code: DomainFailureCode.unavailable,
        operation: operation,
        retryable: true,
        message: 'Fake integration is unavailable.',
      );
    case FakeIntegrationScenario.retryableFailure:
      return DomainFailure(
        code: DomainFailureCode.unavailable,
        operation: operation,
        retryable: true,
        message: 'Fake integration failed transiently; retry may succeed.',
      );
    case FakeIntegrationScenario.success:
    case FakeIntegrationScenario.duplicate:
      throw StateError('$scenario is not a failure scenario');
  }
}

/// Raises the normalized failure for failure scenarios; otherwise returns.
void fakeGuard(FakeIntegrationScenario scenario, String operation) {
  if (scenario.isFailure) {
    throw fakeIntegrationFailure(scenario, operation);
  }
}

/// In-memory idempotency ledger shared by the fake mutating adapters.
///
/// Re-submitting the same [IdempotencyKey] for the same [operation] returns the
/// exact result instance produced by the original request, so a duplicate
/// cannot create a second externally visible effect. The ledger is per adapter
/// instance and deterministic.
final class FakeIdempotencyStore {
  final Map<String, Object> _results = {};

  T resolve<T extends Object>(
    String operation,
    IdempotencyKey key,
    T Function() create,
  ) {
    final cacheKey = '$operation#${key.value}';
    final existing = _results[cacheKey];
    if (existing != null) {
      return existing as T;
    }
    final created = create();
    _results[cacheKey] = created;
    return created;
  }

  /// Clears every remembered result.
  void reset() => _results.clear();
}
