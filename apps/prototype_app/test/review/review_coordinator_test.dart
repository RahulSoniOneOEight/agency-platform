import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_domain_error.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

const reviewer = ReviewActor(
  id: 'reviewer-123',
  name: 'Rahul',
  role: ReviewRole.reviewer,
);
const agent = ReviewActor(
  id: 'opencode',
  name: 'OpenCode',
  role: ReviewRole.agent,
);
const approver = ReviewActor(
  id: 'approver-456',
  name: 'Priya',
  role: ReviewRole.approver,
);

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
  late PrototypeRuntime runtime;
  late ReviewController controller;
  late MemoryFeedbackRepository feedback;
  late ReviewCoordinator coordinator;

  setUp(() {
    runtime = buildRuntime();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    feedback = MemoryFeedbackRepository();
    coordinator = ReviewCoordinator(
      controller: controller,
      feedbackRepository: feedback,
    );
  });

  Future<FeedbackRecord> create({
    String id = 'feedback-1',
    bool blocking = true,
    ReviewActor actor = reviewer,
    FeedbackScope scope = FeedbackScope.general,
    FeedbackTarget target = const FeedbackTarget(),
  }) {
    return coordinator.createFeedback(
      actor: actor,
      id: id,
      scope: scope,
      text: 'Increase spacing',
      target: target,
      blocking: blocking,
    );
  }

  group('createFeedback', () {
    test('creates an open, blocking record and references it from ReviewState',
        () async {
      final record = await create();

      expect(record.status, FeedbackStatus.open);
      expect(record.blocking, isTrue);
      expect(record.createdRound, 1);
      expect(record.history, hasLength(1));
      expect(record.history.single.type, FeedbackEventType.created);
      expect(record.history.single.actorId, 'reviewer-123');

      expect(await feedback.load('prototype-demo', 'feedback-1'), record);
      expect(controller.state.feedbackIds, ['feedback-1']);
      expect(controller.state.status, ReviewStatus.needsRevision);
    });

    test('a non-blocking record leaves the review status untouched', () async {
      await create(blocking: false);

      expect(controller.state.status, ReviewStatus.inReview);
      expect(controller.state.feedbackIds, ['feedback-1']);
    });

    test('is reviewer-only and writes nothing for other roles', () async {
      for (final actor in const [agent, approver]) {
        await expectLater(
          () => create(id: 'feedback-x', actor: actor),
          throwsA(isA<UnauthorizedReviewAction>()),
        );
      }

      expect(await feedback.list('prototype-demo'), isEmpty);
      expect(controller.state.feedbackIds, isEmpty);
      expect(controller.state.status, ReviewStatus.inReview);
    });

    test('rejects a duplicate id with a typed error and no writes', () async {
      await create();
      final stateBefore = controller.state;
      final savesBefore = await feedback.list('prototype-demo');

      await expectLater(
        () => create(),
        throwsA(
          isA<DuplicateFeedbackId>()
              .having((error) => error.code, 'code', 'duplicate_feedback_id'),
        ),
      );

      expect(controller.state.feedbackIds, ['feedback-1']);
      expect(identical(controller.state, stateBefore), isTrue);
      expect((await feedback.list('prototype-demo')).length, savesBefore.length);
    });

    test('rejects an invalid target with a typed error and no writes', () async {
      final stateBefore = controller.state;

      await expectLater(
        () => create(
          scope: FeedbackScope.section,
          target: const FeedbackTarget(screen: 'commerce.home'),
        ),
        throwsA(isA<InvalidFeedbackTarget>()),
      );

      expect(await feedback.list('prototype-demo'), isEmpty);
      expect(identical(controller.state, stateBefore), isTrue);
    });

    test('stores scope-specific targets', () async {
      final record = await create(
        id: 'feedback-section',
        scope: FeedbackScope.section,
        target: const FeedbackTarget(
          screen: 'commerce.home',
          section: 'home.product-grid',
        ),
      );

      expect(record.scope, FeedbackScope.section);
      expect(record.target.screen, 'commerce.home');
      expect(record.target.section, 'home.product-grid');
    });
  });

  group('feedback lifecycle transitions', () {
    test('an agent may move open feedback to addressed', () async {
      await create();
      final addressed = await coordinator.markAddressed(
        actor: agent,
        feedbackId: 'feedback-1',
        batchId: 'batch-007',
      );

      expect(addressed.status, FeedbackStatus.addressed);
      expect(addressed.history.map((event) => event.type), [
        FeedbackEventType.created,
        FeedbackEventType.addressed,
      ]);
      expect(addressed.history.last.batchId, 'batch-007');
      // Marking addressed never auto-resolves or changes review status.
      expect(controller.state.status, ReviewStatus.needsRevision);
    });

    test('a reviewer may resolve addressed feedback', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      final resolved = await coordinator.resolveFeedback(
        actor: reviewer,
        feedbackId: 'feedback-1',
      );

      expect(resolved.status, FeedbackStatus.resolved);
      expect(resolved.resolvedRound, 1);
      expect(resolved.history.last.type, FeedbackEventType.resolved);
    });

    test('a reviewer may reopen addressed or resolved feedback', () async {
      await create(id: 'feedback-addressed');
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-addressed');
      final reopenedAddressed = await coordinator.reopenFeedback(
        actor: reviewer,
        feedbackId: 'feedback-addressed',
      );
      expect(reopenedAddressed.status, FeedbackStatus.open);
      expect(reopenedAddressed.history.last.type, FeedbackEventType.reopened);

      await create(id: 'feedback-resolved');
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-resolved');
      await coordinator.resolveFeedback(
        actor: reviewer,
        feedbackId: 'feedback-resolved',
      );
      final reopenedResolved = await coordinator.reopenFeedback(
        actor: reviewer,
        feedbackId: 'feedback-resolved',
      );

      expect(reopenedResolved.status, FeedbackStatus.open);
      expect(reopenedResolved.resolvedRound, isNull);
      expect(
        reopenedResolved.history.map((event) => event.type),
        [
          FeedbackEventType.created,
          FeedbackEventType.addressed,
          FeedbackEventType.resolved,
          FeedbackEventType.reopened,
        ],
      );
    });

    test('an open item cannot be resolved directly', () async {
      await create();

      await expectLater(
        () => coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1'),
        throwsA(isA<InvalidFeedbackTransition>()),
      );
    });

    test('an agent cannot resolve feedback', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      await expectLater(
        () => coordinator.resolveFeedback(actor: agent, feedbackId: 'feedback-1'),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
      await expectLater(
        () => coordinator.reopenFeedback(actor: agent, feedbackId: 'feedback-1'),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
    });

    test('only an agent may mark feedback addressed', () async {
      await create();

      for (final actor in const [reviewer, approver]) {
        await expectLater(
          () => coordinator.markAddressed(actor: actor, feedbackId: 'feedback-1'),
          throwsA(isA<UnauthorizedReviewAction>()),
        );
      }
    });

    test('re-addressing an addressed item is an illegal transition', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      await expectLater(
        () => coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1'),
        throwsA(isA<InvalidFeedbackTransition>()),
      );
    });

    test('reopening an already open item is an illegal transition', () async {
      await create();

      await expectLater(
        () => coordinator.reopenFeedback(actor: reviewer, feedbackId: 'feedback-1'),
        throwsA(isA<InvalidFeedbackTransition>()),
      );
    });

    test('unknown feedback ids fail with a typed error and no mutation',
        () async {
      final stateBefore = controller.state;

      await expectLater(
        () => coordinator.resolveFeedback(actor: reviewer, feedbackId: 'missing'),
        throwsA(
          isA<FeedbackNotFound>()
              .having((error) => error.code, 'code', 'feedback_not_found'),
        ),
      );
      await expectLater(
        () => coordinator.setBlocking(
          actor: reviewer,
          feedbackId: 'missing',
          blocking: false,
        ),
        throwsA(isA<FeedbackNotFound>()),
      );
      await expectLater(
        () => coordinator.reopenFeedback(actor: reviewer, feedbackId: 'missing'),
        throwsA(isA<FeedbackNotFound>()),
      );

      expect(identical(controller.state, stateBefore), isTrue);
    });
  });

  group('blocking changes', () {
    test('are reviewer-only', () async {
      await create();

      for (final actor in const [agent, approver]) {
        await expectLater(
          () => coordinator.setBlocking(
            actor: actor,
            feedbackId: 'feedback-1',
            blocking: false,
          ),
          throwsA(isA<UnauthorizedReviewAction>()),
        );
      }
    });

    test('append a blockingChanged event and can drive needsRevision', () async {
      await create(blocking: false);
      expect(controller.state.status, ReviewStatus.inReview);

      final updated = await coordinator.setBlocking(
        actor: reviewer,
        feedbackId: 'feedback-1',
        blocking: true,
      );

      expect(updated.blocking, isTrue);
      expect(updated.history.last.type, FeedbackEventType.blockingChanged);
      expect(updated.status, FeedbackStatus.open);
      expect(controller.state.status, ReviewStatus.needsRevision);
    });

    test('setting the same value is a no-op', () async {
      final created = await create(blocking: true);
      final stateBefore = controller.state;

      final same = await coordinator.setBlocking(
        actor: reviewer,
        feedbackId: 'feedback-1',
        blocking: true,
      );

      expect(same, created);
      expect(same.history, hasLength(1));
      expect(identical(controller.state, stateBefore), isTrue);
    });

    test('drives needsRevision for an addressed (unresolved) item', () async {
      await create(blocking: false);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      expect(controller.state.status, ReviewStatus.inReview);

      await coordinator.setBlocking(
        actor: reviewer,
        feedbackId: 'feedback-1',
        blocking: true,
      );

      expect(controller.state.status, ReviewStatus.needsRevision);
    });

    test('does not change review status for a resolved item', () async {
      await create(blocking: false);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1');
      final statusBefore = controller.state.status;
      final roundBefore = controller.state.reviewRound;

      final updated = await coordinator.setBlocking(
        actor: reviewer,
        feedbackId: 'feedback-1',
        blocking: true,
      );

      expect(updated.blocking, isTrue);
      expect(updated.status, FeedbackStatus.resolved);
      expect(controller.state.status, statusBefore);
      expect(controller.state.reviewRound, roundBefore);
    });
  });

  group('history append-only', () {
    test('retains every prior event across the lifecycle', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.reopenFeedback(actor: reviewer, feedbackId: 'feedback-1');
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1');

      final stored = (await feedback.load('prototype-demo', 'feedback-1'))!;
      expect(stored.history.map((event) => event.type), [
        FeedbackEventType.created,
        FeedbackEventType.addressed,
        FeedbackEventType.reopened,
        FeedbackEventType.addressed,
        FeedbackEventType.resolved,
      ]);
      expect(stored.history.first.type, FeedbackEventType.created);
    });
  });

  group('round eligibility and close', () {
    test('blocking open feedback prevents close with a typed error', () async {
      await create();
      final stateBefore = controller.state;

      expect(await coordinator.isEligibleToCloseRound(), isFalse);
      await expectLater(
        () => coordinator.closeCurrentRound(actor: reviewer),
        throwsA(isA<BlockingFeedbackUnresolved>()),
      );
      expect(identical(controller.state, stateBefore), isTrue);
    });

    test('non-blocking open feedback does not prevent close', () async {
      await create(blocking: false);

      expect(await coordinator.isEligibleToCloseRound(), isTrue);
      await coordinator.closeCurrentRound(actor: reviewer);

      expect(controller.state.status, ReviewStatus.readyForFinalReview);
    });

    test('resolving the last blocker makes the round eligible but does not close it',
        () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1');

      expect(await coordinator.isEligibleToCloseRound(), isTrue);
      expect(controller.state.status, isNot(ReviewStatus.readyForFinalReview));
    });

    test('close is reviewer-only', () async {
      await create(blocking: false);
      final stateBefore = controller.state;

      await expectLater(
        () => coordinator.closeCurrentRound(actor: agent),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
      expect(identical(controller.state, stateBefore), isTrue);
    });

    test('a round already ready for final review is not closable again', () async {
      await create(blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);

      await expectLater(
        () => coordinator.closeCurrentRound(actor: reviewer),
        throwsA(isA<ReviewRoundNotClosable>()),
      );
    });
  });

  group('startNextRound', () {
    test('increments the round, returns to in_review and preserves feedback',
        () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1');
      await coordinator.closeCurrentRound(actor: reviewer);
      final recordBefore = await feedback.load('prototype-demo', 'feedback-1');

      await coordinator.startNextRound(actor: reviewer);

      expect(controller.state.reviewRound, 2);
      expect(controller.state.status, ReviewStatus.inReview);
      expect(controller.state.feedbackIds, ['feedback-1']);
      expect(
        await feedback.load('prototype-demo', 'feedback-1'),
        recordBefore,
      );
    });

    test('is reviewer-only', () async {
      await expectLater(
        () => coordinator.startNextRound(actor: approver),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
      expect(controller.state.reviewRound, 1);
    });

    test('increments monotonically', () async {
      await coordinator.startNextRound(actor: reviewer);
      await coordinator.startNextRound(actor: reviewer);

      expect(controller.state.reviewRound, 3);
    });

    test('new feedback after readiness advances the round', () async {
      await create(blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);
      expect(controller.state.status, ReviewStatus.readyForFinalReview);

      final record = await create(id: 'feedback-2', blocking: true);

      expect(controller.state.reviewRound, 2);
      expect(controller.state.status, ReviewStatus.needsRevision);
      expect(record.createdRound, 2);
      expect(controller.state.feedbackIds, ['feedback-1', 'feedback-2']);
    });
  });

  group('readiness reconciliation on reopen', () {
    test('reopening a blocking item from ready advances the round and revises',
        () async {
      await create(blocking: true);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1');
      await coordinator.closeCurrentRound(actor: reviewer);
      expect(controller.state.status, ReviewStatus.readyForFinalReview);
      expect(controller.state.reviewRound, 1);

      final reopened = await coordinator.reopenFeedback(
        actor: reviewer,
        feedbackId: 'feedback-1',
      );

      expect(reopened.status, FeedbackStatus.open);
      expect(controller.state.status, ReviewStatus.needsRevision);
      expect(controller.state.reviewRound, 2);
      expect(controller.state.feedbackIds, ['feedback-1']);
    });

    test('reopening a non-blocking item from ready leaves readiness unchanged',
        () async {
      await create(id: 'feedback-nb', blocking: false);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-nb');
      await coordinator.closeCurrentRound(actor: reviewer);
      expect(controller.state.status, ReviewStatus.readyForFinalReview);

      await coordinator.reopenFeedback(actor: reviewer, feedbackId: 'feedback-nb');

      expect(controller.state.status, ReviewStatus.readyForFinalReview);
      expect(controller.state.reviewRound, 1);
    });

    test('reopening a blocking item when not ready leaves status unchanged',
        () async {
      await create(blocking: true);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      expect(controller.state.status, ReviewStatus.needsRevision);
      expect(controller.state.reviewRound, 1);

      await coordinator.reopenFeedback(actor: reviewer, feedbackId: 'feedback-1');

      expect(controller.state.status, ReviewStatus.needsRevision);
      expect(controller.state.reviewRound, 1);
    });
  });

  group('read helpers', () {
    test('feedbackForRound filters by creation round', () async {
      await create(id: 'feedback-1');
      await coordinator.startNextRound(actor: reviewer);
      await create(id: 'feedback-2');

      expect(
        (await coordinator.feedbackForRound(1)).map((record) => record.id),
        ['feedback-1'],
      );
      expect(
        (await coordinator.feedbackForRound(2)).map((record) => record.id),
        ['feedback-2'],
      );
    });

    test('blockingUnresolved lists only unresolved blocking feedback', () async {
      await create(id: 'feedback-1', blocking: true);
      await create(id: 'feedback-2', blocking: false);
      await create(id: 'feedback-3', blocking: true);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-3');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-3');

      expect(
        (await coordinator.blockingUnresolved()).map((record) => record.id),
        ['feedback-1'],
      );
    });
  });

  group('typed domain errors', () {
    test('expose stable machine-readable codes', () {
      expect(
        const InvalidFeedbackTransition('x').code,
        'invalid_feedback_transition',
      );
      expect(const InvalidFeedbackTarget('x').code, 'invalid_feedback_target');
      expect(
        const UnauthorizedReviewAction('x').code,
        'unauthorized_review_action',
      );
      expect(
        const BlockingFeedbackUnresolved('x').code,
        'blocking_feedback_unresolved',
      );
      expect(const ReviewRoundNotClosable('x').code, 'review_round_not_closable');
      expect(
        const ReadinessRequiresRoundClose('x').code,
        'readiness_requires_round_close',
      );
      expect(const DuplicateFeedbackId('x').code, 'duplicate_feedback_id');
      expect(const FeedbackNotFound('x').code, 'feedback_not_found');
    });

    test('are exceptions with a message', () {
      final error = const UnauthorizedReviewAction('reviewer role required');
      expect(error, isA<Exception>());
      expect(error.message, 'reviewer role required');
      expect(error.toString(), contains('reviewer role required'));
    });
  });
}
