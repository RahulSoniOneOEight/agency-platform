import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/persistence/file_qa_finding_repository.dart';
import 'package:prototype_app/qa/persistence/file_qa_run_repository.dart';
import 'package:prototype_app/qa/persistence/qa_persistence_layout.dart';
import 'package:prototype_app/qa/qa_coordinator.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/qa/visual_qa_provider.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';

import 'support/reference_client_fixtures.dart';

/// Milestone F.2 — the automated visual-QA boundary for the reference client.
///
/// Automated QA can only ever produce a `QaFinding`; the sole path into human
/// review is an explicit reviewer promotion. This test pins the boundary:
/// detection, triage, idempotent promotion, no auto-resolution, and the
/// dismissal path that creates no feedback at all. The provider is the offline
/// `FixtureVisualQaProvider` (RF12); no credentials or network are involved.
const reviewer = ReviewActor(
  id: 'reviewer-123',
  name: 'Rahul',
  role: ReviewRole.reviewer,
);

const captureId =
    'sha256:4187fa0a2878b8298f57f293c933c880520b2014ff1279c00d029c566e16ce44';
const sourceCommitSha = '0123456789abcdef0123456789abcdef01234567';

VisualQaCandidate _candidate({
  required String ruleRef,
  required String category,
  required String summary,
}) {
  return VisualQaCandidate.fromJson({
    'category': category,
    'severity': 'major',
    'summary': summary,
    'surface': 'prototype',
    'screen': 'commerce.pdp',
    'state': 'default',
    'direction': 'b',
    'section': 'pdp.price',
    'screenshot_ref': captureId,
    'rule_source': 'design_contract',
    'rule_ref': ruleRef,
    'confidence': 0.9,
  });
}

Future<QaFinding> _detect(
  QaCoordinator qa,
  VisualQaCandidate candidate, {
  required String id,
  required String clientId,
}) async {
  final context = VisualQaContext(
    clientId: clientId,
    surface: QaSurface.prototype,
    screen: 'commerce.pdp',
    state: 'default',
    direction: 'b',
    section: 'pdp.price',
    sourceCommitSha: sourceCommitSha,
    fixtureVersion: '1',
  );
  final provider = FixtureVisualQaProvider(candidates: [candidate]);
  final reviewed = await provider.review(
    VisualQaRequest(
      context: context,
      artifacts: const [
        VisualQaArtifactRef(captureId: captureId, contentHash: 'sha256:content'),
      ],
      authority: VisualQaAuthorityBundle(
        entries: const [
          VisualQaAuthorityEntry(
            source: QaRuleSource.designContract,
            refs: ['design-contract/tokens'],
          ),
        ],
      ),
    ),
  );
  return qa.recordFinding(
    reviewed.single.toFinding(
      id: id,
      context: context,
      actorId: 'visual-qa',
      at: DateTime.utc(2026, 9, 18, 10),
    ),
  );
}

void main() {
  late Directory tempRoot;
  late QaPersistenceLayout qaLayout;
  late ReviewController controller;
  late ReviewCoordinator review;
  late QaCoordinator qa;
  late String clientId;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('f2-qa-');
    qaLayout = QaPersistenceLayout(clientProjectsDirectory: tempRoot);
    final runtime = loadReferenceRuntime();
    clientId = runtime.clientId;
    controller = ReviewController(
      clientId: clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    review = ReviewCoordinator(
      controller: controller,
      feedbackRepository: MemoryFeedbackRepository(),
      approvalRepository: MemoryApprovalRepository(),
      refinementBatchRepository: MemoryRefinementBatchRepository(),
    );
    qa = QaCoordinator(
      findings: FileQaFindingRepository(layout: qaLayout),
      review: review,
      runs: FileQaRunRepository(layout: qaLayout),
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('finding -> triage -> explicit idempotent promotion (no auto-resolve)',
      () async {
    final finding = await _detect(
      qa,
      _candidate(
        ruleRef: 'spacing.price.rule',
        category: 'spacing',
        summary: 'Price rule spacing is inconsistent with the token grid.',
      ),
      id: 'qa-001',
      clientId: clientId,
    );

    expect(finding.status, QaFindingStatus.detected);
    expect(finding.blocking, isNull,
        reason: 'QA severity never implies C.4 blocking');
    expect(finding.feedbackId, isNull);
    expect(await qa.loadFinding('qa-001'), finding);

    await qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    final triaged = await qa.loadFinding('qa-001');
    expect(triaged!.status, QaFindingStatus.triaged);

    // No FeedbackRecord exists before an explicit promotion.
    expect(
      (await review.allFeedback())
          .where((record) => record.originQaFindingId != null),
      isEmpty,
    );

    final promoted =
        await qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
    expect(promoted.originQaFindingId, 'qa-001');
    expect(promoted.status, FeedbackStatus.open);
    expect(promoted.blocking, isFalse);
    expect(promoted.status, isNot(FeedbackStatus.resolved));
    expect(promoted.history.map((event) => event.type),
        contains(FeedbackEventType.created));

    final promotedAgain =
        await qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
    expect(promotedAgain.id, promoted.id);
    expect(
      (await review.allFeedback())
          .where((record) => record.originQaFindingId == 'qa-001')
          .length,
      1,
    );
    final persistedFinding = await qa.loadFinding('qa-001');
    expect(persistedFinding!.status, QaFindingStatus.promoted);
    expect(persistedFinding.feedbackId, promoted.id);
  });

  test('reviewer dismissal creates no FeedbackRecord', () async {
    final finding = await _detect(
      qa,
      _candidate(
        ruleRef: 'contrast.text.ratio',
        category: 'contrast',
        summary: 'Secondary text contrast is below the governed ratio.',
      ),
      id: 'qa-002',
      clientId: clientId,
    );

    await qa.triageFinding(findingId: finding.id, actor: reviewer);
    final dismissed = await qa.dismissFinding(
      findingId: finding.id,
      actor: reviewer,
      reason: 'Governed token is being updated separately.',
    );
    expect(dismissed.status, QaFindingStatus.dismissed);
    expect(
      (await review.allFeedback())
          .where((record) => record.originQaFindingId == finding.id),
      isEmpty,
    );
    expect(await review.allFeedback(), isEmpty);
  });
}
