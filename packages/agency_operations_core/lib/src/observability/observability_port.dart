/// Provider-neutral observability contract.
///
/// Application and release code depends only on this port. Reference adapters
/// (for example a Sentry adapter) implement it without leaking provider SDK
/// types across the boundary.
abstract interface class ObservabilityPort {
  Future<void> captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> context = const {},
  });

  Future<void> captureMessage(
    String message, {
    Map<String, Object?> context = const {},
  });

  Future<void> addBreadcrumb(
    String message, {
    Map<String, Object?> data = const {},
  });

  Future<void> setUserContext(String? userId);

  Future<void> setReleaseContext(Map<String, String> context);

  Future<T> startOperation<T>(String name, Future<T> Function() operation);

  Future<void> flush();
}
