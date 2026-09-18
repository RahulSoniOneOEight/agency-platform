import 'package:flutter/foundation.dart';

/// Stable, provider-neutral release failure classes.
///
/// Provider-specific exceptions stay in adapters as detail evidence and are
/// mapped into one of these codes at the core boundary.
enum ReleaseFailureCode {
  candidateMismatch,
  authorizationMissing,
  authorizationInvalid,
  artifactMissing,
  artifactDigestMismatch,
  migrationValidationFailed,
  migrationApplyFailed,
  stagingSmokeFailed,
  securityGateFailed,
  accessibilityGateFailed,
  performanceGateFailed,
  observabilityGateFailed,
  analyticsGateFailed,
  deploymentFailed,
  productionSmokeFailed,
  telemetryHealthFailed,
  rollbackFailed,
  recoveryRequired,
}

/// A normalized release failure.
///
/// Carries a stable [code], a human-readable [message], and optional
/// provider-neutral [details]. Provider exceptions are mapped into this type
/// without importing provider SDKs.
final class ReleaseFailure implements Exception {
  ReleaseFailure({
    required this.code,
    required this.message,
    Map<String, Object?> details = const {},
  }) : details = Map.unmodifiable(details);

  final ReleaseFailureCode code;
  final String message;
  final Map<String, Object?> details;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseFailure &&
          other.code == code &&
          other.message == message &&
          mapEquals(other.details, details);

  @override
  int get hashCode {
    final keys = details.keys.toList()..sort();
    return Object.hash(
      code,
      message,
      Object.hashAll(keys),
      Object.hashAll(keys.map((key) => details[key])),
    );
  }

  @override
  String toString() => 'ReleaseFailure(${code.name}): $message';
}
