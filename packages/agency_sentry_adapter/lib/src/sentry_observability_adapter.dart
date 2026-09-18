import 'package:agency_operations_core/agency_operations_core.dart';

/// Narrow, injectable transport seam for the Sentry reference adapter.
///
/// The adapter owns all provider-neutral payload construction and redaction; a
/// concrete transport owns every Sentry HTTP/SDK detail. Tests inject a
/// recording transport, so no network access or credential is required.
abstract interface class SentryTransport {
  /// Sends one already-redacted event payload to the provider.
  Future<void> capture(Map<String, Object?> payload);

  /// Flushes any buffered provider state.
  Future<void> flush();
}

/// Replacement value written in place of every redacted field.
const String redactedValue = '[REDACTED]';

/// Key-name fragments (case-insensitive substrings) that identify sensitive
/// payload fields which must never leave the process.
const List<String> sensitiveKeyFragments = <String>[
  'password',
  'authorization',
  'cookie',
  'service_role_key',
  'secret',
  'token',
];

/// Returns a deep copy of [source] with every sensitive value replaced by
/// [redactedValue].
///
/// Matching is case-insensitive and substring-based on key names, and it
/// recurses through nested maps and lists so a sensitive value cannot escape
/// inside a nested structure. The original value is never copied into the
/// result.
Map<String, Object?> redactSensitive(Map<String, Object?> source) =>
    _redactMap(source);

Map<String, Object?> _redactMap(Map<String, Object?> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    result[entry.key] =
        _isSensitiveKey(entry.key) ? redactedValue : _redactValue(entry.value);
  }
  return result;
}

Object? _redactValue(Object? value) {
  if (value is Map) {
    final nested = <String, Object?>{};
    value.forEach((key, nestedValue) {
      nested[key.toString()] = nestedValue;
    });
    return _redactMap(nested);
  }
  if (value is Iterable) {
    return value.map(_redactValue).toList(growable: false);
  }
  return value;
}

bool _isSensitiveKey(String key) {
  final lower = key.toLowerCase();
  return sensitiveKeyFragments.any(lower.contains);
}

/// Sentry-backed implementation of the provider-neutral [ObservabilityPort].
///
/// Release, environment, client, and candidate identity are constructor-bound
/// and attached to every capture. Additional release context can be layered in
/// through [setReleaseContext], a user identity through [setUserContext], and a
/// correlation/request id supplied in a capture context is propagated on the
/// resulting payload. Sensitive values are redacted recursively before the
/// transport is ever called: the fully assembled payload is passed through
/// [redactSensitive] immediately before `capture`, so no code path can emit an
/// unredacted field.
///
/// Release context supplied through [setReleaseContext] is merged *before* the
/// constructor-bound identity fields, so it can never override `clientId`,
/// `environment`, `sourceSha`, `buildVersion`, or `releaseCandidateId` — and a
/// sensitive release-context key is redacted like any other sensitive field.
///
/// Free-text `message` and `stackTrace` values are caller-supplied and are NOT
/// key-redacted: only map/list values under sensitive key names are scrubbed.
/// Callers must therefore never place secrets in message or stack-trace text
/// (M1). This is a documented contract, not an enforced one.
///
/// The last non-empty correlation/request id observed in a capture context is
/// retained on the adapter and re-attached to subsequent captures by design, so
/// a single request's correlation id keeps flowing through its later events
/// (M6). Supplying a new non-empty id replaces the retained one.
final class SentryObservabilityAdapter implements ObservabilityPort {
  SentryObservabilityAdapter({
    required SentryTransport transport,
    required this.clientId,
    required this.environment,
    required this.sourceSha,
    required this.buildVersion,
    required this.releaseCandidateId,
  }) : _transport = transport;

  final SentryTransport _transport;
  final String clientId;
  final String environment;
  final String sourceSha;
  final String buildVersion;
  final String releaseCandidateId;

  final Map<String, String> _releaseContext = <String, String>{};
  String? _userId;
  String? _correlationId;

  @override
  Future<void> captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> context = const {},
  }) async {
    _rememberCorrelation(context);
    await _capture(<String, Object?>{
      ..._envelope('exception'),
      'message': error.toString(),
      'stackTrace': stackTrace.toString(),
      'context': context,
    });
  }

  @override
  Future<void> captureMessage(
    String message, {
    Map<String, Object?> context = const {},
  }) async {
    _rememberCorrelation(context);
    await _capture(<String, Object?>{
      ..._envelope('message'),
      'message': message,
      'context': context,
    });
  }

  @override
  Future<void> addBreadcrumb(
    String message, {
    Map<String, Object?> data = const {},
  }) async {
    _rememberCorrelation(data);
    await _capture(<String, Object?>{
      ..._envelope('breadcrumb'),
      'message': message,
      'data': data,
    });
  }

  @override
  Future<void> setUserContext(String? userId) async {
    _userId = userId;
  }

  @override
  Future<void> setReleaseContext(Map<String, String> context) async {
    _releaseContext.addAll(context);
  }

  @override
  Future<T> startOperation<T>(
    String name,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      await captureException(
        error,
        stackTrace,
        context: <String, Object?>{'operation': name},
      );
      rethrow;
    }
  }

  @override
  Future<void> flush() => _transport.flush();

  /// Sends [payload] after recursively redacting every sensitive field. This is
  /// the single choke point through which all captures pass, so redaction cannot
  /// be bypassed by any caller-supplied or release-context value.
  Future<void> _capture(Map<String, Object?> payload) =>
      _transport.capture(redactSensitive(payload));

  Map<String, Object?> _envelope(String type) => <String, Object?>{
        // Release context is merged first so the constructor-bound identity
        // fields below always win and can never be overridden.
        ..._releaseContext,
        'type': type,
        'clientId': clientId,
        'environment': environment,
        'sourceSha': sourceSha,
        'buildVersion': buildVersion,
        'releaseCandidateId': releaseCandidateId,
        if (_userId != null) 'userId': _userId,
        if (_correlationId != null) 'correlationId': _correlationId,
      };

  void _rememberCorrelation(Map<String, Object?> context) {
    final value = context['correlationId'] ??
        context['correlation_id'] ??
        context['requestId'] ??
        context['request_id'];
    if (value is String && value.isNotEmpty) {
      _correlationId = value;
    }
  }
}
