/// Governed, user-visible runtime loading failure.
///
/// Error codes are stable strings so the app can render a concise remediation
/// message without leaking stack traces to client reviewers.
class RuntimeException implements Exception {
  const RuntimeException({
    required this.code,
    required this.message,
    this.clientId,
    this.directionId,
  });

  static const String clientNotFound = 'client_not_found';
  static const String invalidBundle = 'invalid_bundle';
  static const String directionNotFound = 'direction_not_found';

  final String code;
  final String message;
  final String? clientId;
  final String? directionId;

  @override
  String toString() => 'RuntimeException($code): $message';
}
