import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';

Map<String, dynamic> v1Json({
  Object? screenSelections = const {'commerce.home': 'b'},
  String? selectedDirection,
  int reviewRound = 2,
  String status = 'in_review',
  String clientId = 'prototype-demo',
  List<dynamic> comments = const [],
}) {
  return {
    'version': 1,
    'client_id': clientId,
    'review_round': reviewRound,
    'status': status,
    'selected_direction': selectedDirection,
    'screen_selections': screenSelections,
    'comments': comments,
  };
}

Map<String, dynamic> v2Json({
  Map<String, dynamic>? screenSelections,
  String? selectedDirection,
  int reviewRound = 2,
  String status = 'in_review',
  String clientId = 'prototype-demo',
  List<dynamic> comments = const [],
}) {
  return {
    'version': 2,
    'client_id': clientId,
    'review_round': reviewRound,
    'status': status,
    'selected_direction': selectedDirection,
    'screen_selections': screenSelections ?? const <String, dynamic>{},
    'comments': comments,
  };
}

void main() {
  group('version 1 migration', () {
    test('migrates a v1 screen direction map into v2 decisions', () {
      final state = ReviewState.fromJson(v1Json(
        screenSelections: const {'commerce.home': 'b'},
      ));

      expect(state.version, ReviewState.currentVersion);
      expect(state.version, 2);
      expect(state.screenSelections['commerce.home'], isA<ReviewScreenDecision>());
      expect(state.screenSelections['commerce.home']!.direction, 'b');
      expect(state.screenSelections['commerce.home']!.sections, isEmpty);
      expect(state.toJson()['version'], 2);
      expect(
        state.toJson()['screen_selections'],
        {
          'commerce.home': {
            'direction': 'b',
            'sections': <String, dynamic>{},
          },
        },
      );
    });

    test('preserves comments, status, round, selected direction and client id', () {
      final state = ReviewState.fromJson(v1Json(
        screenSelections: const {'commerce.home': 'b'},
        selectedDirection: 'a',
        reviewRound: 4,
        status: 'needs_revision',
        comments: [
          {'id': 'c1', 'scope': 'general', 'text': 'keep me'},
          {
            'id': 'c2',
            'scope': 'screen',
            'screen': 'commerce.home',
            'direction': 'b',
            'text': 'screen note',
          },
        ],
      ));

      expect(state.clientId, 'prototype-demo');
      expect(state.reviewRound, 4);
      expect(state.status, ReviewStatus.needsRevision);
      expect(state.selectedDirection, 'a');
      expect(state.comments.map((comment) => comment.id), ['c1', 'c2']);
      expect(state.comments[1].screen, 'commerce.home');
      expect(state.comments[1].direction, 'b');

      final json = state.toJson();
      expect(json['client_id'], 'prototype-demo');
      expect(json['review_round'], 4);
      expect(json['status'], 'needs_revision');
      expect(json['selected_direction'], 'a');
      expect(json['comments'], hasLength(2));
    });

    test('rejects a non-string legacy value', () {
      expect(
        () => ReviewState.fromJson(v1Json(screenSelections: const {'home': 1})),
        throwsFormatException,
      );
    });

    test('rejects an empty legacy string', () {
      expect(
        () => ReviewState.fromJson(v1Json(screenSelections: const {'home': ''})),
        throwsFormatException,
      );
    });

    test('rejects a whitespace-only legacy string', () {
      expect(
        () => ReviewState.fromJson(v1Json(screenSelections: const {'home': '  '})),
        throwsFormatException,
      );
    });

    test('rejects a list legacy value', () {
      expect(
        () => ReviewState.fromJson(v1Json(screenSelections: const {'home': ['a']})),
        throwsFormatException,
      );
    });

    test('rejects a v2-shaped map inside a version 1 document', () {
      expect(
        () => ReviewState.fromJson(v1Json(
          screenSelections: const {
            'home': {'direction': 'a', 'sections': <String, dynamic>{}},
          },
        )),
        throwsFormatException,
      );
    });
  });

  group('version 2 canonical', () {
    test('round-trips canonical v2 state with equality', () {
      final json = v2Json(
        selectedDirection: 'a',
        screenSelections: const {
          'commerce.home': {
            'direction': 'b',
            'sections': {'commerce.home.hero': 'c'},
          },
          'commerce.search': {
            'sections': {'commerce.search.results': 'b'},
          },
        },
        comments: [
          {'id': 'c1', 'scope': 'general', 'text': 'note'},
        ],
      );

      final state = ReviewState.fromJson(json);
      final restored = ReviewState.fromJson(state.toJson());

      expect(state, equals(restored));
      expect(state.screenSelections['commerce.home']!.direction, 'b');
      expect(state.screenSelections['commerce.home']!.sections, {'commerce.home.hero': 'c'});
      expect(state.screenSelections['commerce.search']!.direction, isNull);
      expect(state.screenSelections['commerce.search']!.sections, {'commerce.search.results': 'b'});
    });

    test('treats a missing sections key as an empty map', () {
      final state = ReviewState.fromJson(v2Json(
        screenSelections: const {
          'commerce.home': {'direction': 'b'},
        },
      ));

      expect(state.screenSelections['commerce.home']!.sections, isEmpty);
    });

    test('rejects a non-map v2 screen value', () {
      expect(
        () => ReviewState.fromJson(v2Json(
          screenSelections: const {'commerce.home': 'b'},
        )),
        throwsFormatException,
      );
    });

    test('rejects a non-string v2 section value', () {
      expect(
        () => ReviewState.fromJson(v2Json(
          screenSelections: const {
            'commerce.home': {
              'direction': 'b',
              'sections': {'commerce.home.hero': 1},
            },
          },
        )),
        throwsFormatException,
      );
    });

    test('rejects an empty v2 screen direction string', () {
      expect(
        () => ReviewState.fromJson(v2Json(
          screenSelections: const {
            'commerce.home': {'direction': ''},
          },
        )),
        throwsFormatException,
      );
    });

    test('rejects a non-map sections value', () {
      expect(
        () => ReviewState.fromJson(v2Json(
          screenSelections: const {
            'commerce.home': {'direction': 'b', 'sections': 'nope'},
          },
        )),
        throwsFormatException,
      );
    });
  });

  group('unsupported versions', () {
    test('rejects a version other than one or two', () {
      expect(
        () => ReviewState.fromJson(v2Json()..['version'] = 3),
        throwsFormatException,
      );
      expect(
        () => ReviewState.fromJson(v1Json()..['version'] = 0),
        throwsFormatException,
      );
    });
  });

  group('deterministic serialization', () {
    test('sorts screen keys and nested section keys', () {
      final state = ReviewState.fromJson(v2Json(
        screenSelections: const {
          'commerce.search': {
            'direction': 'b',
            'sections': {
              'commerce.search.results': 'a',
              'commerce.search.filters': 'c',
            },
          },
          'commerce.home': {
            'direction': 'a',
            'sections': {
              'commerce.home.hero': 'b',
              'commerce.home.grid': 'c',
            },
          },
        },
      ));

      final json = state.toJson();
      final selections = json['screen_selections'] as Map<String, dynamic>;
      expect(selections.keys.toList(), ['commerce.home', 'commerce.search']);

      final home = selections['commerce.home'] as Map<String, dynamic>;
      expect(
        (home['sections'] as Map<String, dynamic>).keys.toList(),
        ['commerce.home.grid', 'commerce.home.hero'],
      );
      final search = selections['commerce.search'] as Map<String, dynamic>;
      expect(
        (search['sections'] as Map<String, dynamic>).keys.toList(),
        ['commerce.search.filters', 'commerce.search.results'],
      );
    });

    test('emits direction only when non-null', () {
      final state = ReviewState.fromJson(v2Json(
        screenSelections: const {
          'commerce.home': {'direction': 'b', 'sections': <String, dynamic>{}},
          'commerce.search': {'sections': <String, dynamic>{}},
        },
      ));

      final selections = state.toJson()['screen_selections'] as Map<String, dynamic>;
      expect((selections['commerce.home'] as Map<String, dynamic>).containsKey('direction'), isTrue);
      expect((selections['commerce.search'] as Map<String, dynamic>).containsKey('direction'), isFalse);
    });
  });

  group('immutability', () {
    test('wrapping the constructor map keeps state immutable', () {
      final selections = <String, ReviewScreenDecision>{
        'commerce.home': ReviewScreenDecision(direction: 'a'),
      };
      final state = ReviewState(
        version: ReviewState.currentVersion,
        clientId: 'prototype-demo',
        reviewRound: 1,
        status: ReviewStatus.inReview,
        selectedDirection: null,
        screenSelections: selections,
        comments: const <ReviewComment>[],
      );

      expect(
        () => state.screenSelections['commerce.search'] =
            ReviewScreenDecision(direction: 'b'),
        throwsUnsupportedError,
      );

      selections['commerce.home'] = ReviewScreenDecision(direction: 'c');
      expect(state.screenSelections['commerce.home']!.direction, 'a');
    });

    test('nested section maps are unmodifiable', () {
      final sections = <String, String>{'commerce.home.hero': 'b'};
      final decision = ReviewScreenDecision(direction: 'a', sections: sections);

      expect(
        () => decision.sections['commerce.home.grid'] = 'c',
        throwsUnsupportedError,
      );

      sections['commerce.home.hero'] = 'c';
      expect(decision.sections['commerce.home.hero'], 'b');
    });

    test('parsed nested section maps are unmodifiable', () {
      final state = ReviewState.fromJson(v2Json(
        screenSelections: const {
          'commerce.home': {
            'direction': 'a',
            'sections': {'commerce.home.hero': 'b'},
          },
        },
      ));

      expect(
        () => state.screenSelections['commerce.home']!.sections['x'] = 'y',
        throwsUnsupportedError,
      );
    });
  });
}
