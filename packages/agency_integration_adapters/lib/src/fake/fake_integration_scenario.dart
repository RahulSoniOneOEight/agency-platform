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

/// Joins request fields into a deterministic payload fingerprint.
///
/// Used by [FakeIntegrationScenario.duplicate] to detect a reused idempotency
/// key carrying a different request. The separator is a control character that
/// cannot appear in the field values, so distinct field lists cannot collide.
String fakeFingerprint(Iterable<Object?> parts) =>
    parts.map((part) => part.toString()).join('\u0001');

/// Deterministically fingerprints a string map, independent of insertion order.
String fakeMapFingerprint(Map<String, String> values) {
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join('\u0001');
}

/// Resolves a mutating call against [store] under [scenario].
///
/// [FakeIntegrationScenario.duplicate] enforces provider-side payload
/// integrity: a reused key with an equal request replays the cached result,
/// while a reused key with a different request conflicts. Every other
/// scenario keeps the permissive replay behavior (the key alone wins).
T fakeIdempotentResult<T extends Object>({
  required FakeIntegrationScenario scenario,
  required FakeIdempotencyStore store,
  required String operation,
  required IdempotencyKey key,
  required String requestFingerprint,
  required T Function() create,
}) {
  if (scenario == FakeIntegrationScenario.duplicate) {
    return store.resolveWithIntegrity(
      operation,
      key,
      requestFingerprint,
      create,
    );
  }
  return store.resolve(operation, key, create);
}

/// In-memory idempotency ledger shared by the fake mutating adapters.
///
/// Re-submitting the same [IdempotencyKey] for the same [operation] returns the
/// exact result instance produced by the original request, so a duplicate
/// cannot create a second externally visible effect. [resolveWithIntegrity]
/// additionally enforces payload integrity for the `duplicate` scenario. The
/// ledger is per adapter instance and deterministic.
final class FakeIdempotencyStore {
  final Map<String, Object> _results = {};
  final Map<String, String> _fingerprints = {};

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

  /// Resolves with provider-side payload-integrity enforcement.
  ///
  /// The first request for a key is created and remembered. A repeat with an
  /// equal [requestFingerprint] replays the cached result; a repeat with a
  /// different fingerprint fails with a non-retryable
  /// [DomainFailureCode.conflict], modelling a provider rejecting a reused
  /// idempotency key whose request does not match.
  T resolveWithIntegrity<T extends Object>(
    String operation,
    IdempotencyKey key,
    String requestFingerprint,
    T Function() create,
  ) {
    final cacheKey = '$operation#${key.value}';
    final existing = _results[cacheKey];
    if (existing != null) {
      if (_fingerprints[cacheKey] != requestFingerprint) {
        throw DomainFailure(
          code: DomainFailureCode.conflict,
          operation: operation,
          retryable: false,
          message:
              'Idempotency key was reused with a different request payload.',
        );
      }
      return existing as T;
    }
    final created = create();
    _results[cacheKey] = created;
    _fingerprints[cacheKey] = requestFingerprint;
    return created;
  }

  /// Clears every remembered result and fingerprint.
  void reset() {
    _results.clear();
    _fingerprints.clear();
  }
}
