import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_screen_registry.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/review/review_state_validator.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Three directions with asymmetric exposure:
///   a = plp/pdp/search, product-card/price-display/search-field
///   b = search/trade-dashboard, search-field/credit-summary (no plp, no product-card)
///   c = plp/pdp, product-card/price-display (no search, no search-field)
PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.plp', 'commerce.pdp', 'commerce.search'],
        'b': ['commerce.search', 'commerce.trade-dashboard'],
        'c': ['commerce.plp', 'commerce.pdp'],
      },
      components: const {
        'a': [
          'commerce.product-card',
          'commerce.price-display',
          'commerce.search-field',
        ],
        'b': ['commerce.search-field', 'commerce.credit-summary'],
        'c': ['commerce.product-card', 'commerce.price-display'],
      },
    ),
  );
}

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
        {'commerce.plp': ReviewScreenDecision(direction: 'c')},
    comments: comments,
  );
}

void main() {
  late PrototypeRuntime runtime;
  late Set<String> screenIds;

  setUp(() {
    runtime = buildRuntime();
    screenIds = ReviewScreenRegistry.screenIdsFor(runtime);
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

    test('reports a screen direction missing from runtime directions', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'commerce.plp': ReviewScreenDecision(direction: 'Z'),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains(
          'screen commerce.plp direction Z is not present in runtime directions',
        ),
      );
    });

    test('reports a section source direction that is not mixable', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'commerce.plp': ReviewScreenDecision(
              direction: 'c',
              sections: const {'plp.product-grid': 'Z'},
            ),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains(
          'section plp.product-grid source Z is not mixable: Unknown direction',
        ),
      );
    });

    test('reports a redundant screen override', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'a',
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(direction: 'a'),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('redundant screen override: commerce.plp'),
      );
    });

    test('reports a redundant section override', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'a',
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(
                direction: 'c',
                sections: const {'plp.product-grid': 'c'},
              ),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('redundant section override: plp.product-grid'),
      );
    });

    test('reports an empty screen decision', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'commerce.plp': ReviewScreenDecision(),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains('empty screen decision: commerce.plp'),
      );
    });

    test('reports an unknown section id', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'commerce.plp': ReviewScreenDecision(
              direction: 'c',
              sections: const {'commerce.nope': 'a'},
            ),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains('unknown section id: commerce.nope'),
      );
    });

    test('reports a section that does not belong to the named screen', () {
      expect(
        validateReviewState(
          validState(screenSelections: {
            'commerce.plp': ReviewScreenDecision(
              direction: 'c',
              sections: const {'search.search-field': 'a'},
            ),
          }),
          runtime,
          screenIds: screenIds,
        ),
        contains(
          'section search.search-field does not belong to screen commerce.plp',
        ),
      );
    });

    test('reports a section with no effective screen direction', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: null,
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(
                sections: const {'plp.product-grid': 'a'},
              ),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('section plp.product-grid has no effective screen direction'),
      );
    });

    test('reports a source direction that does not expose the section', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'a',
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(
                direction: 'c',
                sections: const {'plp.product-grid': 'b'},
              ),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains(
          'section plp.product-grid source b is not mixable: Not present in Direction B',
        ),
      );
    });

    test('reports a section source unavailable from the source direction', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'a',
            screenSelections: {
              'commerce.search': ReviewScreenDecision(
                direction: 'a',
                sections: const {'search.search-field': 'c'},
              ),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains(
          'section search.search-field source c is not mixable: Not present in Direction C',
        ),
      );
    });

    test('reports a section source incompatible with the base screen layout', () {
      // Overall 'b' does not declare commerce.plp, so the inherited base cannot
      // host the plp section.
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'b',
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(
                sections: const {'plp.product-grid': 'a'},
              ),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains(
          'section plp.product-grid source a is not mixable: Not compatible with this screen layout',
        ),
      );
    });

    test('reports a screen direction that does not include the screen', () {
      expect(
        validateReviewState(
          validState(
            selectedDirection: 'a',
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(direction: 'b'),
            },
          ),
          runtime,
          screenIds: screenIds,
        ),
        contains('screen commerce.plp direction b does not include this screen'),
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
            selectedDirection: 'a',
            screenSelections: {
              'commerce.plp': ReviewScreenDecision(
                direction: 'c',
                sections: const {'plp.product-grid': 'a'},
              ),
              'commerce.search': ReviewScreenDecision(
                direction: 'b',
                sections: const {'search.search-field': 'a'},
              ),
            },
            comments: const [
              ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'general'),
              ReviewComment(
                id: 'c2',
                scope: ReviewCommentScope.screen,
                screen: 'commerce.plp',
                direction: 'c',
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
          'commerce.plp': ReviewScreenDecision(direction: 'a'),
          'unknown': ReviewScreenDecision(direction: 'b'),
        },
        comments: const [
          ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'one'),
          ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'two'),
          ReviewComment(id: 'c2', scope: ReviewCommentScope.screen, text: 'missing screen'),
        ],
      );

      expect(
        validateReviewState(invalid, runtime, screenIds: screenIds),
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
          'commerce.plp': ReviewScreenDecision(direction: 'Z'),
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
