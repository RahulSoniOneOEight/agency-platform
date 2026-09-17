import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/persistence/file_qa_finding_repository.dart';
import 'package:prototype_app/qa/persistence/file_qa_run_repository.dart';
import 'package:prototype_app/qa/persistence/qa_persistence_layout.dart';
import 'package:prototype_app/qa/qa_coordinator.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/qa/qa_run.dart';
import 'package:prototype_app/qa/visual_qa_provider.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/persistence/file_approval_repository.dart';
import 'package:prototype_app/review/persistence/file_feedback_repository.dart';
import 'package:prototype_app/review/persistence/file_refinement_batch_repository.dart';
import 'package:prototype_app/review/persistence/review_persistence_layout.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/refinement_execution_result.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

/// Milestone D end-to-end flow, exactly as the design spec describes it:
///
/// ```text
/// C.3 selected/mixed experience
///   â†’ deterministic capture metadata
///   â†’ golden + Visual AI candidate
///   â†’ QAFinding
///   â†’ reviewer triage
///   â†’ explicit promotion
///   â†’ FeedbackRecord(originQaFindingId)
///   â†’ C.7 refinement batch
///   â†’ successful validation (feedback addressed)
///   â†’ targeted re-check (only affected surfaces)
///   â†’ QA finding no longer reproducible
///   â†’ FeedbackRecord still awaits reviewer resolution
/// ```
///
/// Capture and provider execution use deterministic fixtures: no browser and no
/// network are involved.
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

PrototypeRuntime _loadReferenceRuntime() {
  final decoded = json.decode(
    File('assets/generated/prototype-demo.json').readAsStringSync(),
  ) as Map;
  return PrototypeRuntime.fromMap(Map<String, dynamic>.from(decoded));
}

void main() {
  late Directory tempRoot;
  late QaPersistenceLayout qaLayout;
  late ReviewPersistenceLayout reviewLayout;
  late PrototypeRuntime runtime;
  late ReviewController controller;
  late ReviewCoordinator review;
  late FileQaFindingRepository findings;
  late QaCoordinator qa;
  late String bundleJsonBefore;
  late Set<String> directionsBefore;
  late Set<String> themesBefore;
  late Set<String> resourcesBefore;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('d1-d4-e2e-');
    qaLayout = QaPersistenceLayout(clientProjectsDirectory: tempRoot);
    reviewLayout = ReviewPersistenceLayout(clientProjectsDirectory: tempRoot);
    runtime = _loadReferenceRuntime();
    bundleJsonBefore = json.encode({
      'directions': {
        for (final entry in runtime.directions.entries)
          entry.key: entry.value.patterns,
      },
      'direction_themes': runtime.directionThemes.keys.toList(),
      'resources': runtime.resources.keys.toList(),
    });
    directionsBefore = runtime.directions.keys.toSet();
    themesBefore = runtime.directionThemes.keys.toSet();
    resourcesBefore = runtime.resources.keys.toSet();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    review = ReviewCoordinator(
      controller: controller,
      feedbackRepository: FileFeedbackRepository(layout: reviewLayout),
      approvalRepository: FileApprovalRepository(layout: reviewLayout),
      refinementBatchRepository:
          FileRefinementBatchRepository(layout: reviewLayout),
    );
    findings = FileQaFindingRepository(layout: qaLayout);
    qa = QaCoordinator(
      findings: findings,
      review: review,
      runs: FileQaRunRepository(layout: qaLayout),
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('D.1-D.4 end-to-end capture, QA, promotion, refinement, and re-check',
      () async {
    // --- C.3 selected/mixed experience -------------------------------------
    await controller.selectDirection('c');
    await controller.setSectionDirection('commerce.plp', 'plp.product-grid', 'a');
    expect(controller.state.selectedDirection, 'c');
    expect(
      controller.state.screenSelections['commerce.plp']!.sections['plp.product-grid'],
      'a',
    );

    // --- Deterministic capture metadata (D.1) ------------------------------
    const captureId =
        'sha256:4187fa0a2878b8298f57f293c933c880520b2014ff1279c00d029c566e16ce44';
    final job = QaCaptureJob(
      captureId: captureId,
      clientId: runtime.clientId,
      surface: QaSurfaceRef.prototype,
      screen: 'commerce.plp',
      state: 'default',
      direction: 'c',
      mixRef: 'review-state-v2',
      viewportWidth: 390,
      viewportHeight: 844,
      fixtureVersion: 'demo-v1',
    );
    const sourceCommitSha = 'abc123';

    // --- Golden + Visual AI candidate (D.2/D.3) ----------------------------
    // A golden mismatch and an AI review both produce candidates; neither can
    // become review state directly.
    final provider = FixtureVisualQaProvider(
      candidates: [
        VisualQaCandidate.fromJson({
          'category': 'spacing',
          'severity': 'major',
          'summary':
              'Product-card spacing is inconsistent with the governed token.',
          'surface': 'prototype',
          'screen': 'commerce.plp',
          'state': 'default',
          'direction': 'c',
          'section': 'plp.product-grid',
          'region': {'x': 0.1, 'y': 0.42, 'width': 0.8, 'height': 0.24},
          'screenshot_ref': captureId,
          'rule_source': 'design_contract',
          'rule_ref': 'spacing.card.gap',
          'confidence': 0.91,
        }),
      ],
    );
    final context = VisualQaContext(
      clientId: runtime.clientId,
      surface: QaSurface.prototype,
      screen: 'commerce.plp',
      state: 'default',
      direction: 'c',
      mixRef: 'review-state-v2',
      sourceCommitSha: sourceCommitSha,
      fixtureVersion: 'demo-v1',
    );
    final authority = VisualQaAuthorityBundle(
      entries: const [
        VisualQaAuthorityEntry(
          source: QaRuleSource.designContract,
          refs: ['design-contract/tokens'],
        ),
      ],
    );
    final candidates = await provider.review(
      VisualQaRequest(
        context: context,
        artifacts: const [
          VisualQaArtifactRef(
            captureId: captureId,
            contentHash: 'sha256:content',
            viewportWidth: 390,
            viewportHeight: 844,
          ),
        ],
        authority: authority,
      ),
    );
    final finding = await qa.recordFinding(
      candidates.single.toFinding(
        id: 'qa-001',
        context: context,
        actorId: 'visual-qa',
        at: DateTime.utc(2026, 9, 17, 10),
      ),
    );
    expect(finding.status, QaFindingStatus.detected);
    expect(finding.screenshotRef, captureId);
    expect(finding.sourceCommitSha, sourceCommitSha);
    expect(finding.blocking, isNull, reason: 'QA severity never implies blocking');
    expect(await review.allFeedback(), isEmpty);

    // Deduplication: the same issue rediscovered links evidence instead of
    // creating a second finding.
    final rediscovered = await qa.recordFinding(
      candidates.single.toFinding(
        id: 'qa-002',
        context: context,
        actorId: 'visual-qa',
        at: DateTime.utc(2026, 9, 17, 10, 5),
      ),
    );
    expect(rediscovered.id, 'qa-001');
    expect(await findings.list(runtime.clientId), hasLength(1));

    // --- Reviewer triage + explicit promotion (D.4) -------------------------
    await qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    final feedback = await qa.promoteFinding(
      findingId: 'qa-001',
      actor: reviewer,
    );
    expect(feedback.originQaFindingId, 'qa-001');
    expect(feedback.status, FeedbackStatus.open);
    expect(feedback.blocking, isFalse);
    // Promotion defaults to non-blocking (QA severity never sets blocking), so
    // the review status is unchanged; the reviewer owns blocking classification.
    expect(controller.state.status, ReviewStatus.inReview);

    // Promotion is idempotent.
    final again = await qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
    expect(again.id, feedback.id);
    expect(await review.allFeedback(), hasLength(1));

    // --- C.7 refinement batch ---------------------------------------------
    await review.createDraftBatch(
      actor: reviewer,
      id: 'batch-001',
      feedbackIds: [feedback.id],
      intendedScope: IntendedScope(screens: const ['commerce.plp']),
      proposed: ChangeClassification.implementationOnly,
    );
    await review.confirmBatchClassification(
      actor: reviewer,
      batchId: 'batch-001',
      confirmed: ChangeClassification.implementationOnly,
    );
    await review.markBatchReady(actor: reviewer, batchId: 'batch-001');
    await review.startBatch(
      actor: agent,
      batchId: 'batch-001',
      agent: 'opencode',
      model: 'deepseek/deepseek-v4-pro',
    );
    await review.recordBatchValidation(
      actor: agent,
      batchId: 'batch-001',
      result: RefinementExecutionResult(
        status: RefinementExecutionStatus.passed,
        commitSha: 'def456',
        filesChanged: const ['packages/agency_flutter_ui/lib/domain/product_card.dart'],
        checks: const [
          ValidationCheck(name: 'flutter test', passed: true, details: 'all green'),
          ValidationCheck(name: 'flutter analyze', passed: true, details: 'no issues'),
        ],
        evidence: const ['build/visual-qa/screenshots/plp-product-grid.png'],
      ),
    );
    final addressed = await review.loadFeedback(feedback.id);
    expect(addressed!.status, FeedbackStatus.addressed);

    // --- Targeted re-check (D.4) ------------------------------------------
    // Only the affected governed surface is re-captured.
    final affected = affectedCaptureJobs(
      jobs: [
        job,
        QaCaptureJob(
          captureId: 'sha256:unrelated',
          clientId: runtime.clientId,
          surface: QaSurfaceRef.prototype,
          screen: 'commerce.cart',
          state: 'default',
          direction: 'c',
          viewportWidth: 390,
          viewportHeight: 844,
          fixtureVersion: 'demo-v1',
        ),
      ],
      changedScreens: {'commerce.plp'},
    );
    expect(affected.map((item) => item.captureId), [captureId]);

    final run = QaRun(
      id: 'run-001',
      clientId: runtime.clientId,
      sourceCommitSha: 'def456',
      actorId: 'qa-runner',
      startedAt: DateTime.utc(2026, 9, 17, 11),
      completedAt: DateTime.utc(2026, 9, 17, 11, 1),
      refinementBatchId: 'batch-001',
      captureIds: [captureId],
      baselineIds: const ['baseline:plp-product-grid'],
      checks: const [
        QaCheckResult(
          name: 'golden:commerce.plp',
          kind: QaCheckKind.golden,
          passed: true,
          detail: 'matches governed baseline',
        ),
        QaCheckResult(
          name: 'visual-ai:commerce.plp',
          kind: QaCheckKind.visualAi,
          passed: true,
          detail: 'no new findings',
        ),
      ],
      findingIds: const ['qa-001'],
    );
    final rechecked = await qa.recordSuccessfulRecheck(
      findingId: 'qa-001',
      run: run,
    );

    // QA finding closed as no longer reproducible; the promoted feedback is
    // untouched and still awaits the reviewer.
    expect(rechecked.isNoLongerReproducible, isTrue);
    expect(rechecked.status, QaFindingStatus.promoted);
    expect(rechecked.feedbackId, feedback.id);
    final stillAddressed = await review.loadFeedback(feedback.id);
    expect(stillAddressed!.status, FeedbackStatus.addressed);
    expect(stillAddressed.status, isNot(FeedbackStatus.resolved));

    // --- Reviewer resolution (C.4 authority) ------------------------------
    final resolved = await review.resolveFeedback(
      actor: reviewer,
      feedbackId: feedback.id,
    );
    expect(resolved.status, FeedbackStatus.resolved);

    // --- No runtime mutation, no parallel QA state -------------------------
    final runtimeJsonAfter = json.encode({
      'directions': {
        for (final entry in runtime.directions.entries)
          entry.key: entry.value.patterns,
      },
      'direction_themes': runtime.directionThemes.keys.toList(),
      'resources': runtime.resources.keys.toList(),
    });
    expect(runtimeJsonAfter, bundleJsonBefore);
    expect(runtime.directions.keys.toSet(), directionsBefore);
    expect(runtime.directionThemes.keys.toSet(), themesBefore);
    expect(runtime.resources.keys.toSet(), resourcesBefore);
    expect(controller.state.feedbackIds, contains(feedback.id));
    expect(controller.state.toJson().keys, isNot(contains('qa_findings')));
    expect(await review.listApprovals(), isEmpty);
  });
}
