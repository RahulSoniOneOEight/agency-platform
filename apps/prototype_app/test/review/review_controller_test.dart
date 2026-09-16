import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_state.dart';

ReviewComment comment(String id, {String text = 'note', String? screen}) {
  return ReviewComment(
    id: id,
    scope: screen == null ? ReviewCommentScope.general : ReviewCommentScope.screen,
    text: text,
    screen: screen,
  );
}

ReviewState buildState({
  String clientId = 'prototype-demo',
  int reviewRound = 1,
  String? selectedDirection,
}) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: clientId,
    reviewRound: reviewRound,
    status: ReviewStatus.inReview,
    selectedDirection: selectedDirection,
    screenSelections: const {},
    comments: const [],
  );
}

void main() {
  late MemoryReviewRepository repository;
  late ReviewController controller;

  setUp(() {
    repository = MemoryReviewRepository();
    controller = ReviewController(clientId: 'prototype-demo', repository: repository);
  });

  group('initial state', () {
    test('starts with no selection, round 1, in review', () {
      expect(controller.clientId, 'prototype-demo');
      expect(controller.state.version, ReviewState.currentVersion);
      expect(controller.state.clientId, 'prototype-demo');
      expect(controller.state.selectedDirection, isNull);
      expect(controller.state.reviewRound, 1);
      expect(controller.state.status, ReviewStatus.inReview);
      expect(controller.state.screenSelections, isEmpty);
      expect(controller.state.comments, isEmpty);
    });
  });

  group('selectDirection', () {
    test('stores a direction verbatim and persists it', () async {
      await controller.selectDirection('b');

      expect(controller.state.selectedDirection, 'b');
      expect((await repository.load('prototype-demo'))!.selectedDirection, 'b');
    });

    test('clears the overall selection back to null', () async {
      await controller.selectDirection('b');
      await controller.selectDirection(null);

      expect(controller.state.selectedDirection, isNull);
      expect((await repository.load('prototype-demo'))!.selectedDirection, isNull);
    });
  });

  group('selectScreenDirection', () {
    test('adds one entry without clearing others and persists', () async {
      await controller.selectScreenDirection('home', 'a');
      await controller.selectScreenDirection('search', 'b');

      expect(controller.state.screenSelections, {'home': 'a', 'search': 'b'});
      expect(
        (await repository.load('prototype-demo'))!.screenSelections,
        {'home': 'a', 'search': 'b'},
      );
    });

    test('updates an existing entry in place', () async {
      await controller.selectScreenDirection('search', 'b');
      await controller.selectScreenDirection('search', 'c');

      expect(controller.state.screenSelections, {'search': 'c'});
    });
  });

  group('comments', () {
    test('addComment appends and persists', () async {
      await controller.addComment(comment('c1'));

      expect(controller.state.comments.map((c) => c.id), ['c1']);
      expect((await repository.load('prototype-demo'))!.comments, hasLength(1));
    });

    test('addComment rejects a duplicate id with StateError', () async {
      await controller.addComment(comment('c1'));

      expect(() => controller.addComment(comment('c1')), throwsStateError);
      expect(controller.state.comments, hasLength(1));
    });

    test('updateComment replaces the comment with the same id', () async {
      await controller.addComment(comment('c1', text: 'old'));
      await controller.updateComment(comment('c1', text: 'new'));

      expect(controller.state.comments.single.text, 'new');
      expect((await repository.load('prototype-demo'))!.comments.single.text, 'new');
    });

    test('updateComment throws StateError for an unknown id', () async {
      await controller.addComment(comment('c1'));

      expect(() => controller.updateComment(comment('missing')), throwsStateError);
    });
  });

  group('setStatus', () {
    test('sets the given status and persists', () async {
      await controller.setStatus(ReviewStatus.needsRevision);

      expect(controller.state.status, ReviewStatus.needsRevision);
      expect((await repository.load('prototype-demo'))!.status, ReviewStatus.needsRevision);
    });
  });

  group('advanceRound', () {
    test('increments by exactly one and preserves selections and comments', () async {
      await controller.selectDirection('b');
      await controller.selectScreenDirection('search', 'b');
      await controller.addComment(comment('c1'));

      await controller.advanceRound();

      expect(controller.state.reviewRound, 2);
      expect(controller.state.selectedDirection, 'b');
      expect(controller.state.screenSelections, {'search': 'b'});
      expect(controller.state.comments.map((c) => c.id), ['c1']);
      expect((await repository.load('prototype-demo'))!.reviewRound, 2);
    });

    test('never drops below one', () async {
      final low = ReviewController(
        clientId: 'prototype-demo',
        repository: repository,
        initialState: buildState(reviewRound: 0),
      );

      await low.advanceRound();

      expect(low.state.reviewRound, 1);
    });
  });

  group('load', () {
    test('restores persisted state when one exists', () async {
      await repository.save(buildState(reviewRound: 2, selectedDirection: 'c'));

      await controller.load();

      expect(controller.state.reviewRound, 2);
      expect(controller.state.selectedDirection, 'c');
    });

    test('keeps the initial state when nothing is persisted', () async {
      await controller.load();

      expect(controller.state.reviewRound, 1);
      expect(controller.state.selectedDirection, isNull);
    });
  });

  group('listeners', () {
    test('notifies after each successful mutation', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.selectDirection('b');
      await controller.selectScreenDirection('search', 'b');
      await controller.addComment(comment('c1'));
      await controller.updateComment(comment('c1', text: 'edited'));
      await controller.setStatus(ReviewStatus.needsRevision);
      await controller.advanceRound();

      expect(notifications, 6);
    });

    test('does not notify when a mutation is rejected', () async {
      await controller.addComment(comment('c1'));
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.addComment(comment('c1')),
        throwsStateError,
      );

      expect(notifications, 0);
    });

    test('rejected mutations neither persist nor notify', () async {
      await controller.addComment(comment('c1'));
      final persistedBefore = await repository.load('prototype-demo');
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.addComment(comment('c1', text: 'duplicate')),
        throwsStateError,
      );
      await expectLater(
        () => controller.updateComment(comment('missing', text: 'nope')),
        throwsStateError,
      );

      expect(notifications, 0);
      expect(await repository.load('prototype-demo'), persistedBefore);
      expect(controller.state.comments.single.text, 'note');
    });

    test('clearScreenDirection removes only that screen and persists', () async {
      await controller.selectScreenDirection('search', 'b');
      await controller.selectScreenDirection('home', 'a');

      await controller.clearScreenDirection('search');

      expect(controller.state.screenSelections.containsKey('search'), isFalse);
      expect(controller.state.screenSelections['home'], 'a');
      final persisted = await repository.load('prototype-demo');
      expect(persisted!.screenSelections.containsKey('search'), isFalse);
      expect(persisted.screenSelections['home'], 'a');

      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.clearScreenDirection('search');
      expect(notifications, 0);
    });

    test('load adopts a valid persisted state', () async {
      await repository.save(buildState(selectedDirection: 'b'));
      final validating = ReviewController(
        clientId: 'prototype-demo',
        repository: repository,
        validate: (state) => <String>[],
      );

      await validating.load();

      expect(validating.state.selectedDirection, 'b');
      expect(validating.loadErrors, isEmpty);
    });

    test('load never adopts invalid persisted state', () async {
      await repository.save(buildState(reviewRound: 0));
      final validating = ReviewController(
        clientId: 'prototype-demo',
        repository: repository,
        validate: (state) => state.reviewRound < 1
            ? <String>['invalid review round: ${state.reviewRound}']
            : <String>[],
      );

      await validating.load();

      expect(validating.state.reviewRound, 1);
      expect(validating.loadErrors, ['invalid review round: 0']);
    });
  });
}
