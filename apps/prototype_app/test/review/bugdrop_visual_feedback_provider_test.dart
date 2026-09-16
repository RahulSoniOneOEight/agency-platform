import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/bugdrop_visual_feedback_provider.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_domain_error.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/review/visual_attachment.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

const reviewer = ReviewActor(
  id: 'reviewer-123',
  name: 'Rahul',
  role: ReviewRole.reviewer,
);

Map<String, Object?> bugdropPayload({
  Object? screenshotRef = 'review-home-round-2',
  Object? bounds = const {
    'left': 0.42,
    'top': 0.31,
    'right': 0.60,
    'bottom': 0.43,
  },
  Object? section = 'home.product-grid',
  Object? providerItemId = 'provider-item-123',
}) {
  return {
    'screenshot_ref': screenshotRef,
    'viewport': {'width': 1440, 'height': 1200},
    'context': {
      'client_id': 'prototype-demo',
      'review_round': 2,
      'screen': 'commerce.home',
      'effective_direction': 'b',
      'source_commit_sha': 'abc123',
      if (section != null) 'section': section,
    },
    'bounds': bounds,
    'provider_item_id': providerItemId,
  };
}

PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
    ),
  );
}

void main() {
  const provider = BugDropVisualFeedbackProvider();

  group('normalization', () {
    test('normalizes a BugDrop payload into provider-neutral evidence', () {
      final attachment = provider.normalize(bugdropPayload());

      expect(attachment.screenshotRef, 'review-home-round-2');
      expect(attachment.viewportWidth, 1440);
      expect(attachment.viewportHeight, 1200);
      expect(attachment.clientId, 'prototype-demo');
      expect(attachment.reviewRound, 2);
      expect(attachment.screenId, 'commerce.home');
      expect(attachment.effectiveDirection, 'b');
      expect(attachment.sourceCommitSha, 'abc123');
      expect(attachment.sectionId, 'home.product-grid');
      expect(attachment.providerName, BugDropVisualFeedbackProvider.providerName);
      expect(attachment.externalRef, 'provider-item-123');
      expect(attachment.annotation.x, closeTo(0.42, 1e-9));
      expect(attachment.annotation.y, closeTo(0.31, 1e-9));
      expect(attachment.annotation.width, closeTo(0.18, 1e-9));
      expect(attachment.annotation.height, closeTo(0.12, 1e-9));
    });

    test('supports a free-form annotation without a section', () {
      final attachment = provider.normalize(bugdropPayload(section: null));

      expect(attachment.sectionId, isNull);
      expect(attachment.toJson().containsKey('section'), isFalse);
    });
  });

  group('typed ingestion errors', () {
    test('rejects a payload missing required structure', () {
      expect(
        () => provider.normalize(bugdropPayload(screenshotRef: null)),
        throwsA(
          isA<UnsupportedVisualProviderPayload>().having(
            (error) => error.code,
            'code',
            'unsupported_visual_provider_payload',
          ),
        ),
      );
      expect(
        () => provider.normalize(bugdropPayload(bounds: null)),
        throwsA(isA<UnsupportedVisualProviderPayload>()),
      );
      expect(
        () => provider.normalize(bugdropPayload(providerItemId: 7)),
        throwsA(isA<UnsupportedVisualProviderPayload>()),
      );
    });

    test('rejects out-of-range bounds with a typed annotation error', () {
      expect(
        () => provider.normalize(
          bugdropPayload(
            bounds: const {
              'left': 0.9,
              'top': 0.1,
              'right': 1.2,
              'bottom': 0.3,
            },
          ),
        ),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
      expect(
        () => provider.normalize(
          bugdropPayload(
            bounds: const {
              'left': 0.5,
              'top': 0.1,
              'right': 0.4,
              'bottom': 0.3,
            },
          ),
        ),
        throwsA(isA<InvalidVisualAnnotation>()),
      );
    });
  });

  group('provider authority', () {
    test('normalization never mutates feedback, review or approval state',
        () async {
      final runtime = buildRuntime();
      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );
      final feedback = MemoryFeedbackRepository();
      final approvals = MemoryApprovalRepository();
      final coordinator = ReviewCoordinator(
        controller: controller,
        feedbackRepository: feedback,
        approvalRepository: approvals,
      );
      expect(coordinator.clientId, 'prototype-demo');
      final stateBefore = controller.state;

      final attachment = provider.normalize(bugdropPayload());
      expect(attachment, isA<VisualAttachment>());

      expect(identical(controller.state, stateBefore), isTrue);
      expect(controller.state.status, ReviewStatus.inReview);
      expect(await feedback.list('prototype-demo'), isEmpty);
      expect(await approvals.list('prototype-demo'), isEmpty);
    });
  });
}
