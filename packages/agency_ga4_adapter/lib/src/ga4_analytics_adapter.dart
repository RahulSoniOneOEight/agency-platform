import 'package:agency_operations_core/agency_operations_core.dart';

/// Narrow, injectable transport seam for the GA4 reference adapter.
///
/// A concrete transport owns every Measurement Protocol HTTP detail. Tests
/// inject a recording transport, so no network access or credential is
/// required.
abstract interface class Ga4Transport {
  /// Sends one governed event with its already-validated parameters.
  Future<void> sendEvent(String eventName, Map<String, Object?> parameters);

  /// Sends user-property updates.
  Future<void> sendUserProperties(Map<String, Object?> properties);

  /// Flushes any buffered provider state.
  Future<void> flush();
}

/// Constructor-only GA4 Measurement Protocol credential.
///
/// The [apiSecret] is a server/CI secret. It is never stored on the adapter,
/// never serialized, and never rendered by [toString].
final class Ga4Credentials {
  const Ga4Credentials({required this.apiSecret, this.clientId});

  final String apiSecret;
  final String? clientId;

  @override
  String toString() => 'Ga4Credentials(clientId: $clientId, apiSecret: '
      '[REDACTED])';
}

/// Parameter-name fragments (case-insensitive substrings) that must never be
/// sent as analytics parameters.
const List<String> sensitiveGa4ParameterFragments = <String>[
  'password',
  'authorization',
  'cookie',
  'service_role_key',
  'secret',
  'token',
];

/// GA4-backed implementation of the provider-neutral [AnalyticsPort].
///
/// Every emitted event carries the configured [environment] so staging and
/// production data stay distinguishable. Analytics storage consent is honored
/// strictly: while disabled, no event or user-property emission reaches the
/// transport. Secret-like parameter names are rejected before any emission.
final class Ga4AnalyticsAdapter implements AnalyticsPort {
  Ga4AnalyticsAdapter({
    required Ga4Transport transport,
    required this.environment,
    required String apiSecret,
    this.measurementId,
  }) : _transport = transport {
    // The Measurement Protocol secret is a constructor-only server input; it
    // is deliberately never retained on the adapter nor echoed in an error.
    if (apiSecret.trim().isEmpty) {
      throw ArgumentError('GA4 api secret must not be empty');
    }
  }

  final Ga4Transport _transport;
  final String environment;
  final String? measurementId;

  final Map<String, String> _releaseContext = <String, String>{};
  bool _analyticsStorageEnabled = true;

  /// Provider-neutral configuration snapshot. Never contains the secret.
  Map<String, Object?> toJson() => <String, Object?>{
        'environment': environment,
        if (measurementId != null) 'measurementId': measurementId,
      };

  @override
  Future<void> trackEvent(AnalyticsEvent event) async {
    _rejectSensitiveParameters(event.parameters);
    if (!_analyticsStorageEnabled) {
      return;
    }
    await _transport.sendEvent(event.name, <String, Object?>{
      ..._releaseContext,
      ...event.parameters,
      'environment': environment,
    });
  }

  @override
  Future<void> setUserProperties(Map<String, Object?> properties) async {
    _rejectSensitiveParameters(properties);
    if (!_analyticsStorageEnabled) {
      return;
    }
    await _transport.sendUserProperties(<String, Object?>{
      ...properties,
      'environment': environment,
    });
  }

  @override
  Future<void> setConsent({required bool analyticsStorage}) async {
    _analyticsStorageEnabled = analyticsStorage;
  }

  @override
  Future<void> setReleaseContext(Map<String, String> context) async {
    _releaseContext.addAll(context);
  }

  @override
  Future<void> flush() => _transport.flush();

  void _rejectSensitiveParameters(Map<String, Object?> parameters) {
    for (final entry in parameters.entries) {
      if (_isSensitiveKey(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'parameters',
          'sensitive analytics parameter names are not permitted',
        );
      }
      final value = entry.value;
      if (value is Map) {
        _rejectSensitiveParameters(_stringKeyed(value));
      } else if (value is Iterable) {
        for (final item in value) {
          if (item is Map) {
            _rejectSensitiveParameters(_stringKeyed(item));
          }
        }
      }
    }
  }

  static Map<String, Object?> _stringKeyed(Map<dynamic, dynamic> source) {
    final result = <String, Object?>{};
    source.forEach((key, value) {
      result[key.toString()] = value;
    });
    return result;
  }

  static bool _isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    return sensitiveGa4ParameterFragments.any(lower.contains);
  }
}
