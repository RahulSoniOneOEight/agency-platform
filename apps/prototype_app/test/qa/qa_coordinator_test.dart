import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/memory_qa_finding_repository.dart';
import 'package:prototype_app/qa/qa_coordinator.dart';
import 'package:prototype_app/qa/qa_domain_error.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_domain_error.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';
import 'support/qa_fixtures.dart';

const reviewer = ReviewActor(
  id: 'reviewer-1',
  name: 'Reviewer',
  role: ReviewRole.reviewer,
);
const agent = ReviewActor(
  id: 'opencode',
  name: 'OpenCode',
  role: ReviewRole.agent,
);

PrototypeRuntime _runtime() => PrototypeRuntime.fromMap(
      canonicalBundle(
        directionIds: const ['a', 'b'],
        patterns: const {
          'a': ['commerce.home'],
          'b': ['commerce.home'],
        },
      ),
    );

final class _Harness {
  _Harness() {
    final runtime = _runtime();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    feedback = MemoryFeedbackRepository();
    review = ReviewCoordinator(
      controller: controller,
      feedbackRepository: feedback,
      approvalRepository: MemoryApprovalRepository(),
      refinementBatchRepository: MemoryRefinementBatchRepository(),
    );
    findings = MemoryQaFindingRepository();
    qa = QaCoordinator(findings: findings, review: review);
  }

  late final ReviewController controller;
  late final MemoryFeedbackRepository feedback;
  late final ReviewCoordinator review;
  late final MemoryQaFindingRepository findings;
  late final QaCoordinator qa;
}

DateTime at(int minute) => DateTime.utc(2026, 9, 17, 11, minute);

void main() {
  group('finding intake and deduplication', () {
    test('a new finding is persisted as detected', () async {
      final h = _Harness();
      final recorded = await h.qa.recordFinding(sampleQaFinding());
      expect(recorded.status, QaFindingStatus.detected);
      expect((await h.findings.list('prototype-demo')), hasLength(1));
    });

    test('rediscovering the same issue links evidence to the active finding',
        () async {
      final h = _Harness();
      final first = await h.qa.recordFinding(sampleQaFinding(confidence: 0.4));
      final second = await h.qa.recordFinding(
        sampleQaFinding(
          id: 'qa-002',
          confidence: 0.99,
          evidence: [QaEvidence(note: 're-observed on the same run')],
        ),
      );
      expect(second.id, first.id, reason: 'must not create an endless duplicate');
      expect(second.evidence, hasLength(1));
      expect(await h.findings.list('prototype-demo'), hasLength(1));
      expect(second.history.last.event, QaFindingEventType.evidenceLinked);
    });

    test('a rediscovery after a successful recheck records a recurrence',
        () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.markFindingNoLongerReproducible(
        findingId: 'qa-001',
        runId: 'run-1',
      );
      final recurred = await h.qa.recordFinding(sampleQaFinding(id: 'qa-002'));
      expect(recurred.id, 'qa-001');
      expect(recurred.isNoLongerReproducible, isFalse);
      expect(recurred.recurrences, 1);
    });

    test('a dismissed finding does not absorb a rediscovery', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      await h.qa.dismissFinding(
        findingId: 'qa-001',
        actor: reviewer,
        reason: 'not actionable',
      );
      final fresh = await h.qa.recordFinding(sampleQaFinding(id: 'qa-002'));
      expect(fresh.id, 'qa-002');
      expect(fresh.status, QaFindingStatus.detected);
      expect(await h.findings.list('prototype-demo'), hasLength(2));
    });

    test('a different issue creates a separate finding', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      final other = await h.qa.recordFinding(
        sampleQaFinding(id: 'qa-002', category: 'clipping'),
      );
      expect(other.id, 'qa-002');
      expect(await h.findings.list('prototype-demo'), hasLength(2));
    });
  });

  group('reviewer triage', () {
    test('triage, dismiss, and accept-risk are QA-only lifecycle moves',
        () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      final triaged = await h.qa.triageFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      expect(triaged.status, QaFindingStatus.triaged);

      final dismissed = await h.qa.dismissFinding(
        findingId: 'qa-001',
        actor: reviewer,
        reason: 'not reproducible',
      );
      expect(dismissed.status, QaFindingStatus.dismissed);
      expect(await h.review.allFeedback(), isEmpty);
      expect(h.controller.state.feedbackIds, isEmpty);
    });

    test('triage does not touch review state', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      final before = h.controller.state.toJson();
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      expect(h.controller.state.toJson(), before);
    });
  });

  group('reviewer promotion', () {
    test('promotion is explicit and idempotent', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);

      final first = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      final second = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );

      expect(second.id, first.id);
      expect(second.originQaFindingId, 'qa-001');
      expect(await h.review.allFeedback(), hasLength(1));
    });

    test('promotion requires reviewer authority', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      await expectLater(
        h.qa.promoteFinding(findingId: 'qa-001', actor: agent),
        throwsA(isA<UnauthorizedReviewAction>()),
      );
      expect(await h.review.allFeedback(), isEmpty);
    });

    test('promotion requires triage first', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await expectLater(
        h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer),
        throwsA(isA<QaFindingNotPromotable>()),
      );
      expect(await h.review.allFeedback(), isEmpty);
    });

    test('promotion preserves the originating finding id', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      final record = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      expect(record.originQaFindingId, 'qa-001');
      final finding = await h.findings.load('prototype-demo', 'qa-001');
      expect(finding!.status, QaFindingStatus.promoted);
      expect(finding.feedbackId, record.id);
    });

    test('severity never becomes blocking', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding(severity: QaSeverity.blocker));
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      final record = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      expect(record.blocking, isFalse);
    });

    test('a reviewer may explicitly promote as blocking', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      final record = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
        blocking: true,
      );
      expect(record.blocking, isTrue);
    });

    test('promotion maps a governed screen and section onto the feedback target',
        () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      final record = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      expect(record.scope, FeedbackScope.section);
      expect(record.target.screen, 'commerce.home');
      expect(record.target.section, 'home.product-grid');
    });

    test('a widgetbook finding promotes as general feedback', () async {
      final h = _Harness();
      await h.qa.recordFinding(
        sampleQaFinding(
          id: 'qa-010',
          surface: QaSurface.widgetbook,
          screen: null,
          story: 'AgencyButton.Primary',
          section: null,
          direction: null,
        ),
      );
      await h.qa.triageFinding(findingId: 'qa-010', actor: reviewer);
      final record = await h.qa.promoteFinding(
        findingId: 'qa-010',
        actor: reviewer,
      );
      expect(record.scope, FeedbackScope.general);
      expect(record.originQaFindingId, 'qa-010');
    });

    test('failed feedback creation leaves the finding unpromoted', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      // A pre-existing unrelated feedback record occupies the deterministic id.
      await h.review.createFeedback(
        actor: reviewer,
        id: 'feedback-qa-001',
        scope: FeedbackScope.general,
        text: 'unrelated',
        target: const FeedbackTarget(),
      );

      await expectLater(
        h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer),
        throwsA(isA<DuplicateFeedbackId>()),
      );
      final finding = await h.findings.load('prototype-demo', 'qa-001');
      expect(finding!.status, QaFindingStatus.triaged);
      expect(finding.feedbackId, isNull);
    });

    test('an orphaned feedback record is reconciled rather than duplicated',
        () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      // Simulate a crash after feedback creation but before the finding link.
      final orphan = await h.review.createFeedback(
        actor: reviewer,
        id: 'feedback-qa-001',
        scope: FeedbackScope.section,
        text: 'Product-card spacing is inconsistent with the governed token.',
        target: const FeedbackTarget(
          screen: 'commerce.home',
          section: 'home.product-grid',
        ),
        originQaFindingId: 'qa-001',
      );

      final promoted = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      expect(promoted.id, orphan.id);
      expect(await h.review.allFeedback(), hasLength(1));
      final finding = await h.findings.load('prototype-demo', 'qa-001');
      expect(finding!.status, QaFindingStatus.promoted);
    });

    test('promotion does not resolve or reclassify feedback', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      final record = await h.qa.promoteFinding(
        findingId: 'qa-001',
        actor: reviewer,
      );
      expect(record.status, FeedbackStatus.open);
      expect(record.history, hasLength(1));
    });

    test('promotion never mutates approval or refinement state', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      await h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
      expect(await h.review.listApprovals(), isEmpty);
      expect(await h.review.allBatches(), isEmpty);
    });

    test('a finding is promoted at most once even under concurrent calls',
        () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      final results = await Future.wait([
        h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer),
        h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer),
      ]);
      expect(results[0].id, results[1].id);
      expect(await h.review.allFeedback(), hasLength(1));
    });
  });

  group('coordinator boundaries', () {
    test('a promoted record stays open until the reviewer acts on it', () async {
      final h = _Harness();
      await h.qa.recordFinding(sampleQaFinding());
      await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
      await h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
      final feedback = (await h.review.allFeedback()).single;
      expect(feedback.status, FeedbackStatus.open);
      // Promotion must not shortcut the C.4 lifecycle: open feedback cannot be
      // resolved until refinement addresses it and the reviewer re-checks.
      await expectLater(
        h.review.resolveFeedback(actor: reviewer, feedbackId: feedback.id),
        throwsA(isA<InvalidFeedbackTransition>()),
      );
    });
  });
}
