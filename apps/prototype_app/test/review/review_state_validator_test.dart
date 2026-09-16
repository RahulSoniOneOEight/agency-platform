import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/review/review_state_validator.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

const Set<String> screenIds = {'home', 'search'};

PrototypeRuntime buildRuntime() => PrototypeRuntime.fromMap(canonicalBundle());

ReviewState validState({
  int version = ReviewState.currentVersion,
  String clientId = 'prototype-demo',
  int reviewRound = 1,
  ReviewStatus status = ReviewStatus.inReview,
  String? selectedDirection = 'a',
  Map<String, ReviewScreenDecision>? screenSelections,
  List<ReviewComment> comments = const [],
}) {
  return ReviewState(
    version: version,
    clientId: clientId,
    reviewRound: reviewRound,
    status: status,
    selectedDirection: selectedDirection,
    screenSelections: screenSelections ??
        {'home': ReviewScreenDecision(direction: 'b')},
    comments: comments,
  );
}

void main() {
  late PrototypeRuntime runtime;

  setUp(() {
    runtime = buildRuntime();
  });

  group('validateReviewState', () {
    test('returns no errors for a valid state', () {
      expect(
        validateReviewState(validState(), runtime, screenIds: screenIds),
        isEmpty,
      );
    });

    test('reports an unsupported version', () {
      expect(
        validateReviewState(validState(version: 3), runtime, screenIds: screenIds),
        contains('unsupported review state version: 3'),
      );
    });

    test('reports a client id mismatch', () {
      expect(
        validateReviewState(validState(clientId: 'other'), runtime, screenIds: screenIds),
        contains(
          'review state client other does not match runtime client prototype-demo',
        ),
      );
    });

    test('reports an invalid review round', () {
      expect(
        validateReviewState(validState(reviewRound: 0), runtime, screenIds: screenIds),
        contains('invalid review round: 0'),
      );
    });

    test('reports a selected direction missing from runtime directions', () {
      expect(
        validateReviewState(
          validState(selectedDirection: 'Z'),
          runtime,
          screenIds: screenIds,
        ),
        contains('selected direction Z is not present in runtime directions'),
      );
    });

    test('reports a screen mix direction missing from runtime directions', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'home': ReviewScreenDecision(direction: 'Z'),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains('screen home direction Z is not present in runtime directions'),
      );
    });

    test('reports a section direction missing from runtime directions', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'home': ReviewScreenDecision(
              direction: 'a',
              sections: const {'home.hero': 'Z'},
            ),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains('section home.hero direction Z is not present in runtime directions'),
      );
    });

    test('reports an unknown screen id from screen selections', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'unknown': ReviewScreenDecision(direction: 'a'),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains('unknown screen id: unknown'),
      );
    });

    test('skips further checks for an unknown screen id', () {
      final errors = validateReviewState(
        validState(screenSelections: {
          'unknown': ReviewScreenDecision(
            direction: 'Z',
            sections: const {'unknown.hero': 'Y'},
          ),
        }),
        runtime,
        screenIds: screenIds,
      );

      expect(errors, contains('unknown screen id: unknown'));
      expect(
        errors.where((error) => error.contains('unknown.hero')),
        isEmpty,
      );
    });

    test('reports an unknown screen id from a screen-scoped comment', () {
      expect(
        validateReviewState(
          validState(
            comments: const [
              ReviewComment(
                id: 'c1',
                scope: ReviewCommentScope.screen,
                screen: 'unknown',
                text: 'text',
              ),
            ],
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('unknown screen id: unknown'),
      );
    });

    test('reports duplicate comment ids', () {
      expect(
        validateReviewState(
          validState(
            comments: const [
              ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'one'),
              ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'two'),
            ],
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('duplicate comment id: c1'),
      );
    });

    test('reports a screen comment missing its screen', () {
      expect(
        validateReviewState(
          validState(
            comments: const [
              ReviewComment(
                id: 'c1',
                scope: ReviewCommentScope.screen,
                text: 'text',
              ),
            ],
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('screen comment c1 missing screen'),
      );
    });

    test('reports an invalid optional comment direction', () {
      expect(
        validateReviewState(
          validState(
            comments: const [
              ReviewComment(
                id: 'c1',
                scope: ReviewCommentScope.general,
                direction: 'Z',
                text: 'text',
              ),
            ],
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('comment c1 direction Z is not present in runtime directions'),
      );
    });

    test('reports a comment with empty text', () {
      expect(
        validateReviewState(
          validState(
            comments: const [
              ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: '   '),
            ],
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('comment c1 has empty text'),
      );
    });

    test('accepts a fully populated valid state', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'b',
            screenSelections: {
              'home': ReviewScreenDecision(
                direction: 'a',
                sections: const {'home.hero': 'b'},
              ),
              'search': ReviewScreenDecision(direction: 'b'),
            },
            comments: const [
              ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'general'),
              ReviewComment(
                id: 'c2',
                scope: ReviewCommentScope.screen,
                screen: 'home',
                direction: 'a',
                text: 'screen',
              ),
            ],
          ),
          runtime,
          screenIds: screenIds,
        ),
        isEmpty,
      );
    });

    test('returns a deterministic unique and sorted list for the plan example', () {
      final invalid = ReviewState(
        version: ReviewState.currentVersion,
        clientId: 'prototype-demo',
        reviewRound: 0,
        status: ReviewStatus.inReview,
        selectedDirection: 'Z',
        screenSelections: {
          'home': ReviewScreenDecision(direction: 'a'),
          'unknown': ReviewScreenDecision(direction: 'b'),
        },
        comments: const [
          ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'one'),
          ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'two'),
          ReviewComment(id: 'c2', scope: ReviewCommentScope.screen, text: 'missing screen'),
        ],
      );

      expect(
        validateReviewState(invalid, runtime, screenIds: {'home', 'search'}),
        equals([
          'duplicate comment id: c1',
          'invalid review round: 0',
          'screen comment c2 missing screen',
          'selected direction Z is not present in runtime directions',
          'unknown screen id: unknown',
        ]),
      );
    });

    test('deduplicates repeated findings', () {
      final state = validState(
        screenSelections: {
          'unknown': ReviewScreenDecision(direction: 'a'),
        },
        comments: const [
          ReviewComment(
            id: 'c1',
            scope: ReviewCommentScope.screen,
            screen: 'unknown',
            text: 'text',
          ),
        ],
      );

      final errors = validateReviewState(state, runtime, screenIds: screenIds);

      expect(errors.where((error) => error == 'unknown screen id: unknown'), hasLength(1));
      expect(errors, equals([...errors]..sort()));
    });

    test('does not mutate the runtime or the review state', () {
      final state = validState(
        reviewRound: 0,
        selectedDirection: 'Z',
        screenSelections: {
          'home': ReviewScreenDecision(direction: 'Z'),
          'unknown': ReviewScreenDecision(direction: 'b'),
        },
        comments: const [
          ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: '   '),
        ],
      );
      final directionsBefore = runtime.directions.keys.toList();
      final selectionsBefore =
          Map<String, ReviewScreenDecision>.from(state.screenSelections);
      final commentsBefore = List<ReviewComment>.from(state.comments);

      validateReviewState(state, runtime, screenIds: screenIds);

      expect(runtime.directions.keys.toList(), directionsBefore);
      expect(state.screenSelections, selectionsBefore);
      expect(state.comments, commentsBefore);
      expect(state.reviewRound, 0);
      expect(state.selectedDirection, 'Z');
    });
  });
}
