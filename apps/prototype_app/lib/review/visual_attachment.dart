/// Provider-neutral C.6 visual evidence attached to a feedback record.
///
/// The screenshot/annotation is evidence only: the [FeedbackRecord] remains the
/// lifecycle authority. Coordinates are normalized to `0..1` so annotations stay
/// meaningful across image transport/storage implementations, and any malformed
/// or out-of-bounds value fails with a typed [InvalidVisualAnnotation].
library;

import 'review_domain_error.dart';

const double _epsilon = 1e-9;

/// A normalized annotation region within a screenshot.
final class NormalizedRect {
  NormalizedRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    for (final value in [x, y, width, height]) {
      if (value.isNaN || value.isInfinite) {
        throw const InvalidVisualAnnotation(
          'annotation coordinates must be finite',
        );
      }
    }
    if (x < 0 || x > 1 || y < 0 || y > 1) {
      throw const InvalidVisualAnnotation(
        'annotation origin must be within 0..1',
      );
    }
    if (width <= 0 || height <= 0) {
      throw const InvalidVisualAnnotation(
        'annotation width and height must be positive',
      );
    }
    if (x + width > 1 + _epsilon || y + height > 1 + _epsilon) {
      throw const InvalidVisualAnnotation(
        'annotation region must stay within 0..1',
      );
    }
  }

  final double x;
  final double y;
  final double width;
  final double height;

  factory NormalizedRect.fromJson(Map<String, dynamic> json) {
    return NormalizedRect(
      x: _requireDouble(json['x'], 'annotation x'),
      y: _requireDouble(json['y'], 'annotation y'),
      width: _requireDouble(json['width'], 'annotation width'),
      height: _requireDouble(json['height'], 'annotation height'),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NormalizedRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// Normalized, provider-agnostic visual evidence for a feedback item.
final class VisualAttachment {
  VisualAttachment({
    required this.screenshotRef,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.clientId,
    required this.reviewRound,
    required this.screenId,
    required this.effectiveDirection,
    required this.sourceCommitSha,
    required this.annotation,
    required this.providerName,
    required this.externalRef,
    this.sectionId,
  }) {
    if (screenshotRef.trim().isEmpty) {
      throw const InvalidVisualAnnotation('screenshot reference is required');
    }
    if (viewportWidth <= 0 || viewportHeight <= 0) {
      throw const InvalidVisualAnnotation(
        'viewport dimensions must be positive',
      );
    }
    if (clientId.trim().isEmpty) {
      throw const InvalidVisualAnnotation('visual attachment client id is required');
    }
    if (reviewRound < 1) {
      throw const InvalidVisualAnnotation(
        'visual attachment review round must be positive',
      );
    }
    if (screenId.trim().isEmpty) {
      throw const InvalidVisualAnnotation('visual attachment screen is required');
    }
    if (effectiveDirection.trim().isEmpty) {
      throw const InvalidVisualAnnotation(
        'visual attachment effective direction is required',
      );
    }
    if (sourceCommitSha.trim().isEmpty) {
      throw const InvalidVisualAnnotation(
        'visual attachment source commit SHA is required',
      );
    }
    if (providerName.trim().isEmpty) {
      throw const InvalidVisualAnnotation(
        'visual attachment provider name is required',
      );
    }
    if (externalRef.trim().isEmpty) {
      throw const InvalidVisualAnnotation(
        'visual attachment external reference is required',
      );
    }
    if (sectionId != null && sectionId!.trim().isEmpty) {
      throw const InvalidVisualAnnotation(
        'visual attachment section must not be blank',
      );
    }
  }

  /// Immutable screenshot reference; stable once attached.
  final String screenshotRef;
  final int viewportWidth;
  final int viewportHeight;
  final String clientId;
  final int reviewRound;
  final String screenId;
  final String effectiveDirection;
  final String sourceCommitSha;
  final NormalizedRect annotation;
  final String providerName;
  final String externalRef;

  /// Optional governed section; free-form annotations may omit it.
  final String? sectionId;

  factory VisualAttachment.fromJson(Map<String, dynamic> json) {
    final viewport = _requireMap(json['viewport'], 'viewport');
    final context = _requireMap(json['context'], 'context');
    final provider = _requireMap(json['provider'], 'provider');
    final annotation = _requireMap(json['annotation'], 'annotation');
    return VisualAttachment(
      screenshotRef: _requireString(json['screenshot_ref'], 'screenshot_ref'),
      viewportWidth: _requireInt(viewport['width'], 'viewport width'),
      viewportHeight: _requireInt(viewport['height'], 'viewport height'),
      clientId: _requireString(context['client_id'], 'context client_id'),
      reviewRound: _requireInt(context['review_round'], 'context review_round'),
      screenId: _requireString(context['screen'], 'context screen'),
      effectiveDirection:
          _requireString(context['effective_direction'], 'context direction'),
      sourceCommitSha:
          _requireString(context['source_commit_sha'], 'context commit sha'),
      annotation: NormalizedRect.fromJson(annotation),
      providerName: _requireString(provider['name'], 'provider name'),
      externalRef: _requireString(provider['external_ref'], 'provider ref'),
      sectionId: _optionalString(json['section'], 'section'),
    );
  }

  /// Deterministic canonical serialization.
  Map<String, dynamic> toJson() => {
        'screenshot_ref': screenshotRef,
        'viewport': {
          'width': viewportWidth,
          'height': viewportHeight,
        },
        'context': {
          'client_id': clientId,
          'review_round': reviewRound,
          'screen': screenId,
          'effective_direction': effectiveDirection,
          'source_commit_sha': sourceCommitSha,
        },
        if (sectionId != null) 'section': sectionId,
        'annotation': annotation.toJson(),
        'provider': {
          'name': providerName,
          'external_ref': externalRef,
        },
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VisualAttachment &&
        other.screenshotRef == screenshotRef &&
        other.viewportWidth == viewportWidth &&
        other.viewportHeight == viewportHeight &&
        other.clientId == clientId &&
        other.reviewRound == reviewRound &&
        other.screenId == screenId &&
        other.effectiveDirection == effectiveDirection &&
        other.sourceCommitSha == sourceCommitSha &&
        other.annotation == annotation &&
        other.providerName == providerName &&
        other.externalRef == externalRef &&
        other.sectionId == sectionId;
  }

  @override
  int get hashCode => Object.hash(
        screenshotRef,
        viewportWidth,
        viewportHeight,
        clientId,
        reviewRound,
        screenId,
        effectiveDirection,
        sourceCommitSha,
        annotation,
        providerName,
        externalRef,
        sectionId,
      );
}

Map<String, dynamic> _requireMap(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw InvalidVisualAnnotation('missing or invalid $field');
  }
  return value.cast<String, dynamic>();
}

String _requireString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw InvalidVisualAnnotation('missing or invalid $field');
  }
  return value;
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw InvalidVisualAnnotation('invalid $field');
  }
  return value;
}

int _requireInt(Object? value, String field) {
  if (value is! int) {
    throw InvalidVisualAnnotation('missing or invalid $field');
  }
  return value;
}

double _requireDouble(Object? value, String field) {
  if (value is num) {
    return value.toDouble();
  }
  throw InvalidVisualAnnotation('missing or invalid $field');
}
