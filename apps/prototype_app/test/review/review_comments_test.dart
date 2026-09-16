import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_comments.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_screen_registry.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Reference runtime with three directions and four governed screens so the
/// comment forms have real screen and direction options to choose from.
PrototypeRuntime buildCommentsRuntime() {
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
    runtime = buildCommentsRuntime();
    repository = MemoryReviewRepository();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: repository,
    );
  });

  Future<void> pumpComments(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewComments(runtime: runtime, controller: controller),
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

  Future<void> addGeneral(WidgetTester tester, String text) async {
    await tester.enterText(
        find.byKey(ReviewComments.generalTextFieldKey), text);
    await tester.tap(find.byKey(ReviewComments.addGeneralButtonKey));
    await tester.pumpAndSettle();
  }

  Future<void> addScreen(
    WidgetTester tester, {
    required String screenId,
    required String text,
  }) async {
    await chooseDropdown(
      tester,
      ReviewComments.screenFieldKey,
      ReviewScreenRegistry.labelFor(screenId),
    );
    await tester.enterText(find.byKey(ReviewComments.screenTextFieldKey), text);
    await tester.tap(find.byKey(ReviewComments.addScreenButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('adds a general comment, persists it and displays it',
      (tester) async {
    await pumpComments(tester);

    await addGeneral(tester, 'Prefer the quieter visual hierarchy');

    expect(controller.state.comments, hasLength(1));
    final comment = controller.state.comments.single;
    expect(comment.scope, ReviewCommentScope.general);
    expect(comment.text, 'Prefer the quieter visual hierarchy');
    expect(comment.screen, isNull);
    expect(comment.direction, isNull);
    expect(find.text('Prefer the quieter visual hierarchy'), findsOneWidget);

    final persisted = await repository.load('prototype-demo');
    expect(persisted, isNotNull);
    expect(
        persisted!.comments.single.text, 'Prefer the quieter visual hierarchy');
  });

  testWidgets('adds a screen comment with a governed screen and persists it',
      (tester) async {
    await pumpComments(tester);

    await addScreen(
      tester,
      screenId: 'commerce.home',
      text: 'Reduce hero height',
    );

    expect(controller.state.comments, hasLength(1));
    final comment = controller.state.comments.single;
    expect(comment.scope, ReviewCommentScope.screen);
    expect(comment.screen, 'commerce.home');
    expect(comment.text, 'Reduce hero height');
    expect(find.text('Reduce hero height'), findsOneWidget);

    final persisted = await repository.load('prototype-demo');
    expect(persisted!.comments.single.screen, 'commerce.home');
  });

  testWidgets('records an optional direction on either scope', (tester) async {
    await pumpComments(tester);

    await chooseDropdown(tester, ReviewComments.generalDirectionFieldKey, 'B');
    await addGeneral(tester, 'Prefer B navigation');

    await chooseDropdown(tester, ReviewComments.screenDirectionFieldKey, 'C');
    await addScreen(
      tester,
      screenId: 'commerce.search',
      text: 'Search experience from C',
    );

    expect(controller.state.comments, hasLength(2));
    expect(controller.state.comments[0].direction, 'b');
    expect(controller.state.comments[1].direction, 'c');
    expect(controller.state.comments[1].screen, 'commerce.search');
  });

  testWidgets('rejects blank general text at the UI boundary', (tester) async {
    await pumpComments(tester);

    await tester.tap(find.byKey(ReviewComments.addGeneralButtonKey));
    await tester.pumpAndSettle();
    expect(controller.state.comments, isEmpty);

    await addGeneral(tester, '   ');

    expect(controller.state.comments, isEmpty);
    expect(await repository.load('prototype-demo'), isNull);
  });

  testWidgets('cannot save a screen comment without a screen selection',
      (tester) async {
    await pumpComments(tester);

    await tester.enterText(
      find.byKey(ReviewComments.screenTextFieldKey),
      'Needs a governed screen',
    );
    await tester.tap(find.byKey(ReviewComments.addScreenButtonKey));
    await tester.pumpAndSettle();

    expect(controller.state.comments, isEmpty);
    expect(await repository.load('prototype-demo'), isNull);
  });

  testWidgets('generates unique ids that avoid existing review ids',
      (tester) async {
    await controller.addComment(
      const ReviewComment(
        id: 'review-2',
        scope: ReviewCommentScope.general,
        text: 'existing',
      ),
    );
    await pumpComments(tester);

    for (final text in const ['first', 'second', 'third']) {
      await addGeneral(tester, text);
    }

    final ids = controller.state.comments.map((comment) => comment.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids,
        containsAll(<String>['review-2', 'review-1', 'review-3', 'review-4']));
    expect(ReviewComments.nextCommentId(const <ReviewComment>[]), 'review-1');
  });

  testWidgets('displays existing general and screen comments', (tester) async {
    await controller.addComment(
      const ReviewComment(
        id: 'review-1',
        scope: ReviewCommentScope.general,
        text: 'General note',
      ),
    );
    await controller.addComment(
      const ReviewComment(
        id: 'review-2',
        scope: ReviewCommentScope.screen,
        screen: 'commerce.home',
        direction: 'a',
        text: 'Screen note',
      ),
    );

    await pumpComments(tester);

    expect(find.text('General note'), findsOneWidget);
    expect(find.text('Screen note'), findsOneWidget);
    expect(find.text('Comment count: 2'), findsOneWidget);
  });
}
