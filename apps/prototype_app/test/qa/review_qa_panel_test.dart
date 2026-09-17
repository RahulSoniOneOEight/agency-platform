import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/memory_qa_finding_repository.dart';
import 'package:prototype_app/qa/qa_coordinator.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/qa/review_qa_panel.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';
import 'support/qa_fixtures.dart';

const reviewer = ReviewActor(
  id: 'reviewer-1',
  name: 'Reviewer',
  role: ReviewRole.reviewer,
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
    this.runtime = runtime;
  }

  late final PrototypeRuntime runtime;
  late final ReviewController controller;
  late final MemoryFeedbackRepository feedback;
  late final ReviewCoordinator review;
  late final MemoryQaFindingRepository findings;
  late final QaCoordinator qa;
}

Widget _wrap(_Harness h) => MaterialApp(
      home: Scaffold(
        body: ReviewQaPanel(
          runtime: h.runtime,
          coordinator: h.qa,
          actor: reviewer,
        ),
      ),
    );

void main() {
  testWidgets('renders an empty state without findings', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();
    expect(find.text('No QA findings.'), findsOneWidget);
  });

  testWidgets('renders structured findings with severity, category and rule',
      (tester) async {
    final h = _Harness();
    await h.qa.recordFinding(sampleQaFinding());
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();

    expect(find.textContaining('Product-card spacing'), findsOneWidget);
    expect(
      find.textContaining('major · spacing · detected · design_contract'),
      findsOneWidget,
    );
  });

  testWidgets('promote is only offered after triage', (tester) async {
    final h = _Harness();
    await h.qa.recordFinding(sampleQaFinding());
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();

    expect(find.text('Promote'), findsNothing);
    expect(find.text('Triage'), findsOneWidget);

    await tester.tap(find.text('Triage'));
    await tester.pumpAndSettle();

    expect(find.text('Promote'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Accept risk'), findsOneWidget);
  });

  testWidgets('promote creates reviewer feedback with the origin finding id',
      (tester) async {
    final h = _Harness();
    await h.qa.recordFinding(sampleQaFinding());
    await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Promote'));
    await tester.pumpAndSettle();

    final records = await h.review.allFeedback();
    expect(records, hasLength(1));
    expect(records.single.originQaFindingId, 'qa-001');
    expect(find.textContaining('Promoted → feedback-qa-001'), findsOneWidget);
  });

  testWidgets('dismissal requires an explicit reason', (tester) async {
    final h = _Harness();
    await h.qa.recordFinding(sampleQaFinding());
    await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss finding'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not reproducible');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final finding = await h.findings.load('prototype-demo', 'qa-001');
    expect(finding!.status, QaFindingStatus.dismissed);
  });

  testWidgets('accept risk records a reason', (tester) async {
    final h = _Harness();
    await h.qa.recordFinding(sampleQaFinding());
    await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accept risk'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'approved dense layout');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final finding = await h.findings.load('prototype-demo', 'qa-001');
    expect(finding!.status, QaFindingStatus.acceptedRisk);
  });

  testWidgets('the panel exposes no review, approval, or baseline authority',
      (tester) async {
    final h = _Harness();
    await h.qa.recordFinding(sampleQaFinding());
    await h.qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    await h.qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
    await tester.pumpWidget(_wrap(h));
    await tester.pumpAndSettle();

    for (final forbidden in const [
      'Resolve',
      'Reopen',
      'Blocking',
      'Approve',
      'Update baseline',
      'Accept baseline',
    ]) {
      expect(find.text(forbidden), findsNothing,
          reason: 'QA triage must not expose $forbidden');
    }
  });
}
