import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_decision_normalizer.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
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

ReviewState buildState({
  String? selectedDirection = 'a',
  Map<String, ReviewScreenDecision> screenSelections = const {},
  List<ReviewComment> comments = const [],
  int reviewRound = 1,
  ReviewStatus status = ReviewStatus.inReview,
}) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: 'prototype-demo',
    reviewRound: reviewRound,
    status: status,
    selectedDirection: selectedDirection,
    screenSelections: screenSelections,
    comments: comments,
  );
}

void main() {
  late PrototypeRuntime runtime;

  setUp(() {
    runtime = buildRuntime();
  });

  group('effective direction resolution', () {
    test('resolves overrides and inheritance for screens and sections', () {
      final state = buildState(
        selectedDirection: 'a',
        screenSelections: {
          'commerce.plp': ReviewScreenDecision(
            direction: 'c',
            sections: const {'plp.product-grid': 'a'},
          ),
        },
      );

      expect(effectiveScreenDirection(state, 'commerce.plp'), 'c');
      expect(effectiveScreenDirection(state, 'commerce.pdp'), 'a');
      expect(
        effectiveSectionDirection(state, 'commerce.plp', 'plp.product-grid'),
        'a',
      );
      expect(effectiveSectionDirection(state, 'commerce.plp', 'pdp.price'), 'c');
      expect(effectiveSectionDirection(state, 'commerce.pdp', 'pdp.price'), 'a');
    });
  });

  group('normalizeReviewDecisions', () {
    test('removes redundant screen/section overrides and empty screens', () {
      final state = buildState(
        selectedDirection: 'a',
        screenSelections: {
          'commerce.plp': ReviewScreenDecision(
            direction: 'a',
            sections: const {'plp.product-grid': 'a'},
          ),
          'commerce.pdp': ReviewScreenDecision(
            direction: 'c',
            sections: const {'pdp.price': 'c'},
          ),
          'commerce.search': ReviewScreenDecision(),
        },
      );

      final normalized = normalizeReviewDecisions(state, runtime);

      expect(normalized.screenSelections, {
        'commerce.pdp': ReviewScreenDecision(direction: 'c'),
      });
    });

    test(
        'changing a screen direction removes a newly redundant child override '
        'but retains a still-valid different-source override', () {
      final before = buildState(
        selectedDirection: 'c',
        screenSelections: {
          'commerce.search': ReviewScreenDecision(
            direction: 'a',
            sections: const {
              'search.search-field': 'b',
              'search.results-grid': 'a',
            },
          ),
        },
      );

      final normalizedBefore = normalizeReviewDecisions(before, runtime);
      expect(
        normalizedBefore.screenSelections['commerce.search']!.sections,
        {'search.search-field': 'b'},
      );

      final after = buildState(
        selectedDirection: 'c',
        screenSelections: {
          'commerce.search': ReviewScreenDecision(
            direction: 'b',
            sections: const {
              'search.search-field': 'b',
              'search.results-grid': 'a',
            },
          ),
        },
      );

      final normalizedAfter = normalizeReviewDecisions(after, runtime);
      expect(
        normalizedAfter.screenSelections['commerce.search']!.direction,
        'b',
      );
      expect(
        normalizedAfter.screenSelections['commerce.search']!.sections,
        {'search.results-grid': 'a'},
      );
    });

    test('overall change revalidates inherited screens and drops stale overrides',
        () {
      final before = buildState(
        selectedDirection: 'a',
        screenSelections: {
          'commerce.search': ReviewScreenDecision(
            sections: const {'search.search-field': 'b'},
          ),
        },
      );
      expect(
        normalizeReviewDecisions(before, runtime)
            .screenSelections['commerce.search']!
            .sections,
        {'search.search-field': 'b'},
      );

      final after = buildState(
        selectedDirection: 'c',
        screenSelections: {
          'commerce.search': ReviewScreenDecision(
            sections: const {'search.search-field': 'b'},
          ),
        },
      );
      expect(normalizeReviewDecisions(after, runtime).screenSelections, isEmpty);
    });

    test('unrelated valid decisions and comments survive unchanged', () {
      const comments = [
        ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'keep me'),
        ReviewComment(
          id: 'c2',
          scope: ReviewCommentScope.screen,
          screen: 'commerce.plp',
          text: 'screen note',
        ),
      ];
      final state = buildState(
        selectedDirection: 'a',
        screenSelections: {
          'commerce.pdp': ReviewScreenDecision(
            direction: 'c',
            sections: const {'pdp.price': 'a'},
          ),
        },
        comments: comments,
      );

      final normalized = normalizeReviewDecisions(state, runtime);

      expect(normalized.screenSelections, {
        'commerce.pdp': ReviewScreenDecision(
          direction: 'c',
          sections: const {'pdp.price': 'a'},
        ),
      });
      expect(normalized.comments, comments);
      expect(normalized.selectedDirection, 'a');
      expect(normalized.clientId, 'prototype-demo');
      expect(normalized.reviewRound, 1);
      expect(normalized.status, ReviewStatus.inReview);
    });

    test('is deterministic, idempotent, and never mutates its inputs', () {
      final state = buildState(
        selectedDirection: 'a',
        screenSelections: {
          'commerce.plp': ReviewScreenDecision(
            direction: 'a',
            sections: const {'plp.product-grid': 'a'},
          ),
          'commerce.search': ReviewScreenDecision(
            direction: 'b',
            sections: const {'search.search-field': 'a'},
          ),
        },
        comments: const [
          ReviewComment(id: 'c1', scope: ReviewCommentScope.general, text: 'note'),
        ],
      );
      final stateJsonBefore = state.toJson();
      final runtimeBefore = {
        for (final entry in runtime.directions.entries)
          entry.key: entry.value.patterns.toList(),
      };

      final first = normalizeReviewDecisions(state, runtime);
      final second = normalizeReviewDecisions(first, runtime);

      expect(first, second);
      expect(first.toJson(), second.toJson());
      expect(state.toJson(), stateJsonBefore);
      expect(
        {
          for (final entry in runtime.directions.entries)
            entry.key: entry.value.patterns.toList(),
        },
        runtimeBefore,
      );
    });

    test('never invents a direction when selected_direction is null', () {
      final state = buildState(
        selectedDirection: null,
        screenSelections: {
          'commerce.plp': ReviewScreenDecision(
            sections: const {'plp.product-grid': 'a'},
          ),
          'commerce.pdp': ReviewScreenDecision(direction: 'a'),
        },
      );

      final normalized = normalizeReviewDecisions(state, runtime);

      expect(normalized.selectedDirection, isNull);
      expect(normalized.screenSelections, {
        'commerce.pdp': ReviewScreenDecision(direction: 'a'),
      });
    });
  });
}
