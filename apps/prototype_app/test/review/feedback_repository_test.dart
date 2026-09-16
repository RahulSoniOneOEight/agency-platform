import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/feedback_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';

FeedbackRecord record(
  String id, {
  bool blocking = true,
  FeedbackScope scope = FeedbackScope.general,
  FeedbackTarget target = const FeedbackTarget(),
}) {
  return FeedbackRecord(
    id: id,
    scope: scope,
    text: 'note $id',
    status: FeedbackStatus.open,
    blocking: blocking,
    createdRound: 1,
    target: target,
    history: [
      FeedbackEvent(
        type: FeedbackEventType.created,
        actorId: 'reviewer-1',
        at: DateTime.utc(2026, 9, 17, 10),
        round: 1,
      ),
    ],
  );
}

void main() {
  late FeedbackRepository repository;

  setUp(() {
    repository = MemoryFeedbackRepository();
  });

  group('create and load', () {
    test('round-trips a record by client id', () async {
      final value = record('feedback-1');

      await repository.create('prototype-demo', value);

      expect(await repository.load('prototype-demo', 'feedback-1'), value);
      expect(await repository.load('prototype-demo', 'missing'), isNull);
      expect(await repository.load('other-client', 'feedback-1'), isNull);
    });

    test('rejects a duplicate id with a StateError and keeps the original',
        () async {
      final original = record('feedback-1', blocking: true);
      final duplicate = record('feedback-1', blocking: false);

      await repository.create('prototype-demo', original);

      await expectLater(
        () => repository.create('prototype-demo', duplicate),
        throwsStateError,
      );
      expect(await repository.load('prototype-demo', 'feedback-1'), original);
    });

    test('keeps distinct clients isolated', () async {
      await repository.create('alpha', record('feedback-1'));
      await repository.create('beta', record('feedback-1', blocking: false));

      expect(
        (await repository.load('alpha', 'feedback-1'))!.blocking,
        isTrue,
      );
      expect(
        (await repository.load('beta', 'feedback-1'))!.blocking,
        isFalse,
      );
    });
  });

  group('list', () {
    test('returns an empty list for an unknown client', () async {
      expect(await repository.list('missing'), isEmpty);
    });

    test('returns records in deterministic id order regardless of creation order',
        () async {
      await repository.create('prototype-demo', record('feedback-3'));
      await repository.create('prototype-demo', record('feedback-1'));
      await repository.create('prototype-demo', record('feedback-2'));

      final listed = await repository.list('prototype-demo');
      expect(
        listed.map((value) => value.id).toList(),
        ['feedback-1', 'feedback-2', 'feedback-3'],
      );
    });
  });

  group('replace (expected-current semantics)', () {
    test('replaces the stored record when it matches the expectation',
        () async {
      final current = record('feedback-1', blocking: true);
      await repository.create('prototype-demo', current);
      final next = current.copyWith(blocking: false);

      await repository.replace('prototype-demo', current, next);

      expect(await repository.load('prototype-demo', 'feedback-1'), next);
    });

    test('rejects a stale expectation without overwriting the stored record',
        () async {
      final current = record('feedback-1', blocking: true);
      await repository.create('prototype-demo', current);
      final stale = current.copyWith(blocking: false);

      await expectLater(
        () => repository.replace(
          'prototype-demo',
          stale,
          stale.copyWith(blocking: true),
        ),
        throwsStateError,
      );
      expect(await repository.load('prototype-demo', 'feedback-1'), current);
    });

    test('rejects an unknown record', () async {
      final missing = record('feedback-1');

      await expectLater(
        () => repository.replace(
          'prototype-demo',
          missing,
          missing.copyWith(blocking: false),
        ),
        throwsStateError,
      );
    });

    test('rejects a replacement whose id differs from the expectation',
        () async {
      final current = record('feedback-1');
      await repository.create('prototype-demo', current);

      await expectLater(
        () => repository.replace(
          'prototype-demo',
          current,
          record('feedback-2'),
        ),
        throwsStateError,
      );
      expect(await repository.load('prototype-demo', 'feedback-1'), current);
      expect(await repository.load('prototype-demo', 'feedback-2'), isNull);
    });
  });
}
