import 'analytics_event.dart';

/// Provider-neutral analytics contract.
///
/// Reference adapter: GA4. Consent is explicit and must be able to suppress
/// emission of all events.
abstract interface class AnalyticsPort {
  Future<void> trackEvent(AnalyticsEvent event);

  Future<void> setUserProperties(Map<String, Object?> properties);

  Future<void> setConsent({required bool analyticsStorage});

  Future<void> setReleaseContext(Map<String, String> context);

  Future<void> flush();
}
