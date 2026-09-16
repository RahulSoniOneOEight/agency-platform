import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_repository.dart';
import 'package:prototype_app/review/review_state.dart';

ReviewState buildState({
  String clientId = 'prototype-demo',
  int reviewRound = 1,
  ReviewStatus status = ReviewStatus.inReview,
  String? selectedDirection,
  Map<String, String> screenSelections = const {},
  List<ReviewComment> comments = const [],
}) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: clientId,
    reviewRound: reviewRound,
    status: status,
    selectedDirection: selectedDirection,
    screenSelections: screenSelections,
    comments: comments,
  );
}

void main() {
  group('MemoryReviewRepository', () {
    test('save/load round-trips state by client id', () async {
      final ReviewRepository repository = MemoryReviewRepository();
      final state = buildState(
        selectedDirection: 'b',
        screenSelections: const {'search': 'b'},
        comments: const [
          ReviewComment(
            id: 'c1',
            scope: ReviewCommentScope.general,
            text: 'note',
          ),
        ],
      );

      await repository.save(state);

      expect(await repository.load('prototype-demo'), state);
    });

    test('load returns null for an unknown client', () async {
      final repository = MemoryReviewRepository();

      expect(await repository.load('missing'), isNull);
    });

    test('keeps distinct clients isolated', () async {
      final repository = MemoryReviewRepository();

      await repository.save(buildState(clientId: 'alpha', selectedDirection: 'a'));
      await repository.save(buildState(clientId: 'beta', selectedDirection: 'c'));

      expect((await repository.load('alpha'))!.selectedDirection, 'a');
      expect((await repository.load('beta'))!.selectedDirection, 'c');
    });

    test('saving a new state for a client replaces the previous one', () async {
      final repository = MemoryReviewRepository();

      await repository.save(buildState(selectedDirection: 'a'));
      await repository.save(buildState(selectedDirection: 'b'));

      expect((await repository.load('prototype-demo'))!.selectedDirection, 'b');
    });
  });
}
