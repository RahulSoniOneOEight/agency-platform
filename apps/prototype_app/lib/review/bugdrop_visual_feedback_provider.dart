import 'review_domain_error.dart';
import 'visual_attachment.dart';
import 'visual_feedback_provider.dart';

/// First [VisualFeedbackProvider] adapter; BugDrop is not a core dependency.
///
/// The adapter is pure: it validates and normalizes a BugDrop-style payload into
/// a neutral [VisualAttachment] and never mutates feedback, review, or approval
/// state. BugDrop reports a region as normalized `bounds`
/// (`left/top/right/bottom`), which is converted to `x/y/width/height`.
final class BugDropVisualFeedbackProvider implements VisualFeedbackProvider {
  const BugDropVisualFeedbackProvider();

  static const String providerName = 'bugdrop';

  @override
  VisualAttachment normalize(Map<String, Object?> payload) {
    final viewport = _requireMap(payload['viewport'], 'viewport');
    final context = _requireMap(payload['context'], 'context');
    final bounds = _requireMap(payload['bounds'], 'bounds');
    final left = _requireDouble(bounds['left'], 'bounds left');
    final top = _requireDouble(bounds['top'], 'bounds top');
    final right = _requireDouble(bounds['right'], 'bounds right');
    final bottom = _requireDouble(bounds['bottom'], 'bounds bottom');
    final annotation = _requireAnnotation(left, top, right, bottom);
    return VisualAttachment(
      screenshotRef: _requireString(payload['screenshot_ref'], 'screenshot_ref'),
      viewportWidth: _requireInt(viewport['width'], 'viewport width'),
      viewportHeight: _requireInt(viewport['height'], 'viewport height'),
      clientId: _requireString(context['client_id'], 'context client_id'),
      reviewRound: _requireInt(context['review_round'], 'context review_round'),
      screenId: _requireString(context['screen'], 'context screen'),
      effectiveDirection:
          _requireString(context['effective_direction'], 'context direction'),
      sourceCommitSha:
          _requireString(context['source_commit_sha'], 'context commit sha'),
      annotation: annotation,
      providerName: providerName,
      externalRef: _requireString(payload['provider_item_id'], 'provider item id'),
      sectionId: _optionalString(context['section'], 'context section'),
    );
  }

  static Map<String, Object?> _requireMap(Object? value, String field) {
    if (value is! Map) {
      throw UnsupportedVisualProviderPayload('missing or invalid $field');
    }
    return value.cast<String, Object?>();
  }

  static String _requireString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw UnsupportedVisualProviderPayload('missing or invalid $field');
    }
    return value;
  }

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw UnsupportedVisualProviderPayload('invalid $field');
    }
    return value;
  }

  static int _requireInt(Object? value, String field) {
    if (value is! int) {
      throw UnsupportedVisualProviderPayload('missing or invalid $field');
    }
    return value;
  }

  static double _requireDouble(Object? value, String field) {
    if (value is num) {
      return value.toDouble();
    }
    throw UnsupportedVisualProviderPayload('missing or invalid $field');
  }

  /// Converts normalized `bounds` into a [NormalizedRect], surfacing malformed
  /// bounds as an ingestion-typed [UnsupportedVisualProviderPayload].
  static NormalizedRect _requireAnnotation(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    try {
      return NormalizedRect(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
    } on InvalidVisualAnnotation catch (error) {
      throw UnsupportedVisualProviderPayload('invalid bounds: ${error.message}');
    }
  }
}
