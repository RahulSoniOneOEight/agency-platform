import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_domain_error.dart';
import 'package:prototype_app/review/visual_attachment.dart';

VisualAttachment attachment({
  String screenshotRef = 'review-home-round-2',
  int viewportWidth = 1440,
  int viewportHeight = 1200,
  String clientId = 'prototype-demo',
  int reviewRound = 2,
  String screenId = 'commerce.home',
  String effectiveDirection = 'b',
  String sourceCommitSha = 'abc123',
  NormalizedRect? annotation,
  String providerName = 'bugdrop',
  String externalRef = 'provider-item-123',
  String? sectionId,
}) {
  return VisualAttachment(
    screenshotRef: screenshotRef,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    clientId: clientId,
    reviewRound: reviewRound,
    screenId: screenId,
    effectiveDirection: effectiveDirection,
    sourceCommitSha: sourceCommitSha,
    annotation:
        annotation ?? NormalizedRect(x: 0.42, y: 0.31, width: 0.18, height: 0.12),
    providerName: providerName,
    externalRef: externalRef,
    sectionId: sectionId,
  );
}

void main() {
  group('NormalizedRect', () {
    test('accepts in-bounds regions', () {
      final rect = NormalizedRect(x: 0, y: 0, width: 1, height: 1);
      expect(rect.toJson(), {'x': 0.0, 'y': 0.0, 'width': 1.0, 'height': 1.0});
    });

    test('rejects out-of-bounds origins and regions', () {
      expect(
        () => NormalizedRect(x: -0.1, y: 0, width: 0.2, height: 0.2),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => NormalizedRect(x: 0.9, y: 0, width: 0.2, height: 0.2),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => NormalizedRect(x: 0, y: 0.9, width: 0.2, height: 0.2),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('rejects non-positive dimensions', () {
      expect(
        () => NormalizedRect(x: 0, y: 0, width: 0, height: 0.2),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => NormalizedRect(x: 0, y: 0, width: 0.2, height: -0.1),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('rejects non-finite coordinates', () {
      expect(
        () => NormalizedRect(x: double.nan, y: 0, width: 0.2, height: 0.2),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('value equality', () {
      expect(
        NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
        NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
      );
      expect(
        NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
        isNot(NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)),
      );
    });
  });

  group('VisualAttachment serialization', () {
    test('round-trips deterministically', () {
      final original = attachment(sectionId: 'home.product-grid');

      final json = original.toJson();
      expect(json['screenshot_ref'], 'review-home-round-2');
      expect(json['viewport'], {'width': 1440, 'height': 1200});
      expect(json['context'], {
        'client_id': 'prototype-demo',
        'review_round': 2,
        'screen': 'commerce.home',
        'effective_direction': 'b',
        'source_commit_sha': 'abc123',
      });
      expect(json['section'], 'home.product-grid');
      expect(json['annotation'], {
        'x': 0.42,
        'y': 0.31,
        'width': 0.18,
        'height': 0.12,
      });
      expect(json['provider'], {
        'name': 'bugdrop',
        'external_ref': 'provider-item-123',
      });

      expect(VisualAttachment.fromJson(json), original);
    });

    test('omits the optional section when absent', () {
      final json = attachment().toJson();
      expect(json.containsKey('section'), isFalse);
    });

    test('throws InvalidVisualAnnotation for malformed payloads', () {
      expect(
        () => VisualAttachment.fromJson(attachment().toJson()..remove('viewport')),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => VisualAttachment.fromJson(
          attachment().toJson()..['screenshot_ref'] = '   ',
        ),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => VisualAttachment.fromJson(
          attachment().toJson()..['annotation'] = 'nope',
        ),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });
  });

  group('VisualAttachment invariants', () {
    test('requires a screenshot ref', () {
      expect(
        () => attachment(screenshotRef: '  '),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('requires positive viewport dimensions', () {
      expect(
        () => attachment(viewportWidth: 0),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => attachment(viewportHeight: -1),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('requires review context', () {
      expect(
        () => attachment(clientId: ''),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => attachment(reviewRound: 0),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => attachment(screenId: ''),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => attachment(effectiveDirection: ''),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => attachment(sourceCommitSha: ''),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('requires provider identity', () {
      expect(
        () => attachment(providerName: ''),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => attachment(externalRef: ''),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('rejects a blank optional section', () {
      expect(
        () => attachment(sectionId: ' '),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });

    test('value equality compares every field', () {
      expect(attachment(), attachment());
      expect(attachment().hashCode, attachment().hashCode);
      expect(attachment(), isNot(attachment(screenId: 'commerce.plp')));
      expect(attachment(), isNot(attachment(sectionId: 'home.product-grid')));
      expect(attachment(), isNot(attachment(externalRef: 'other')));
    });
  });
}
