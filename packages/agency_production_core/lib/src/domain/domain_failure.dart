enum DomainFailureCode {
  unauthorized,
  forbidden,
  validation,
  conflict,
  unavailable,
  timeout,
  staleData,
  unknown,
}

final class DomainFailure implements Exception {
  const DomainFailure({
    required this.code,
    required this.operation,
    required this.retryable,
    required this.message,
    this.correlationId,
  });

  final DomainFailureCode code;
  final String operation;
  final bool retryable;
  final String message;
  final String? correlationId;
}
