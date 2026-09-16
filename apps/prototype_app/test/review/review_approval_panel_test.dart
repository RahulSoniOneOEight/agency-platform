import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_approval_panel.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
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

VisualAttachment visualAttachment() {
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
  );
}

void main() {
  late PrototypeRuntime runtime;
  late ReviewController controller;
  late MemoryFeedbackRepository feedback;
  late MemoryApprovalRepository approvals;
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
    coordinator = ReviewCoordinator(
      controller: controller,
      feedbackRepository: feedback,
      approvalRepository: approvals,
    );
  });

  Future<FeedbackRecord> seed({
    required String id,
    bool blocking = false,
    VisualAttachment? attachment,
  }) {
    return coordinator.createFeedback(
      actor: reviewer,
      id: id,
      scope: attachment == null
          ? FeedbackScope.general
          : FeedbackScope.visualAnnotation,
      text: 'Seeded $id',
      target: attachment == null
          ? const FeedbackTarget()
          : const FeedbackTarget(screen: 'commerce.home'),
      blocking: blocking,
      visualAttachment: attachment,
    );
  }

  Future<void> pump(WidgetTester tester, ReviewActor actor) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewApprovalPanel(
            runtime: runtime,
            controller: controller,
            coordinator: coordinator,
            actor: actor,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('eligibility', () {
    testWidgets('shows exact blocking reasons and disables approval',
        (tester) async {
      await seed(id: 'feedback-block', blocking: true);

      await pump(tester, reviewer);

      expect(find.byKey(ReviewApprovalPanel.blockersKey), findsOneWidget);
      expect(find.byKey(ReviewApprovalPanel.eligibilityBannerKey), findsNothing);
      final create = tester.widget<FilledButton>(
        find.byKey(ReviewApprovalPanel.createButtonKey),
      );
      expect(create.onPressed, isNull);
    });

    testWidgets('is eligible once the round is ready with no blockers',
        (tester) async {
      await seed(id: 'feedback-nb', blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);
      expect(controller.state.status, ReviewStatus.readyForFinalReview);

      await pump(tester, reviewer);

      expect(find.byKey(ReviewApprovalPanel.eligibilityBannerKey), findsOneWidget);
      expect(find.text('Eligible for approval'), findsOneWidget);
      final create = tester.widget<FilledButton>(
        find.byKey(ReviewApprovalPanel.createButtonKey),
      );
      expect(create.onPressed, isNotNull);
    });
  });

  group('create approval', () {
    testWidgets('captures reviewer and approver identities, same person allowed',
        (tester) async {
      await seed(id: 'feedback-nb', blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);

      await pump(tester, reviewer);
      await tester.enterText(
        find.byKey(ReviewApprovalPanel.approverIdFieldKey),
        'reviewer-123',
      );
      await tester.enterText(
        find.byKey(ReviewApprovalPanel.approverNameFieldKey),
        'Rahul',
      );
      await tester.enterText(
        find.byKey(ReviewApprovalPanel.commitShaFieldKey),
        'abc123',
      );
      await tester.tap(find.byKey(ReviewApprovalPanel.createButtonKey));
      await tester.pumpAndSettle();

      final stored = await coordinator.listApprovals();
      expect(stored, hasLength(1));
      final snapshot = stored.single;
      expect(snapshot.version, 1);
      expect(snapshot.reviewedBy.id, 'reviewer-123');
      expect(snapshot.approvedBy.id, 'reviewer-123');
      expect(snapshot.reviewedBy.role, ReviewRole.reviewer);
      expect(snapshot.approvedBy.role, ReviewRole.approver);
      expect(snapshot.sourceCommitSha, 'abc123');
      expect(
        find.byKey(ReviewApprovalPanel.versionTileKey(1)),
        findsOneWidget,
      );
    });

    testWidgets('rejects missing identities without writing an approval',
        (tester) async {
      await seed(id: 'feedback-nb', blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);

      await pump(tester, reviewer);
      await tester.enterText(
        find.byKey(ReviewApprovalPanel.commitShaFieldKey),
        'abc123',
      );
      await tester.tap(find.byKey(ReviewApprovalPanel.createButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ReviewApprovalPanel.errorKey), findsOneWidget);
      expect(await coordinator.listApprovals(), isEmpty);
    });
  });

  group('approval history', () {
    testWidgets('renders existing versions read-only', (tester) async {
      await seed(id: 'feedback-nb', blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);
      await coordinator.createApproval(
        reviewer: reviewer,
        approver: const ReviewActor(
          id: 'approver-456',
          name: 'Priya',
          role: ReviewRole.approver,
        ),
        sourceCommitSha: 'abc123',
      );

      await pump(tester, reviewer);

      expect(find.byKey(ReviewApprovalPanel.versionTileKey(1)), findsOneWidget);
      expect(find.text('Approval v1'), findsOneWidget);
      expect(find.textContaining('approved_by approver-456'), findsOneWidget);
      // Read-only: no edit/delete controls on the immutable snapshot.
      expect(find.widgetWithText(TextButton, 'Delete'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
    });
  });

  group('carried-forward non-blocking feedback', () {
    testWidgets('shows unresolved non-blocking feedback', (tester) async {
      await seed(id: 'feedback-nb', blocking: false);
      await coordinator.closeCurrentRound(actor: reviewer);

      await pump(tester, reviewer);

      expect(
        find.byKey(ReviewApprovalPanel.unresolvedNonBlockingKey),
        findsOneWidget,
      );
      expect(find.textContaining('feedback-nb'), findsOneWidget);
    });
  });

  group('visual evidence', () {
    testWidgets('renders attachment context without lifecycle controls',
        (tester) async {
      await seed(id: 'feedback-visual', attachment: visualAttachment());

      await pump(tester, reviewer);

      expect(find.byKey(ReviewApprovalPanel.visualEvidenceKey), findsOneWidget);
      expect(
        find.byKey(ReviewApprovalPanel.visualEvidenceItemKey('feedback-visual')),
        findsOneWidget,
      );
      expect(find.textContaining('review-home-round-1'), findsOneWidget);
      expect(find.textContaining('bugdrop'), findsWidgets);
    });
  });
}
