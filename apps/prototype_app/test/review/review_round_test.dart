import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/prototype_direction.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_overview.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

PrototypeRuntime buildRoundRuntime() {
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

void main() {
  late PrototypeRuntime runtime;
  late MemoryReviewRepository repository;
  late ReviewController controller;

  setUp(() {
    runtime = buildRoundRuntime();
    repository = MemoryReviewRepository();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: repository,
    );
  });

  Future<void> pumpOverview(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewOverview(runtime: runtime, controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('advanceRound', () {
    test('increments deterministically and preserves selections and comments',
        () async {
      await controller.selectDirection('b');
      await controller.selectScreenDirection('commerce.search', 'c');
      await controller.addComment(
        const ReviewComment(
          id: 'review-1',
          scope: ReviewCommentScope.general,
          text: 'keep me',
        ),
      );

      expect(controller.state.reviewRound, 1);

      await controller.advanceRound();

      expect(controller.state.reviewRound, 2);
      expect(controller.state.selectedDirection, 'b');
      expect(controller.state.screenSelections, {
        'commerce.search': ReviewScreenDecision(direction: 'c'),
      });
      expect(controller.state.comments.single.text, 'keep me');
      expect(controller.state.status, ReviewStatus.inReview);
      expect((await repository.load('prototype-demo'))!.reviewRound, 2);

      await controller.advanceRound();
      expect(controller.state.reviewRound, 3);
    });

    testWidgets('the explicit advance action updates the round in the overview',
        (tester) async {
      await pumpOverview(tester);
      expect(find.text('Review round: 1'), findsOneWidget);

      await tester.tap(find.byKey(ReviewOverview.advanceRoundButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Advance review round?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Advance'));
      await tester.pumpAndSettle();

      expect(controller.state.reviewRound, 2);
      expect(find.text('Review round: 2'), findsOneWidget);
    });

    testWidgets('the advance action can be cancelled', (tester) async {
      await pumpOverview(tester);

      await tester.tap(find.byKey(ReviewOverview.advanceRoundButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(controller.state.reviewRound, 1);
      expect(find.text('Review round: 1'), findsOneWidget);
    });

    testWidgets('overview renders without overflow at phone width',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewOverview(runtime: runtime, controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('status control', () {
    testWidgets('sets each C.1 status through the controller', (tester) async {
      await pumpOverview(tester);
      expect(controller.state.status, ReviewStatus.inReview);

      for (final status in ReviewStatus.values) {
        await tester.tap(
          find.descendant(
            of: find.byKey(ReviewOverview.statusControlKey),
            matching: find.text(reviewStatusToWire(status)),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.state.status, status);
      }

      expect(
        (await repository.load('prototype-demo'))!.status,
        ReviewStatus.readyForFinalReview,
      );
    });

    testWidgets('offers exactly the three C.1 statuses', (tester) async {
      await pumpOverview(tester);

      final rendered = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(ReviewOverview.statusControlKey),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toSet();

      expect(
        rendered,
        equals(<String>{
          'in_review',
          'needs_revision',
          'ready_for_final_review',
        }),
      );
    });
  });

  test('advancing the round creates no approval artifact', () async {
    final patternsBefore = {
      for (final entry in runtime.directions.entries)
        entry.key: List<String>.of(entry.value.patterns),
    };
    final instancesBefore =
        Map<String, PrototypeDirection>.of(runtime.directions);

    await controller.advanceRound();

    final persisted = (await repository.load('prototype-demo'))!;
    expect(persisted.reviewRound, 2);
    expect(persisted.status, ReviewStatus.inReview);
    expect(persisted.comments, isEmpty);
    expect(persisted.screenSelections, isEmpty);

    // Only the canonical review-state keys exist: no approval artifact/field is
    // introduced by advancing a review round.
    expect(
      persisted.toJson().keys.toSet(),
      equals(<String>{
        'version',
        'client_id',
        'review_round',
        'status',
        'selected_direction',
        'screen_selections',
        'comments',
      }),
    );

    // Review rounds never mutate the read-only runtime bundle.
    for (final id in patternsBefore.keys) {
      expect(identical(runtime.directions[id], instancesBefore[id]), isTrue);
      expect(runtime.directions[id]!.patterns, equals(patternsBefore[id]));
    }
  });
}
