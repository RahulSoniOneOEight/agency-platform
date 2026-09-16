import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/refinement_batch_repository.dart';
import 'package:prototype_app/review/refinement_execution_result.dart';
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

/// Wraps the in-memory repository so a batch persistence failure can be injected
/// at any point, proving no false addressed transition occurs.
final class _ToggleBatchRepository implements RefinementBatchRepository {
  final MemoryRefinementBatchRepository _inner =
      MemoryRefinementBatchRepository();
  bool failReplace = false;

  @override
  Future<RefinementBatch?> load(String clientId, String batchId) =>
      _inner.load(clientId, batchId);

  @override
  Future<List<RefinementBatch>> list(String clientId) => _inner.list(clientId);

  @override
  Future<void> create(String clientId, RefinementBatch batch) =>
      _inner.create(clientId, batch);

  @override
  Future<void> replace(
    String clientId,
    RefinementBatch expectedCurrent,
    RefinementBatch next,
  ) {
    if (failReplace) {
      throw StateError('injected batch persistence failure');
    }
    return _inner.replace(clientId, expectedCurrent, next);
  }
}

VisualAttachment visualAttachment({String? sectionId}) {
  return VisualAttachment(
    screenshotRef: 'review-home-round-1',
    viewportWidth: 1440,
    viewportHeight: 1200,
    clientId: 'prototype-demo',
    reviewRound: 1,
    screenId: 'commerce.home',
    effectiveDirection: 'a',
    sourceCommitSha: 'abc123',
    annotation: NormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.1),
    providerName: 'bugdrop',
    externalRef: 'provider-item-1',
    sectionId: sectionId,
  );
}

RefinementExecutionResult passedResult({List<String> evidence = const []}) {
  return RefinementExecutionResult(
    status: RefinementExecutionStatus.passed,
    commitSha: 'abc123',
    filesChanged: const ['lib/review/refinement_batch.dart'],
    checks: const [
      ValidationCheck(
        name: 'flutter test test/review',
        passed: true,
        details: 'all green',
      ),
    ],
    evidence: evidence,
  );
}

RefinementExecutionResult failedResult() {
  return RefinementExecutionResult(
    status: RefinementExecutionStatus.failed,
    commitSha: 'abc123',
    checks: const [
      ValidationCheck(
        name: 'flutter test test/review',
        passed: false,
        details: 'one failure',
      ),
    ],
  );
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
  late PrototypeRuntime runtime;
  late ReviewController controller;
  late MemoryFeedbackRepository feedback;
  late MemoryApprovalRepository approvals;
  late MemoryRefinementBatchRepository batches;
  late ReviewCoordinator coordinator;

  setUp(() {
    runtime = buildRuntime();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    feedback = MemoryFeedbackRepository();
    approvals = MemoryApprovalRepository();
    batches = MemoryRefinementBatchRepository();
    coordinator = ReviewCoordinator(
      controller: controller,
      feedbackRepository: feedback,
      approvalRepository: approvals,
      refinementBatchRepository: batches,
    );
  });

  Future<FeedbackRecord> create({
    String id = 'feedback-1',
    bool blocking = true,
    FeedbackScope scope = FeedbackScope.general,
    FeedbackTarget target = const FeedbackTarget(),
    VisualAttachment? visualAttachment,
    ReviewActor actor = reviewer,
  }) {
    return coordinator.createFeedback(
      actor: actor,
      id: id,
      scope: scope,
      text: 'note $id',
      target: target,
      blocking: blocking,
      visualAttachment: visualAttachment,
    );
  }

  IntendedScope homeScope() => IntendedScope(screens: const ['commerce.home']);

  Future<RefinementBatch> createDraft({
    String id = 'batch-1',
    List<String> feedbackIds = const ['feedback-1'],
    ChangeClassification proposed = ChangeClassification.implementationOnly,
    ReviewActor actor = reviewer,
    IntendedScope? scope,
  }) {
    return coordinator.createDraftBatch(
      actor: actor,
      id: id,
      feedbackIds: feedbackIds,
      intendedScope: scope ?? homeScope(),
      proposed: proposed,
    );
  }

  Future<RefinementBatch> readyBatch({
    String id = 'batch-1',
    List<String> feedbackIds = const ['feedback-1'],
    ChangeClassification proposed = ChangeClassification.implementationOnly,
    ChangeClassification? confirmed,
    IntendedScope? scope,
  }) async {
    await createDraft(
      id: id,
      feedbackIds: feedbackIds,
      proposed: proposed,
      scope: scope,
    );
    await coordinator.confirmBatchClassification(
      actor: reviewer,
      batchId: id,
      confirmed: confirmed ?? proposed,
    );
    return coordinator.markBatchReady(actor: reviewer, batchId: id);
  }

  group('createDraftBatch authority', () {
    test('is reviewer-only and persists nothing for other roles', () async {
      await create();
      for (final actor in const [agent, approver]) {
        await expectLater(
          () => createDraft(actor: actor),
          throwsA(isA<UnauthorizedReviewAction>()),
        );
      }
      expect(await batches.list('prototype-demo'), isEmpty);
    });

    test('rejects unknown feedback with a typed error', () async {
      await expectLater(
        () => createDraft(feedbackIds: const ['missing']),
        throwsA(isA<FeedbackNotFound>()),
      );
      expect(await batches.list('prototype-demo'), isEmpty);
    });

    test('rejects feedback that is not open (already addressed)', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      await expectLater(
        () => createDraft(),
        throwsA(isA<InvalidBatchTransition>()),
      );
      expect(await batches.list('prototype-demo'), isEmpty);
    });

    test('rejects a duplicate batch id with a typed error', () async {
      await create();
      await createDraft();

      await expectLater(
        () => createDraft(),
        throwsA(
          isA<DuplicateBatchId>().having(
            (error) => error.code,
            'code',
            'duplicate_batch_id',
          ),
        ),
      );
    });

    test('defaults the proposed classification to contract_impacting (R7)',
        () async {
      await create();
      final batch = await coordinator.createDraftBatch(
        actor: reviewer,
        id: 'batch-1',
        feedbackIds: const ['feedback-1'],
        intendedScope: homeScope(),
      );
      expect(batch.changeClassification.proposed,
          ChangeClassification.contractImpacting);
      expect(batch.changeClassification.isConfirmed, isFalse);
      expect(batch.status, RefinementBatchStatus.draft);
    });
  });

  group('draft editing', () {
    test('updateDraftBatch edits feedback and scope while draft', () async {
      await create();
      await create(id: 'feedback-2');
      await createDraft();

      final updated = await coordinator.updateDraftBatch(
        actor: reviewer,
        batchId: 'batch-1',
        feedbackIds: const ['feedback-1', 'feedback-2'],
        intendedScope: IntendedScope(screens: const ['commerce.plp']),
      );

      expect(updated.feedbackIds, ['feedback-1', 'feedback-2']);
      expect(updated.intendedScope.screens, ['commerce.plp']);
      expect((await coordinator.loadBatch('batch-1'))!.feedbackIds,
          ['feedback-1', 'feedback-2']);
    });

    test('is reviewer-only', () async {
      await create();
      await createDraft();
      await expectLater(
        () => coordinator.updateDraftBatch(
          actor: agent,
          batchId: 'batch-1',
          intendedScope: homeScope(),
        ),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
    });

    test('throws BatchScopeFrozen once ready', () async {
      await create();
      await readyBatch();
      expect(
        () => coordinator.updateDraftBatch(
          actor: reviewer,
          batchId: 'batch-1',
          intendedScope: IntendedScope(screens: const ['commerce.plp']),
        ),
        throwsA(
          isA<BatchScopeFrozen>().having(
            (error) => error.code,
            'code',
            'batch_scope_frozen',
          ),
        ),
      );
    });

    test('a batch with no linked feedback is rejected', () async {
      await expectLater(
        () => createDraft(feedbackIds: const []),
        throwsA(isA<InvalidBatchTransition>()),
      );
    });
  });

  group('classification and ready', () {
    test('confirmBatchClassification is reviewer-only', () async {
      await create();
      await createDraft();
      await expectLater(
        () => coordinator.confirmBatchClassification(
          actor: agent,
          batchId: 'batch-1',
          confirmed: ChangeClassification.implementationOnly,
        ),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
    });

    test('markBatchReady requires a confirmed classification', () async {
      await create();
      await createDraft();

      await expectLater(
        () => coordinator.markBatchReady(actor: reviewer, batchId: 'batch-1'),
        throwsA(isA<ContractClassificationUnconfirmed>()),
      );
      expect((await coordinator.loadBatch('batch-1'))!.status,
          RefinementBatchStatus.draft);
    });

    test('markBatchReady is reviewer-only', () async {
      await create();
      await createDraft();
      await coordinator.confirmBatchClassification(
        actor: reviewer,
        batchId: 'batch-1',
        confirmed: ChangeClassification.implementationOnly,
      );
      await expectLater(
        () => coordinator.markBatchReady(actor: agent, batchId: 'batch-1'),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
    });

    test('ready freezes the confirmed classification', () async {
      await create();
      final ready = await readyBatch(
        proposed: ChangeClassification.contractImpacting,
        confirmed: ChangeClassification.contractImpacting,
      );
      expect(ready.status, RefinementBatchStatus.ready);
      expect(ready.changeClassification.confirmed,
          ChangeClassification.contractImpacting);
      expect(
        () => coordinator.confirmBatchClassification(
          actor: reviewer,
          batchId: 'batch-1',
          confirmed: ChangeClassification.implementationOnly,
        ),
        throwsA(isA<BatchScopeFrozen>()),
      );
    });
  });

  group('execution authority', () {
    test('startBatch is agent-only', () async {
      await create();
      await readyBatch();
      await expectLater(
        () => coordinator.startBatch(actor: reviewer, batchId: 'batch-1'),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
    });

    test('startBatch on a draft batch throws BatchNotReady', () async {
      await create();
      await createDraft();
      await expectLater(
        () => coordinator.startBatch(actor: agent, batchId: 'batch-1'),
        throwsA(
          isA<BatchNotReady>().having(
            (error) => error.code,
            'code',
            'batch_not_ready',
          ),
        ),
      );
    });

    test('recordBatchValidation is agent-only', () async {
      await create();
      await readyBatch();
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');
      await expectLater(
        () => coordinator.recordBatchValidation(
          actor: reviewer,
          batchId: 'batch-1',
          result: passedResult(),
        ),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
    });

    test('recordBatchValidation before start throws BatchNotReady', () async {
      await create();
      await readyBatch();
      await expectLater(
        () => coordinator.recordBatchValidation(
          actor: agent,
          batchId: 'batch-1',
          result: passedResult(),
        ),
        throwsA(isA<BatchNotReady>()),
      );
    });

    test('OpenCode cannot resolve or reopen feedback', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await expectLater(
        () => coordinator.resolveFeedback(actor: agent, feedbackId: 'feedback-1'),
        throwsA(
          isA<UnauthorizedFeedbackResolution>().having(
            (error) => error.code,
            'code',
            'unauthorized_feedback_resolution',
          ),
        ),
      );
      await expectLater(
        () => coordinator.reopenFeedback(actor: agent, feedbackId: 'feedback-1'),
        throwsA(isA<UnauthorizedFeedbackResolution>()),
      );
    });

    test('OpenCode cannot change blocking classification', () async {
      await create();
      await expectLater(
        () => coordinator.setBlocking(
          actor: agent,
          feedbackId: 'feedback-1',
          blocking: false,
        ),
        throwsA(
          isA<UnauthorizedBlockingChange>().having(
            (error) => error.code,
            'code',
            'unauthorized_blocking_change',
          ),
        ),
      );
    });
  });

  group('validation transitions', () {
    test('a passing result moves feedback open -> addressed with a batch id',
        () async {
      await create();
      await readyBatch();
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');

      final reviewed = await coordinator.recordBatchValidation(
        actor: agent,
        batchId: 'batch-1',
        result: passedResult(),
      );

      expect(reviewed.status, RefinementBatchStatus.readyForReview);
      final record = (await feedback.load('prototype-demo', 'feedback-1'))!;
      expect(record.status, FeedbackStatus.addressed);
      expect(record.history.last.type, FeedbackEventType.addressed);
      expect(record.history.last.batchId, 'batch-1');
    });

    test('a failing result leaves feedback open', () async {
      await create();
      await readyBatch();
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');

      final reviewed = await coordinator.recordBatchValidation(
        actor: agent,
        batchId: 'batch-1',
        result: failedResult(),
      );

      expect(reviewed.status, RefinementBatchStatus.validationFailed);
      expect((await feedback.load('prototype-demo', 'feedback-1'))!.status,
          FeedbackStatus.open);
    });

    test('a passing result without a passed check is rejected', () async {
      await create();
      await readyBatch();
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');

      await expectLater(
        () => coordinator.recordBatchValidation(
          actor: agent,
          batchId: 'batch-1',
          result: RefinementExecutionResult(
            status: RefinementExecutionStatus.passed,
            commitSha: 'abc123',
            checks: const [
              ValidationCheck(name: 'flutter analyze', passed: false, details: 'x'),
            ],
          ),
        ),
        throwsA(
          isA<BatchValidationRequired>().having(
            (error) => error.code,
            'code',
            'batch_validation_required',
          ),
        ),
      );
      expect((await feedback.load('prototype-demo', 'feedback-1'))!.status,
          FeedbackStatus.open);
    });

    test('visual feedback requires screenshot evidence on success', () async {
      await create(
        scope: FeedbackScope.visualAnnotation,
        target: const FeedbackTarget(
          screen: 'commerce.home',
          section: 'home.product-grid',
        ),
        visualAttachment: visualAttachment(sectionId: 'home.product-grid'),
      );
      await readyBatch();
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');

      await expectLater(
        () => coordinator.recordBatchValidation(
          actor: agent,
          batchId: 'batch-1',
          result: passedResult(),
        ),
        throwsA(isA<BatchValidationRequired>()),
      );

      final reviewed = await coordinator.recordBatchValidation(
        actor: agent,
        batchId: 'batch-1',
        result: passedResult(evidence: const ['review-home-round-1']),
      );
      expect(reviewed.status, RefinementBatchStatus.readyForReview);
      expect(reviewed.evidence, ['review-home-round-1']);
    });

    test('only linked open feedback becomes addressed', () async {
      await create(id: 'feedback-1');
      await create(id: 'feedback-2');
      await readyBatch(feedbackIds: const ['feedback-1', 'feedback-2']);
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');
      // feedback-2 is addressed outside the batch before validation completes.
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-2');

      await coordinator.recordBatchValidation(
        actor: agent,
        batchId: 'batch-1',
        result: passedResult(),
      );

      expect((await feedback.load('prototype-demo', 'feedback-1'))!.status,
          FeedbackStatus.addressed);
      // feedback-2 was already addressed; it is untouched (no duplicate event).
      expect((await feedback.load('prototype-demo', 'feedback-2'))!.history,
          hasLength(2));
    });
  });

  group('transactional guarantees', () {
    test('a batch persistence failure produces no addressed transition',
        () async {
      final toggling = _ToggleBatchRepository();
      final togglingCoordinator = ReviewCoordinator(
        controller: controller,
        feedbackRepository: feedback,
        approvalRepository: approvals,
        refinementBatchRepository: toggling,
      );
      await create();
      await togglingCoordinator.createDraftBatch(
        actor: reviewer,
        id: 'batch-1',
        feedbackIds: const ['feedback-1'],
        intendedScope: homeScope(),
        proposed: ChangeClassification.implementationOnly,
      );
      await togglingCoordinator.confirmBatchClassification(
        actor: reviewer,
        batchId: 'batch-1',
        confirmed: ChangeClassification.implementationOnly,
      );
      await togglingCoordinator.markBatchReady(
        actor: reviewer,
        batchId: 'batch-1',
      );
      await togglingCoordinator.startBatch(actor: agent, batchId: 'batch-1');

      toggling.failReplace = true;
      await expectLater(
        () => togglingCoordinator.recordBatchValidation(
          actor: agent,
          batchId: 'batch-1',
          result: passedResult(),
        ),
        throwsStateError,
      );

      expect((await feedback.load('prototype-demo', 'feedback-1'))!.status,
          FeedbackStatus.open);
      expect((await toggling.load('prototype-demo', 'batch-1'))!.status,
          RefinementBatchStatus.inProgress);
    });
  });

  group('completion', () {
    Future<RefinementBatch> readyForReview() async {
      await create();
      await readyBatch();
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');
      return coordinator.recordBatchValidation(
        actor: agent,
        batchId: 'batch-1',
        result: passedResult(),
      );
    }

    test('completeBatch is reviewer-only and freezes the batch', () async {
      await readyForReview();
      await expectLater(
        () => coordinator.completeBatch(actor: agent, batchId: 'batch-1'),
        throwsA(isA<UnauthorizedReviewAction>()),
      );

      final completed = await coordinator.completeBatch(
        actor: reviewer,
        batchId: 'batch-1',
      );
      expect(completed.status, RefinementBatchStatus.completed);
      expect(
        () => coordinator.updateDraftBatch(
          actor: reviewer,
          batchId: 'batch-1',
          intendedScope: homeScope(),
        ),
        throwsA(isA<BatchAlreadyCompleted>()),
      );
      expect((await coordinator.loadBatch('batch-1'))!.status,
          RefinementBatchStatus.completed);
    });

    test('completeBatch on a ready batch is an invalid transition', () async {
      await create();
      await readyBatch();
      await expectLater(
        () => coordinator.completeBatch(actor: reviewer, batchId: 'batch-1'),
        throwsA(isA<InvalidBatchTransition>()),
      );
    });
  });

  group('regression reopen', () {
    test('appends a deterministic reopened event with cause/evidence/batchId',
        () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      final reopened = await coordinator.reopenAddressedForRegression(
        actor: agent,
        feedbackId: 'feedback-1',
        cause: 'later regression in batch-2',
        evidence: 'screenshot-2',
        batchId: 'batch-2',
      );

      expect(reopened.status, FeedbackStatus.open);
      expect(reopened.history.last.type, FeedbackEventType.reopened);
      expect(reopened.history.last.batchId, 'batch-2');
      expect(reopened.history.last.cause, 'later regression in batch-2');
      expect(reopened.history.last.evidence, 'screenshot-2');

      final stored = (await feedback.load('prototype-demo', 'feedback-1'))!;
      expect(stored.history.last, reopened.history.last);
      expect(FeedbackRecord.fromJson(stored.toJson()), stored);
    });

    test('is agent-only and only applies to addressed feedback', () async {
      await create();
      await expectLater(
        () => coordinator.reopenAddressedForRegression(
          actor: reviewer,
          feedbackId: 'feedback-1',
          cause: 'c',
          evidence: 'e',
          batchId: 'batch-1',
        ),
        throwsA(isA<UnauthorizedFeedbackResolution>()),
      );

      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-1');
      await expectLater(
        () => coordinator.reopenAddressedForRegression(
          actor: agent,
          feedbackId: 'feedback-1',
          cause: 'c',
          evidence: 'e',
          batchId: 'batch-1',
        ),
        throwsA(isA<InvalidFeedbackTransition>()),
      );
    });

    test('requires a cause, evidence, and batch id', () async {
      await create();
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');
      await expectLater(
        () => coordinator.reopenAddressedForRegression(
          actor: agent,
          feedbackId: 'feedback-1',
          cause: '  ',
          evidence: 'e',
          batchId: 'batch-1',
        ),
        throwsFormatException,
      );
    });
  });

  group('contract-impact approval gate (M2)', () {
    Future<void> completeBatch(
      String id, {
      required String feedbackId,
      required ChangeClassification classification,
    }) async {
      await readyBatch(
        id: id,
        feedbackIds: [feedbackId],
        proposed: classification,
        confirmed: classification,
      );
      await coordinator.startBatch(actor: agent, batchId: id);
      await coordinator.recordBatchValidation(
        actor: agent,
        batchId: id,
        result: passedResult(),
      );
      await coordinator.resolveFeedback(
        actor: reviewer,
        feedbackId: feedbackId,
      );
      await coordinator.completeBatch(actor: reviewer, batchId: id);
    }

    test('an unresolved contract-impacting batch blocks approval', () async {
      await create(id: 'feedback-1', blocking: false);
      await readyBatch(
        proposed: ChangeClassification.contractImpacting,
        confirmed: ChangeClassification.contractImpacting,
      );
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');
      await coordinator.closeCurrentRound(actor: reviewer);

      expect(controller.state.status, ReviewStatus.readyForFinalReview);
      await expectLater(
        () => coordinator.createApproval(
          reviewer: reviewer,
          approver: approver,
          sourceCommitSha: 'abc123',
        ),
        throwsA(
          isA<ContractImpactRequiresNewRound>().having(
            (error) => error.code,
            'code',
            'contract_impact_requires_new_round',
          ),
        ),
      );
      expect(await coordinator.listApprovals(), isEmpty);
      expect(
        (await coordinator.approvalBlockingReasons())
            .any((reason) => reason.contains('Contract-impacting')),
        isTrue,
      );
    });

    test('an implementation-only batch does not block approval', () async {
      await create(id: 'feedback-1', blocking: false);
      await readyBatch(
        proposed: ChangeClassification.implementationOnly,
        confirmed: ChangeClassification.implementationOnly,
      );
      await coordinator.startBatch(actor: agent, batchId: 'batch-1');
      await coordinator.recordBatchValidation(
        actor: agent,
        batchId: 'batch-1',
        result: passedResult(),
      );
      await coordinator.resolveFeedback(
        actor: reviewer,
        feedbackId: 'feedback-1',
      );
      await coordinator.completeBatch(actor: reviewer, batchId: 'batch-1');
      await coordinator.closeCurrentRound(actor: reviewer);

      final snapshot = await coordinator.createApproval(
        reviewer: reviewer,
        approver: approver,
        sourceCommitSha: 'abc123',
      );
      expect(snapshot.version, 1);
    });

    test('contract-impacting work after approval requires a new round',
        () async {
      await create(id: 'feedback-1', blocking: false);
      await create(id: 'feedback-2', blocking: false);
      await completeBatch(
        'batch-1',
        feedbackId: 'feedback-1',
        classification: ChangeClassification.contractImpacting,
      );
      await coordinator.closeCurrentRound(actor: reviewer);
      final first = await coordinator.createApproval(
        reviewer: reviewer,
        approver: approver,
        sourceCommitSha: 'abc123',
      );
      expect(first.version, 1);
      expect(first.reviewRound, 1);
      expect(first.unresolvedNonBlockingFeedbackIds, ['feedback-2']);

      // Same round, no new feedback: a contract-impacting batch refined from
      // the already-open feedback-2 still blocks re-approval.
      await completeBatch(
        'batch-2',
        feedbackId: 'feedback-2',
        classification: ChangeClassification.contractImpacting,
      );

      await expectLater(
        () => coordinator.createApproval(
          reviewer: reviewer,
          approver: approver,
          sourceCommitSha: 'def456',
        ),
        throwsA(
          isA<ContractImpactRequiresNewRound>().having(
            (error) => error.code,
            'code',
            'contract_impact_requires_new_round',
          ),
        ),
      );

      // Advancing to a new round allows approval-v2 without rewriting v1.
      await coordinator.startNextRound(actor: reviewer);
      await coordinator.closeCurrentRound(actor: reviewer);
      final second = await coordinator.createApproval(
        reviewer: reviewer,
        approver: approver,
        sourceCommitSha: 'def456',
      );
      expect(second.version, 2);
      expect(second.supersedes, 1);
      expect(second.reviewRound, 2);
      expect((await coordinator.listApprovals()).first, first);
    });
  });

  group('typed refinement errors expose stable codes', () {
    test('batch and authority errors carry machine-readable codes', () {
      expect(const BatchNotFound('x').code, 'batch_not_found');
      expect(const DuplicateBatchId('x').code, 'duplicate_batch_id');
      expect(const BatchScopeFrozen('x').code, 'batch_scope_frozen');
      expect(const BatchNotReady('x').code, 'batch_not_ready');
      expect(const BatchAlreadyCompleted('x').code, 'batch_already_completed');
      expect(const InvalidBatchTransition('x').code, 'invalid_batch_transition');
      expect(const BatchValidationRequired('x').code, 'batch_validation_required');
      expect(const BatchValidationFailed('x').code, 'batch_validation_failed');
      expect(
        const UnauthorizedFeedbackResolution('x').code,
        'unauthorized_feedback_resolution',
      );
      expect(
        const UnauthorizedBlockingChange('x').code,
        'unauthorized_blocking_change',
      );
      expect(
        const ContractClassificationUnconfirmed('x').code,
        'contract_classification_unconfirmed',
      );
      expect(
        const ContractImpactRequiresNewRound('x').code,
        'contract_impact_requires_new_round',
      );
    });
  });
}
