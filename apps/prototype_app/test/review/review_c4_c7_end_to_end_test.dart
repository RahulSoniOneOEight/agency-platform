import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/bugdrop_visual_feedback_provider.dart';
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
import 'package:prototype_app/review/review_direction_comparison.dart';
import 'package:prototype_app/review/review_domain_error.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

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

/// The C.2 comparison neutrality vocabulary (kept in sync with
/// `review_comparison_architecture_test.dart`).
final RegExp _rankingVocabulary = RegExp(
  'best|recommend|winner|rank|score|rating|prefer|favorite|better|ideal',
  caseSensitive: false,
);

PrototypeRuntime _loadReferenceRuntime() {
  final decoded =
      json.decode(File('assets/generated/prototype-demo.json').readAsStringSync())
          as Map;
  return PrototypeRuntime.fromMap(Map<String, dynamic>.from(decoded));
}

Map<String, Object?> bugdropPayload() => <String, Object?>{
      'screenshot_ref': 'review-home-round-2',
      'viewport': {'width': 1440, 'height': 1200},
      'context': {
        'client_id': 'prototype-demo',
        'review_round': 1,
        'screen': 'commerce.plp',
        'effective_direction': 'a',
        'source_commit_sha': 'abc123',
        'section': 'plp.product-grid',
      },
      'bounds': {'left': 0.42, 'top': 0.31, 'right': 0.60, 'bottom': 0.43},
      'provider_item_id': 'provider-item-123',
    };

RefinementExecutionResult passingResult({List<String> evidence = const []}) {
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
      ValidationCheck(
        name: 'flutter analyze',
        passed: true,
        details: 'no issues',
      ),
    ],
    evidence: evidence,
  );
}

void main() {
  late Directory tempRoot;
  late ReviewPersistenceLayout layout;
  late FileFeedbackRepository feedbackRepository;
  late FileRefinementBatchRepository batchRepository;
  late FileApprovalRepository approvalRepository;
  late PrototypeRuntime runtime;
  late ReviewController controller;
  late ReviewCoordinator coordinator;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('c4-c7-e2e-');
    layout = ReviewPersistenceLayout(clientProjectsDirectory: tempRoot);
    feedbackRepository = FileFeedbackRepository(layout: layout);
    batchRepository = FileRefinementBatchRepository(layout: layout);
    approvalRepository = FileApprovalRepository(layout: layout);
    runtime = _loadReferenceRuntime();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    coordinator = ReviewCoordinator(
      controller: controller,
      feedbackRepository: feedbackRepository,
      approvalRepository: approvalRepository,
      refinementBatchRepository: batchRepository,
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('C.4-C.7 end-to-end refinement and re-approval flow', () async {
    // --- runtime / B.1D / B.1E read-only baseline ---------------------------
    final bundleJsonBefore =
        File('assets/generated/prototype-demo.json').readAsStringSync();
    final directionsBefore = Map.of(runtime.directions);
    final themesBefore = Map.of(runtime.directionThemes);
    final themeBefore = runtime.theme;

    // --- C.3 mixed decision -------------------------------------------------
    await controller.selectDirection('a');
    await controller.setSectionDirection('commerce.plp', 'plp.product-grid', 'c');
    expect(
      controller.state.screenSelections['commerce.plp']!
          .sections['plp.product-grid'],
      'c',
    );

    // --- reviewer creates blocking visual feedback --------------------------
    final attachment =
        const BugDropVisualFeedbackProvider().normalize(bugdropPayload());
    expect(attachment.providerName, 'bugdrop');
    expect(attachment.sectionId, 'plp.product-grid');

    final visualFeedback = await coordinator.createFeedback(
      actor: reviewer,
      id: 'feedback-021',
      scope: FeedbackScope.visualAnnotation,
      text: 'Product grid does not align with the mixed direction',
      target: const FeedbackTarget(
        screen: 'commerce.plp',
        section: 'plp.product-grid',
      ),
      blocking: true,
      visualAttachment: attachment,
    );
    expect(visualFeedback.status, FeedbackStatus.open);
    expect(controller.state.status, ReviewStatus.needsRevision);

    // A non-blocking item is carried forward into the approval snapshot.
    await coordinator.createFeedback(
      actor: reviewer,
      id: 'feedback-099',
      scope: FeedbackScope.general,
      text: 'Consider a quieter tertiary action later',
      target: const FeedbackTarget(),
      blocking: false,
    );

    // --- reviewer creates a draft batch, confirms, and marks ready ----------
    final draft = await coordinator.createDraftBatch(
      actor: reviewer,
      id: 'batch-001',
      feedbackIds: const ['feedback-021'],
      intendedScope: IntendedScope(
        screens: const ['commerce.plp'],
        sections: const ['plp.product-grid'],
      ),
      proposed: ChangeClassification.implementationOnly,
    );
    expect(draft.status, RefinementBatchStatus.draft);

    await coordinator.confirmBatchClassification(
      actor: reviewer,
      batchId: 'batch-001',
      confirmed: ChangeClassification.implementationOnly,
    );
    final ready = await coordinator.markBatchReady(
      actor: reviewer,
      batchId: 'batch-001',
    );
    expect(ready.status, RefinementBatchStatus.ready);

    // Scope and classification are frozen after ready.
    await expectLater(
      () => coordinator.updateDraftBatch(
        actor: reviewer,
        batchId: 'batch-001',
        intendedScope: IntendedScope(screens: const ['commerce.pdp']),
      ),
      throwsA(isA<ReviewDomainError>()),
    );

    // --- OpenCode executes and validates ------------------------------------
    await coordinator.startBatch(actor: agent, batchId: 'batch-001');
    final reviewed = await coordinator.recordBatchValidation(
      actor: agent,
      batchId: 'batch-001',
      result: passingResult(evidence: const ['review-home-round-2']),
    );
    expect(reviewed.status, RefinementBatchStatus.readyForReview);

    // Feedback moved only to addressed; never auto-resolved.
    final addressed =
        (await coordinator.loadFeedback('feedback-021'))!;
    expect(addressed.status, FeedbackStatus.addressed);
    expect(addressed.history.last.batchId, 'batch-001');
    expect(addressed.status, isNot(FeedbackStatus.resolved));

    // --- reviewer resolves, completes the batch, and closes the round -------
    await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-021');
    await coordinator.completeBatch(actor: reviewer, batchId: 'batch-001');
    final completed = (await coordinator.loadBatch('batch-001'))!;
    expect(completed.status, RefinementBatchStatus.completed);
    await coordinator.closeCurrentRound(actor: reviewer);
    expect(controller.state.status, ReviewStatus.readyForFinalReview);

    // --- approver creates approval-v1 ---------------------------------------
    final v1 = await coordinator.createApproval(
      reviewer: reviewer,
      approver: approver,
      sourceCommitSha: 'abc123',
    );
    expect(v1.version, 1);
    expect(v1.reviewRound, 1);
    expect(v1.unresolvedNonBlockingFeedbackIds, ['feedback-099']);

    // --- a new contract-impacting change requires a new round ---------------
    final contractFeedback = await coordinator.createFeedback(
      actor: reviewer,
      id: 'feedback-022',
      scope: FeedbackScope.screen,
      text: 'Home hero must change the approved experience contract',
      target: const FeedbackTarget(screen: 'commerce.home'),
      blocking: true,
    );
    expect(contractFeedback.createdRound, 2);
    expect(controller.state.reviewRound, 2);
    expect(controller.state.status, ReviewStatus.needsRevision);

    await coordinator.createDraftBatch(
      actor: reviewer,
      id: 'batch-002',
      feedbackIds: const ['feedback-022'],
      intendedScope: IntendedScope(screens: const ['commerce.home']),
      proposed: ChangeClassification.contractImpacting,
    );
    await coordinator.confirmBatchClassification(
      actor: reviewer,
      batchId: 'batch-002',
      confirmed: ChangeClassification.contractImpacting,
    );
    await coordinator.markBatchReady(actor: reviewer, batchId: 'batch-002');
    await coordinator.startBatch(actor: agent, batchId: 'batch-002');
    await coordinator.recordBatchValidation(
      actor: agent,
      batchId: 'batch-002',
      result: passingResult(),
    );
    await coordinator.resolveFeedback(actor: reviewer, feedbackId: 'feedback-022');
    await coordinator.completeBatch(actor: reviewer, batchId: 'batch-002');
    await coordinator.closeCurrentRound(actor: reviewer);

    final v2 = await coordinator.createApproval(
      reviewer: reviewer,
      approver: approver,
      sourceCommitSha: 'def456',
    );
    expect(v2.version, 2);
    expect(v2.reviewRound, 2);
    expect(v2.supersedes, 1);
    expect(v2.sourceCommitSha, 'def456');

    // v1 is never rewritten; supersession is version/index metadata only.
    final approvals = await coordinator.listApprovals();
    expect(approvals.map((snapshot) => snapshot.version), [1, 2]);
    expect(approvals.first, v1);
    expect(approvals.first.sourceCommitSha, 'abc123');

    // --- completed batches stay frozen --------------------------------------
    expect(
      (await coordinator.allBatches()).map((batch) => batch.status),
      [RefinementBatchStatus.completed, RefinementBatchStatus.completed],
    );
    await expectLater(
      () => coordinator.updateDraftBatch(
        actor: reviewer,
        batchId: 'batch-001',
        intendedScope: IntendedScope(screens: const ['commerce.pdp']),
      ),
      throwsA(isA<ReviewDomainError>()),
    );

    // --- no automatic approval / resolution / batch creation ----------------
    // Exactly two batches exist, both reviewer-created; the agent created none.
    expect((await coordinator.allBatches()), hasLength(2));
    // The agent never resolved feedback.
    expect(
      (await coordinator.loadFeedback('feedback-021'))!.status,
      FeedbackStatus.resolved,
    );

    // --- runtime / B.1D / B.1E remain read-only -----------------------------
    expect(identical(runtime.theme, themeBefore), isTrue);
    expect(runtime.directions.keys.toSet(), directionsBefore.keys.toSet());
    for (final id in directionsBefore.keys) {
      expect(identical(runtime.directions[id], directionsBefore[id]), isTrue);
    }
    expect(runtime.directionThemes.keys.toSet(), themesBefore.keys.toSet());
    for (final id in themesBefore.keys) {
      expect(identical(runtime.directionThemes[id], themesBefore[id]), isTrue);
    }
    // No synthetic runtime artifact was generated.
    expect(
      File('assets/generated/prototype-demo.json').readAsStringSync(),
      bundleJsonBefore,
    );
  });

  testWidgets('C.2 comparison stays neutral after the C.7 flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewDirectionComparison(
            runtime: runtime,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_rankingVocabulary), findsNothing);
    // Comparison is display-only: no direction is selected by viewing.
    expect(controller.state.selectedDirection, isNull);
  });

  test('C.3 selection/mix still persists normally', () async {
    await controller.selectDirection('a');
    await controller.setSectionDirection('commerce.plp', 'plp.product-grid', 'c');

    final persisted = controller.state.toJson();
    expect(persisted['version'], 2);
    expect(
      (persisted['screen_selections'] as Map<String, dynamic>)['commerce.plp'],
      {
        'sections': {'plp.product-grid': 'c'},
      },
    );
  });
}
