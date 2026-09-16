import 'visual_attachment.dart';

/// Provider-agnostic ingestion boundary for visual feedback evidence.
///
/// A provider normalizes its own payload into a neutral [VisualAttachment]. It
/// is an adapter only: it must never change feedback status, classify
/// blocking/non-blocking, resolve/reopen feedback, create batches, mutate review
/// decisions, or touch approval history. Malformed provider payloads fail with a
/// typed `UnsupportedVisualProviderPayload`.
abstract interface class VisualFeedbackProvider {
  VisualAttachment normalize(Map<String, Object?> payload);
}
