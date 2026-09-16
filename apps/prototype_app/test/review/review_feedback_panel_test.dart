import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_feedback_panel.dart';
import 'package:prototype_app/review/review_screen_registry.dart';
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

PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      names: const {
        'a': 'Alpha Direction',
        'b': 'Beta Direction',
        'c': 'Gamma Direction',
      },
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
    ),
  );
}

Map<String, Object?> bugdropPayload() {
  return {
    'screenshot_ref': 'review-home-round-1',
    'viewport': {'width': 1440, 'height': 1200},
    'context': {
      'client_id': 'prototype-demo',
      'review_round': 1,
      'screen': 'commerce.home',
      'effective_direction': 'a',
      'source_commit_sha': 'abc123',
    },
    'bounds': {'left': 0.4, 'top': 0.3, 'right': 0.6, 'bottom': 0.4},
    'provider_item_id': 'provider-item-1',
  };
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
      approvalRepository: MemoryApprovalRepository(),
      refinementBatchRepository: MemoryRefinementBatchRepository(),
    );
  });

  Future<FeedbackRecord> seed({
    required String id,
    bool blocking = false,
    String text = 'Seeded feedback',
    FeedbackScope scope = FeedbackScope.general,
    FeedbackTarget target = const FeedbackTarget(),
  }) {
    return coordinator.createFeedback(
      actor: reviewer,
      id: id,
      scope: scope,
      text: text,
      target: target,
      blocking: blocking,
    );
  }

  Future<void> pump(WidgetTester tester, ReviewActor actor) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReviewFeedbackPanel(
              runtime: runtime,
              controller: controller,
              coordinator: coordinator,
              actor: actor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseDropdown(
    WidgetTester tester,
    Key fieldKey,
    String optionText,
  ) async {
    await tester.tap(find.byKey(fieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionText).last);
    await tester.pumpAndSettle();
  }

  group('create feedback', () {
    testWidgets('a reviewer can create blocking feedback by default',
        (tester) async {
      await pump(tester, reviewer);

      await tester.enterText(
        find.byKey(ReviewFeedbackPanel.textFieldKey),
        'Increase spacing',
      );
      await tester.tap(find.byKey(ReviewFeedbackPanel.createButtonKey));
      await tester.pumpAndSettle();

      final records = await coordinator.allFeedback();
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.text, 'Increase spacing');
      expect(record.blocking, isTrue);
      expect(controller.state.feedbackIds, [record.id]);
      expect(find.byKey(ReviewFeedbackPanel.tileKey(record.id)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ReviewFeedbackPanel.statusChipKey(record.id)),
          matching: find.text('open'),
        ),
        findsOneWidget,
      );
      expect(find.text('Blocking'), findsWidgets);
    });

    testWidgets('rejects blank feedback at the UI boundary', (tester) async {
      await pump(tester, reviewer);

      await tester.tap(find.byKey(ReviewFeedbackPanel.createButtonKey));
      await tester.pumpAndSettle();

      expect(await coordinator.allFeedback(), isEmpty);
      expect(find.byKey(ReviewFeedbackPanel.errorKey), findsOneWidget);
    });

    testWidgets('creates section-scoped feedback with a governed target',
        (tester) async {
      await pump(tester, reviewer);

      await chooseDropdown(tester, ReviewFeedbackPanel.scopeFieldKey, 'section');
      await chooseDropdown(
        tester,
        ReviewFeedbackPanel.screenFieldKey,
        ReviewScreenRegistry.labelFor('commerce.home'),
      );
      await chooseDropdown(tester, ReviewFeedbackPanel.sectionFieldKey, 'Product grid');
      await tester.enterText(
        find.byKey(ReviewFeedbackPanel.textFieldKey),
        'Tighten the grid',
      );
      await tester.tap(find.byKey(ReviewFeedbackPanel.createButtonKey));
      await tester.pumpAndSettle();

      final record = (await coordinator.allFeedback()).single;
      expect(record.scope, FeedbackScope.section);
      expect(record.target.screen, 'commerce.home');
      expect(record.target.section, 'home.product-grid');
    });
  });

  group('reviewer authority', () {
    testWidgets('non-reviewers get a read-only panel', (tester) async {
      await seed(id: 'feedback-1', blocking: true);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      await pump(tester, agent);

      expect(find.byKey(ReviewFeedbackPanel.createButtonKey), findsNothing);
      expect(
        find.byKey(ReviewFeedbackPanel.resolveButtonKey('feedback-1')),
        findsNothing,
      );
      expect(
        find.byKey(ReviewFeedbackPanel.blockingToggleKey('feedback-1')),
        findsNothing,
      );
      expect(find.byKey(ReviewFeedbackPanel.closeRoundButtonKey), findsNothing);
      expect(find.byKey(ReviewFeedbackPanel.tileKey('feedback-1')), findsOneWidget);
    });

    testWidgets('a reviewer can resolve addressed feedback and reopen it',
        (tester) async {
      await seed(id: 'feedback-1', blocking: true);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      await pump(tester, reviewer);
      await tester.tap(find.byKey(ReviewFeedbackPanel.resolveButtonKey('feedback-1')));
      await tester.pumpAndSettle();

      expect(
        (await coordinator.loadFeedback('feedback-1'))!.status,
        FeedbackStatus.resolved,
      );
      expect(
        find.descendant(
          of: find.byKey(ReviewFeedbackPanel.statusChipKey('feedback-1')),
          matching: find.text('resolved'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ReviewFeedbackPanel.reopenButtonKey('feedback-1')));
      await tester.pumpAndSettle();

      expect(
        (await coordinator.loadFeedback('feedback-1'))!.status,
        FeedbackStatus.open,
      );
    });

    testWidgets('a reviewer can reopen an addressed item directly',
        (tester) async {
      await seed(id: 'feedback-1', blocking: true);
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-1');

      await pump(tester, reviewer);

      expect(
        find.byKey(ReviewFeedbackPanel.reopenButtonKey('feedback-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ReviewFeedbackPanel.reopenButtonKey('feedback-1')));
      await tester.pumpAndSettle();

      expect(
        (await coordinator.loadFeedback('feedback-1'))!.status,
        FeedbackStatus.open,
      );
    });

    testWidgets('a reviewer can toggle blocking classification', (tester) async {
      await seed(id: 'feedback-1', blocking: false);
      await pump(tester, reviewer);

      await tester.tap(find.byKey(ReviewFeedbackPanel.blockingToggleKey('feedback-1')));
      await tester.pumpAndSettle();

      expect((await coordinator.loadFeedback('feedback-1'))!.blocking, isTrue);
    });
  });

  group('status chips', () {
    testWidgets('show open, addressed and resolved states', (tester) async {
      await seed(id: 'feedback-open');
      await seed(id: 'feedback-addressed');
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-addressed');
      await seed(id: 'feedback-resolved');
      await coordinator.markAddressed(actor: agent, feedbackId: 'feedback-resolved');
      await coordinator.resolveFeedback(
        actor: reviewer,
        feedbackId: 'feedback-resolved',
      );

      await pump(tester, reviewer);

      for (final entry in {
        'feedback-open': 'open',
        'feedback-addressed': 'addressed',
        'feedback-resolved': 'resolved',
      }.entries) {
        expect(
          find.descendant(
            of: find.byKey(ReviewFeedbackPanel.statusChipKey(entry.key)),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
          reason: 'missing ${entry.value} chip for ${entry.key}',
        );
      }
    });
  });

  group('round eligibility and close', () {
    testWidgets('an unresolved blocker hides eligibility and disables close',
        (tester) async {
      await seed(id: 'feedback-1', blocking: true);

      await pump(tester, reviewer);

      expect(find.byKey(ReviewFeedbackPanel.eligibilityBannerKey), findsNothing);
      final close = tester.widget<FilledButton>(
        find.byKey(ReviewFeedbackPanel.closeRoundButtonKey),
      );
      expect(close.onPressed, isNull);
    });

    testWidgets('non-blocking open feedback makes the round eligible to close',
        (tester) async {
      await seed(id: 'feedback-1', blocking: false);

      await pump(tester, reviewer);

      expect(find.byKey(ReviewFeedbackPanel.eligibilityBannerKey), findsOneWidget);
      expect(find.text('Eligible to close round'), findsOneWidget);
      final close = tester.widget<FilledButton>(
        find.byKey(ReviewFeedbackPanel.closeRoundButtonKey),
      );
      expect(close.onPressed, isNotNull);
    });

    testWidgets('closing the round sets ready_for_final_review', (tester) async {
      await seed(id: 'feedback-1', blocking: false);

      await pump(tester, reviewer);
      await tester.tap(find.byKey(ReviewFeedbackPanel.closeRoundButtonKey));
      await tester.pumpAndSettle();

      expect(controller.state.status, ReviewStatus.readyForFinalReview);
    });
  });

  group('prior-round history', () {
    testWidgets('shows feedback from every round', (tester) async {
      await seed(id: 'feedback-1', text: 'Round one note');
      await coordinator.startNextRound(actor: reviewer);
      await seed(id: 'feedback-2', text: 'Round two note');

      await pump(tester, reviewer);

      expect(find.byKey(ReviewFeedbackPanel.roundSectionKey(1)), findsOneWidget);
      expect(find.byKey(ReviewFeedbackPanel.roundSectionKey(2)), findsOneWidget);
      expect(find.text('Round one note'), findsOneWidget);
      expect(find.text('Round two note'), findsOneWidget);
    });
  });

  group('visual feedback entry', () {
    testWidgets('accepts a normalized provider payload and shows evidence',
        (tester) async {
      await pump(tester, reviewer);

      await chooseDropdown(
        tester,
        ReviewFeedbackPanel.scopeFieldKey,
        'visual_annotation',
      );
      await tester.enterText(
        find.byKey(ReviewFeedbackPanel.visualPayloadFieldKey),
        jsonEncode(bugdropPayload()),
      );
      await tester.enterText(
        find.byKey(ReviewFeedbackPanel.textFieldKey),
        'Align the price block',
      );
      await tester.tap(find.byKey(ReviewFeedbackPanel.createButtonKey));
      await tester.pumpAndSettle();

      final record = (await coordinator.allFeedback()).single;
      expect(record.scope, FeedbackScope.visualAnnotation);
      expect(record.visualAttachment, isNotNull);
      expect(record.visualAttachment!.providerName, 'bugdrop');
      expect(record.visualAttachment!.screenshotRef, 'review-home-round-1');
      expect(
        find.byKey(ReviewFeedbackPanel.attachmentKey(record.id)),
        findsOneWidget,
      );
      expect(find.textContaining('review-home-round-1'), findsOneWidget);
      // Provider evidence never drives readiness; the reviewer/round flow does.
      expect(controller.state.status, isNot(ReviewStatus.readyForFinalReview));
    });

    testWidgets('rejects a malformed provider payload without writing feedback',
        (tester) async {
      await pump(tester, reviewer);

      await chooseDropdown(
        tester,
        ReviewFeedbackPanel.scopeFieldKey,
        'visual_annotation',
      );
      await tester.enterText(
        find.byKey(ReviewFeedbackPanel.visualPayloadFieldKey),
        '{not json',
      );
      await tester.enterText(
        find.byKey(ReviewFeedbackPanel.textFieldKey),
        'Broken evidence',
      );
      await tester.tap(find.byKey(ReviewFeedbackPanel.createButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ReviewFeedbackPanel.errorKey), findsOneWidget);
      expect(await coordinator.allFeedback(), isEmpty);
    });
  });
}
