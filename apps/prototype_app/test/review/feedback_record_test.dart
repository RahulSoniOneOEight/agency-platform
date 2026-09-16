import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/feedback_record.dart';

FeedbackEvent createdEvent({
  String actorId = 'reviewer-1',
  int round = 1,
}) {
  return FeedbackEvent(
    type: FeedbackEventType.created,
    actorId: actorId,
    at: DateTime.utc(2026, 9, 17, 10),
    round: round,
  );
}

FeedbackRecord record({
  String id = 'feedback-1',
  FeedbackScope scope = FeedbackScope.general,
  String text = 'Increase spacing above this section',
  FeedbackStatus status = FeedbackStatus.open,
  bool blocking = true,
  int createdRound = 1,
  FeedbackTarget target = const FeedbackTarget(),
  List<FeedbackEvent>? history,
  int? resolvedRound,
}) {
  return FeedbackRecord(
    id: id,
    scope: scope,
    text: text,
    status: status,
    blocking: blocking,
    createdRound: createdRound,
    target: target,
    history: history ?? [createdEvent(round: createdRound)],
    resolvedRound: resolvedRound,
  );
}

void main() {
  group('wire values', () {
    test('statuses round-trip through stable wire values', () {
      for (final status in FeedbackStatus.values) {
        expect(feedbackStatusFromWire(feedbackStatusToWire(status)), status);
      }
      expect(feedbackStatusToWire(FeedbackStatus.open), 'open');
      expect(feedbackStatusToWire(FeedbackStatus.addressed), 'addressed');
      expect(feedbackStatusToWire(FeedbackStatus.resolved), 'resolved');
      expect(() => feedbackStatusFromWire('approved'), throwsFormatException);
    });

    test('scopes round-trip and use snake_case for visual annotations', () {
      for (final scope in FeedbackScope.values) {
        expect(feedbackScopeFromWire(feedbackScopeToWire(scope)), scope);
      }
      expect(feedbackScopeToWire(FeedbackScope.visualAnnotation), 'visual_annotation');
      expect(feedbackScopeToWire(FeedbackScope.general), 'general');
      expect(feedbackScopeToWire(FeedbackScope.screen), 'screen');
      expect(feedbackScopeToWire(FeedbackScope.section), 'section');
      expect(feedbackScopeToWire(FeedbackScope.decision), 'decision');
      expect(() => feedbackScopeFromWire('widget'), throwsFormatException);
    });

    test('event types round-trip through stable wire values', () {
      for (final type in FeedbackEventType.values) {
        expect(feedbackEventTypeFromWire(feedbackEventTypeToWire(type)), type);
      }
      expect(feedbackEventTypeToWire(FeedbackEventType.blockingChanged), 'blocking_changed');
      expect(() => feedbackEventTypeFromWire('deleted'), throwsFormatException);
    });
  });

  group('target validation per scope', () {
    test('general feedback accepts an empty target only', () {
      expect(
        record(scope: FeedbackScope.general, target: const FeedbackTarget()).target,
        const FeedbackTarget(),
      );
      expect(
        () => record(
          scope: FeedbackScope.general,
          target: const FeedbackTarget(direction: 'a'),
        ),
        throwsFormatException,
      );
      expect(
        () => record(
          scope: FeedbackScope.general,
          target: const FeedbackTarget(screen: 'commerce.home'),
        ),
        throwsFormatException,
      );
    });

    test('screen feedback requires a screen and forbids a section', () {
      expect(
        record(
          scope: FeedbackScope.screen,
          target: const FeedbackTarget(screen: 'commerce.home'),
        ).target.screen,
        'commerce.home',
      );
      expect(
        () => record(scope: FeedbackScope.screen, target: const FeedbackTarget()),
        throwsFormatException,
      );
      expect(
        () => record(
          scope: FeedbackScope.screen,
          target: const FeedbackTarget(
            screen: 'commerce.home',
            section: 'home.product-grid',
          ),
        ),
        throwsFormatException,
      );
    });

    test('section feedback requires both a screen and a section', () {
      expect(
        record(
          scope: FeedbackScope.section,
          target: const FeedbackTarget(
            screen: 'commerce.home',
            section: 'home.product-grid',
          ),
        ).target.section,
        'home.product-grid',
      );
      expect(
        () => record(
          scope: FeedbackScope.section,
          target: const FeedbackTarget(screen: 'commerce.home'),
        ),
        throwsFormatException,
      );
      expect(
        () => record(
          scope: FeedbackScope.section,
          target: const FeedbackTarget(section: 'home.product-grid'),
        ),
        throwsFormatException,
      );
    });

    test('decision feedback requires a direction', () {
      expect(
        record(
          scope: FeedbackScope.decision,
          target: const FeedbackTarget(direction: 'a'),
        ).target.direction,
        'a',
      );
      expect(
        () => record(scope: FeedbackScope.decision, target: const FeedbackTarget()),
        throwsFormatException,
      );
    });

    test('visual annotation feedback accepts a free-form target', () {
      expect(
        record(
          scope: FeedbackScope.visualAnnotation,
          target: const FeedbackTarget(),
        ).scope,
        FeedbackScope.visualAnnotation,
      );
      expect(
        record(
          scope: FeedbackScope.visualAnnotation,
          target: const FeedbackTarget(
            screen: 'commerce.pdp',
            section: 'pdp.price',
          ),
        ).target.section,
        'pdp.price',
      );
      expect(
        () => record(
          scope: FeedbackScope.visualAnnotation,
          target: const FeedbackTarget(section: 'pdp.price'),
        ),
        throwsFormatException,
      );
    });

    test('blank target strings are rejected', () {
      expect(
        () => record(
          scope: FeedbackScope.screen,
          target: const FeedbackTarget(screen: '  '),
        ),
        throwsFormatException,
      );
    });
  });

  group('record invariants', () {
    test('requires a non-empty id and text', () {
      expect(() => record(id: '  '), throwsFormatException);
      expect(() => record(text: '   '), throwsFormatException);
    });

    test('requires a positive created round', () {
      expect(
        () => record(createdRound: 0, history: [createdEvent(round: 0)]),
        throwsFormatException,
      );
    });

    test('requires non-empty history that starts with created', () {
      expect(() => record(history: const []), throwsFormatException);
      expect(
        () => record(
          history: [
            FeedbackEvent(
              type: FeedbackEventType.addressed,
              actorId: 'agent-1',
              at: DateTime.utc(2026, 9, 17, 11),
            ),
          ],
        ),
        throwsFormatException,
      );
    });

    test('rejects a repeated created event', () {
      expect(
        () => record(
          history: [createdEvent(), createdEvent()],
        ),
        throwsFormatException,
      );
    });

    test('requires the status to match the append-only history', () {
      expect(
        () => record(status: FeedbackStatus.resolved),
        throwsFormatException,
      );
      expect(
        () => record(
          status: FeedbackStatus.addressed,
          history: [
            createdEvent(),
            FeedbackEvent(
              type: FeedbackEventType.resolved,
              actorId: 'reviewer-1',
              at: DateTime.utc(2026, 9, 17, 12),
            ),
          ],
        ),
        throwsFormatException,
      );
    });

    test('couples the resolved status to a resolved round', () {
      final resolved = record(
        status: FeedbackStatus.resolved,
        resolvedRound: 1,
        history: [
          createdEvent(),
          FeedbackEvent(
            type: FeedbackEventType.resolved,
            actorId: 'reviewer-1',
            at: DateTime.utc(2026, 9, 17, 12),
          ),
        ],
      );
      expect(resolved.status, FeedbackStatus.resolved);
      expect(resolved.resolvedRound, 1);

      expect(
        () => record(
          status: FeedbackStatus.resolved,
          history: [
            createdEvent(),
            FeedbackEvent(
              type: FeedbackEventType.resolved,
              actorId: 'reviewer-1',
              at: DateTime.utc(2026, 9, 17, 12),
            ),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => record(status: FeedbackStatus.open, resolvedRound: 2),
        throwsFormatException,
      );
    });

    test('rejects a resolved round that precedes creation', () {
      expect(
        () => record(
          createdRound: 2,
          status: FeedbackStatus.resolved,
          resolvedRound: 1,
          history: [
            createdEvent(round: 2),
            FeedbackEvent(
              type: FeedbackEventType.resolved,
              actorId: 'reviewer-1',
              at: DateTime.utc(2026, 9, 17, 12),
            ),
          ],
        ),
        throwsFormatException,
      );
    });
  });

  group('serialization', () {
    test('round-trips a section-scoped record with history', () {
      final original = record(
        id: 'feedback-001',
        scope: FeedbackScope.section,
        text: 'Increase spacing above this section',
        blocking: true,
        createdRound: 2,
        target: const FeedbackTarget(
          screen: 'commerce.home',
          section: 'home.product-grid',
        ),
        history: [
          FeedbackEvent(
            type: FeedbackEventType.created,
            actorId: 'reviewer-123',
            at: DateTime.utc(2026, 9, 17, 10),
            round: 2,
          ),
          FeedbackEvent(
            type: FeedbackEventType.addressed,
            actorId: 'opencode',
            at: DateTime.utc(2026, 9, 17, 11, 15),
            batchId: 'batch-007',
          ),
          FeedbackEvent(
            type: FeedbackEventType.reopened,
            actorId: 'reviewer-123',
            at: DateTime.utc(2026, 9, 17, 11, 40),
          ),
          FeedbackEvent(
            type: FeedbackEventType.resolved,
            actorId: 'reviewer-123',
            at: DateTime.utc(2026, 9, 17, 12),
            round: 2,
          ),
        ],
        status: FeedbackStatus.resolved,
        resolvedRound: 2,
      );

      final json = original.toJson();
      expect(json['scope'], 'section');
      expect(json['status'], 'resolved');
      expect(json['created_round'], 2);
      expect(json['resolved_round'], 2);
      expect(json['target'], {
        'screen': 'commerce.home',
        'section': 'home.product-grid',
      });
      expect((json['history'] as List<dynamic>), hasLength(4));
      expect(
        (json['history'] as List<dynamic>).first,
        {
          'type': 'created',
          'actor_id': 'reviewer-123',
          'at': '2026-09-17T10:00:00.000Z',
          'round': 2,
        },
      );

      expect(FeedbackRecord.fromJson(json), original);
    });

    test('always emits every canonical top-level key', () {
      final json = record().toJson();
      expect(
        json.keys.toSet(),
        {
          'id',
          'scope',
          'text',
          'status',
          'blocking',
          'created_round',
          'resolved_round',
          'target',
          'history',
        },
      );
      expect(json['resolved_round'], isNull);
    });

    test('emits history event round and batch id only when present', () {
      final json = record().toJson();
      expect(
        (json['history'] as List<dynamic>).single,
        {
          'type': 'created',
          'actor_id': 'reviewer-1',
          'at': '2026-09-17T10:00:00.000Z',
          'round': 1,
        },
      );
    });

    test('throws FormatException for malformed payloads', () {
      final valid = record().toJson();

      expect(
        () => FeedbackRecord.fromJson(valid..['scope'] = 'widget'),
        throwsFormatException,
      );
      expect(
        () => FeedbackRecord.fromJson(
          record().toJson()..['status'] = 'approved',
        ),
        throwsFormatException,
      );
      expect(
        () => FeedbackRecord.fromJson(record().toJson()..['history'] = 'nope'),
        throwsFormatException,
      );
      expect(
        () => FeedbackRecord.fromJson(record().toJson()..['target'] = 'nope'),
        throwsFormatException,
      );
      expect(
        () => FeedbackRecord.fromJson(record().toJson()..remove('blocking')),
        throwsFormatException,
      );
      expect(
        () => FeedbackRecord.fromJson(record().toJson()..remove('id')),
        throwsFormatException,
      );
      expect(
        () => FeedbackRecord.fromJson(
          record().toJson()
            ..['history'] = [
              {
                'type': 'created',
                'actor_id': 'reviewer-1',
                'at': 'not-a-date',
              }
            ],
        ),
        throwsFormatException,
      );
    });
  });

  group('immutability and equality', () {
    test('wraps the history collection so the record cannot be rewritten', () {
      final history = <FeedbackEvent>[createdEvent()];
      final value = record(history: history);

      expect(
        () => value.history.add(createdEvent()),
        throwsUnsupportedError,
      );

      history.clear();
      expect(value.history, hasLength(1));
    });

    test('value equality compares every field and history', () {
      expect(record(), equals(record()));
      expect(record().hashCode, equals(record().hashCode));
      expect(record(), isNot(equals(record(id: 'feedback-2'))));
      expect(record(), isNot(equals(record(blocking: false))));
      expect(
        record(),
        isNot(
          equals(
            record(
              history: [
                createdEvent(),
                FeedbackEvent(
                  type: FeedbackEventType.blockingChanged,
                  actorId: 'reviewer-1',
                  at: DateTime.utc(2026, 9, 17, 11),
                ),
              ],
            ),
          ),
        ),
      );
    });
  });
}
