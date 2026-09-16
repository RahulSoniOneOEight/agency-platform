import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_state.dart';

Map<String, dynamic> canonicalStateJson({
  int version = 1,
  String clientId = 'prototype-demo',
  Object? reviewRound = 1,
  String status = 'in_review',
  Object? selectedDirection,
  Map<String, dynamic>? screenSelections,
  List<dynamic>? comments,
}) {
  return {
    'version': version,
    'client_id': clientId,
    'review_round': reviewRound,
    'status': status,
    'selected_direction': selectedDirection,
    'screen_selections': screenSelections ?? {'home': 'a'},
    'comments': comments ?? const [],
  };
}

void main() {
  group('ReviewState parsing and serialization', () {
    test('round-trips the canonical shape', () {
      final state = ReviewState.fromJson({
        'version': 1,
        'client_id': 'prototype-demo',
        'review_round': 1,
        'status': 'in_review',
        'selected_direction': null,
        'screen_selections': {'home': 'a'},
        'comments': [
          {
            'id': 'review-001',
            'scope': 'general',
            'text': 'Prefer the quieter visual hierarchy.',
          }
        ],
      });

      expect(state.version, 1);
      expect(state.clientId, 'prototype-demo');
      expect(state.reviewRound, 1);
      expect(state.status, ReviewStatus.inReview);
      expect(state.selectedDirection, isNull);
      expect(state.screenSelections, {'home': 'a'});
      expect(state.comments, hasLength(1));
      expect(state.comments.single.scope, ReviewCommentScope.general);

      expect(state.toJson(), {
        'version': 1,
        'client_id': 'prototype-demo',
        'review_round': 1,
        'status': 'in_review',
        'selected_direction': null,
        'screen_selections': {'home': 'a'},
        'comments': [
          {
            'id': 'review-001',
            'scope': 'general',
            'text': 'Prefer the quieter visual hierarchy.',
          }
        ],
      });
      expect(ReviewState.fromJson(state.toJson()), state);
    });

    test('round-trips a null selected direction as JSON null', () {
      final state = ReviewState.fromJson(canonicalStateJson(selectedDirection: null));
      final json = state.toJson();

      expect(json.containsKey('selected_direction'), isTrue);
      expect(json['selected_direction'], isNull);
      expect(ReviewState.fromJson(json).selectedDirection, isNull);
    });

    test('serializes screen comment screen and direction when present', () {
      final state = ReviewState.fromJson(canonicalStateJson(
        selectedDirection: 'b',
        comments: [
          {
            'id': 'review-002',
            'scope': 'screen',
            'screen': 'home',
            'direction': 'a',
            'text': 'Reduce hero height.',
          }
        ],
      ));

      expect(state.toJson()['comments'], [
        {
          'id': 'review-002',
          'scope': 'screen',
          'screen': 'home',
          'direction': 'a',
          'text': 'Reduce hero height.',
        }
      ]);
    });

    test('emits screen_selections keys in stable sorted order regardless of input order', () {
      final first = ReviewState.fromJson(canonicalStateJson(
        screenSelections: {'search': 'b', 'home': 'a'},
      ));
      final second = ReviewState.fromJson(canonicalStateJson(
        screenSelections: {'home': 'a', 'search': 'b'},
      ));

      expect(
        (first.toJson()['screen_selections'] as Map<String, dynamic>).keys.toList(),
        ['home', 'search'],
      );
      expect(
        (second.toJson()['screen_selections'] as Map<String, dynamic>).keys.toList(),
        ['home', 'search'],
      );
      expect(first.toJson(), second.toJson());
    });

    test('preserves comment list order', () {
      final state = ReviewState.fromJson(canonicalStateJson(
        comments: [
          {'id': 'c2', 'scope': 'general', 'text': 'second'},
          {'id': 'c1', 'scope': 'general', 'text': 'first'},
        ],
      ));

      expect(
        (state.toJson()['comments'] as List<dynamic>)
            .map((comment) => (comment as Map<String, dynamic>)['id'])
            .toList(),
        ['c2', 'c1'],
      );
    });

    test('always emits every required top-level key', () {
      final state = ReviewState.fromJson(canonicalStateJson());
      expect(
        state.toJson().keys.toSet(),
        {
          'version',
          'client_id',
          'review_round',
          'status',
          'selected_direction',
          'screen_selections',
          'comments',
        },
      );
    });

    test('parses an unsupported version structurally so the validator can reject it', () {
      final state = ReviewState.fromJson(canonicalStateJson(version: 2));
      expect(state.version, 2);
    });

    test('throws FormatException for an unknown status wire value', () {
      expect(
        () => ReviewState.fromJson(canonicalStateJson(status: 'approved')),
        throwsFormatException,
      );
    });

    test('throws FormatException for an unknown comment scope wire value', () {
      expect(
        () => ReviewComment.fromJson({'id': 'c1', 'scope': 'widget', 'text': 'x'}),
        throwsFormatException,
      );
    });

    test('requires review_round to be an int', () {
      expect(
        () => ReviewState.fromJson(canonicalStateJson(reviewRound: 1.0)),
        throwsFormatException,
      );
      expect(
        () => ReviewState.fromJson({
          'version': 1,
          'client_id': 'prototype-demo',
          'review_round': '1',
          'status': 'in_review',
          'selected_direction': null,
          'screen_selections': <String, dynamic>{},
          'comments': <dynamic>[],
        }),
        throwsFormatException,
      );
    });

    test('parses review_round below 1 structurally (round validation is semantic)', () {
      final state = ReviewState.fromJson(canonicalStateJson(reviewRound: 0));
      expect(state.reviewRound, 0);
    });

    test('throws FormatException when a required field is missing', () {
      final missingStatus = canonicalStateJson()..remove('status');
      expect(() => ReviewState.fromJson(missingStatus), throwsFormatException);

      final missingClient = canonicalStateJson()..remove('client_id');
      expect(() => ReviewState.fromJson(missingClient), throwsFormatException);

      final missingComments = canonicalStateJson()..remove('comments');
      expect(() => ReviewState.fromJson(missingComments), throwsFormatException);

      expect(
        () => ReviewComment.fromJson({'scope': 'general', 'text': 'x'}),
        throwsFormatException,
      );
    });
  });
}
