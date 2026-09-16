import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/approval_snapshot.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_screen_decision.dart';

const reviewer = ReviewActor(
  id: 'reviewer-123',
  name: 'Rahul',
  role: ReviewRole.reviewer,
);
const approver = ReviewActor(
  id: 'approver-456',
  name: 'Priya',
  role: ReviewRole.approver,
);

ApprovalSnapshot snapshot({
  int version = 1,
  String clientId = 'prototype-demo',
  int reviewRound = 3,
  ReviewActor reviewedBy = reviewer,
  ReviewActor approvedBy = approver,
  DateTime? approvedAt,
  String? selectedDirection = 'a',
  Map<String, ReviewScreenDecision>? screenSelections,
  List<String> unresolved = const <String>[],
  String sourceCommitSha = 'abc123',
  String reviewStateHash = 'sha256:deadbeef',
  String? themePreset,
  int? supersedes,
}) {
  return ApprovalSnapshot(
    version: version,
    clientId: clientId,
    reviewRound: reviewRound,
    reviewedBy: reviewedBy,
    approvedBy: approvedBy,
    approvedAt: approvedAt ?? DateTime.utc(2026, 9, 17, 12, 30),
    selectedDirection: selectedDirection,
    screenSelections: screenSelections ??
        {
          'commerce.home': ReviewScreenDecision(
            direction: 'b',
            sections: const {'home.product-grid': 'c'},
          ),
        },
    unresolvedNonBlockingFeedbackIds: unresolved,
    sourceCommitSha: sourceCommitSha,
    reviewStateHash: reviewStateHash,
    themePreset: themePreset,
    supersedes: supersedes,
  );
}

void main() {
  group('serialization', () {
    test('round-trips deterministically', () {
      final original = snapshot(
        unresolved: const ['feedback-021', 'feedback-003'],
        themePreset: 'editorial',
      );

      final json = original.toJson();
      expect(json['approval_version'], 1);
      expect(json['client_id'], 'prototype-demo');
      expect(json['review_round'], 3);
      expect(json['reviewed_by'], {'id': 'reviewer-123', 'name': 'Rahul'});
      expect(json['approved_by'], {'id': 'approver-456', 'name': 'Priya'});
      expect(json['approved_at'], '2026-09-17T12:30:00.000Z');
      expect(json['selected_direction'], 'a');
      expect(json['screens'], {
        'commerce.home': {
          'direction': 'b',
          'sections': {'home.product-grid': 'c'},
        },
      });
      expect(json['source_commit_sha'], 'abc123');
      expect(json['review_state_hash'], 'sha256:deadbeef');
      expect(json['theme_preset'], 'editorial');
      expect(json['supersedes'], isNull);

      expect(ApprovalSnapshot.fromJson(json), original);
    });

    test('always emits every canonical top-level key', () {
      expect(snapshot().toJson().keys.toSet(), {
        'approval_version',
        'client_id',
        'review_round',
        'reviewed_by',
        'approved_by',
        'approved_at',
        'selected_direction',
        'screens',
        'unresolved_non_blocking',
        'source_commit_sha',
        'review_state_hash',
        'theme_preset',
        'supersedes',
      });
    });

    test('normalizes and sorts unresolved non-blocking ids', () {
      final value = snapshot(unresolved: const ['feedback-b', 'feedback-a']);
      expect(value.unresolvedNonBlockingFeedbackIds, ['feedback-a', 'feedback-b']);
      expect(value.toJson()['unresolved_non_blocking'], ['feedback-a', 'feedback-b']);
    });

    test('throws FormatException for malformed payloads', () {
      final valid = snapshot().toJson();

      expect(
        () => ApprovalSnapshot.fromJson(valid..['approval_version'] = 'x'),
        throwsFormatException,
      );
      expect(
        () => ApprovalSnapshot.fromJson(snapshot().toJson()..remove('screens')),
        throwsFormatException,
      );
      expect(
        () => ApprovalSnapshot.fromJson(
          snapshot().toJson()..['unresolved_non_blocking'] = 'nope',
        ),
        throwsFormatException,
      );
      expect(
        () => ApprovalSnapshot.fromJson(
          snapshot().toJson()..['approved_at'] = 'not-a-date',
        ),
        throwsFormatException,
      );
      expect(
        () => ApprovalSnapshot.fromJson(
          snapshot().toJson()..remove('reviewed_by'),
        ),
        throwsFormatException,
      );
    });
  });

  group('reviewer and approver identity', () {
    test('records reviewer and approver separately', () {
      final value = snapshot();
      expect(value.reviewedBy.role, ReviewRole.reviewer);
      expect(value.approvedBy.role, ReviewRole.approver);
      expect(value.reviewedBy.id, isNot(value.approvedBy.id));
    });

    test('allows the same person to occupy both roles', () {
      final value = snapshot(
        reviewedBy: reviewer,
        approvedBy: const ReviewActor(
          id: 'reviewer-123',
          name: 'Rahul',
          role: ReviewRole.approver,
        ),
      );

      expect(value.reviewedBy.id, value.approvedBy.id);
      expect(value.reviewedBy.role, ReviewRole.reviewer);
      expect(value.approvedBy.role, ReviewRole.approver);
      expect(ApprovalSnapshot.fromJson(value.toJson()), value);
    });

    test('rejects a reviewed_by that is not a reviewer', () {
      expect(
        () => snapshot(
          reviewedBy: const ReviewActor(
            id: 'x',
            name: 'X',
            role: ReviewRole.approver,
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects an approved_by that is not an approver', () {
      expect(
        () => snapshot(
          approvedBy: const ReviewActor(
            id: 'x',
            name: 'X',
            role: ReviewRole.reviewer,
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('invariants', () {
    test('requires a positive version and review round', () {
      expect(() => snapshot(version: 0), throwsFormatException);
      expect(() => snapshot(reviewRound: 0), throwsFormatException);
    });

    test('requires a client id, commit sha and review-state hash', () {
      expect(() => snapshot(clientId: '  '), throwsFormatException);
      expect(() => snapshot(sourceCommitSha: ''), throwsFormatException);
      expect(() => snapshot(reviewStateHash: ' '), throwsFormatException);
    });

    test('rejects a supersedes reference that is not an earlier version', () {
      expect(() => snapshot(version: 1, supersedes: 1), throwsFormatException);
      expect(() => snapshot(version: 2, supersedes: 3), throwsFormatException);
      final value = snapshot(version: 2, supersedes: 1);
      expect(value.supersedes, 1);
    });

    test('rejects blank or duplicate unresolved feedback ids', () {
      expect(() => snapshot(unresolved: const [' ']), throwsFormatException);
      expect(
        () => snapshot(unresolved: const ['feedback-1', 'feedback-1']),
        throwsFormatException,
      );
    });

    test('wraps collections so the snapshot cannot be mutated', () {
      final selections = <String, ReviewScreenDecision>{
        'commerce.home': ReviewScreenDecision(direction: 'b'),
      };
      final unresolved = <String>['feedback-1'];
      final value = snapshot(
        screenSelections: selections,
        unresolved: unresolved,
      );

      expect(
        () => value.screenSelections['commerce.search'] =
            ReviewScreenDecision(direction: 'a'),
        throwsUnsupportedError,
      );
      expect(
        () => value.unresolvedNonBlockingFeedbackIds.add('feedback-2'),
        throwsUnsupportedError,
      );
      selections.clear();
      unresolved.clear();
      expect(value.screenSelections, hasLength(1));
      expect(value.unresolvedNonBlockingFeedbackIds, ['feedback-1']);
    });
  });

  group('equality', () {
    test('compares every field', () {
      expect(snapshot(), equals(snapshot()));
      expect(snapshot().hashCode, equals(snapshot().hashCode));
      expect(snapshot(), isNot(equals(snapshot(version: 2))));
      expect(snapshot(), isNot(equals(snapshot(reviewRound: 4))));
      expect(snapshot(), isNot(equals(snapshot(sourceCommitSha: 'def'))));
      expect(
        snapshot(),
        isNot(equals(snapshot(unresolved: const ['feedback-1']))),
      );
    });
  });
}
