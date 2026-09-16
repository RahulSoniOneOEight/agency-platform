import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/review/review_state_hash.dart';

ReviewState state({
  String? selectedDirection,
  List<String> feedbackIds = const <String>['feedback-1'],
}) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: 'prototype-demo',
    reviewRound: 1,
    status: ReviewStatus.inReview,
    selectedDirection: selectedDirection,
    screenSelections: {
      'commerce.home': ReviewScreenDecision(
        direction: 'b',
        sections: const {'home.product-grid': 'c'},
      ),
    },
    comments: const <ReviewComment>[],
    feedbackIds: feedbackIds,
  );
}

void main() {
  group('sha256Hex', () {
    test('matches canonical known vectors', () {
      expect(
        sha256Hex(utf8.encode('')),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex(utf8.encode('The quick brown fox jumps over the lazy dog')),
        'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
      );
    });
  });

  group('reviewStateHash', () {
    test('is deterministic and prefixed', () {
      final value = state();
      expect(reviewStateHash(value), reviewStateHash(value));
      expect(reviewStateHash(value), startsWith('sha256:'));
    });

    test('changes when the decision tree or feedback references change', () {
      expect(reviewStateHash(state()), isNot(reviewStateHash(state(selectedDirection: 'a'))));
      expect(
        reviewStateHash(state()),
        isNot(reviewStateHash(state(feedbackIds: const ['feedback-2']))),
      );
    });

    test('hashes the canonical JSON of the state', () {
      final value = state();
      expect(
        reviewStateHash(value),
        'sha256:${sha256Hex(utf8.encode(canonicalReviewStateJson(value)))}',
      );
    });
  });
}
