import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/review_domain_error.dart';

final DateTime t0 = DateTime.utc(2026, 9, 17, 10);
final DateTime t1 = DateTime.utc(2026, 9, 17, 11);
final DateTime t2 = DateTime.utc(2026, 9, 17, 12);

RefinementBatch draftBatch({
  String id = 'batch-1',
  String clientId = 'prototype-demo',
  int reviewRound = 1,
  List<String> feedbackIds = const ['feedback-1'],
  IntendedScope? scope,
  String proposedBy = 'opencode',
  ChangeClassification proposed = ChangeClassification.contractImpacting,
}) {
  return RefinementBatch.draft(
    id: id,
    clientId: clientId,
    reviewRound: reviewRound,
    feedbackIds: feedbackIds,
    intendedScope: scope ?? IntendedScope(screens: const ['commerce.home']),
    proposedBy: proposedBy,
    proposed: proposed,
    createdBy: 'reviewer-123',
    createdAt: t0,
  );
}

RefinementBatch confirmedBatch({
  ChangeClassification confirmed = ChangeClassification.implementationOnly,
  IntendedScope? scope,
}) {
  return draftBatch(scope: scope).confirmClassification(
    actorId: 'reviewer-123',
    at: t1,
    confirmed: confirmed,
  );
}

RefinementBatch readyBatch({
  ChangeClassification confirmed = ChangeClassification.implementationOnly,
}) {
  return confirmedBatch(confirmed: confirmed)
      .markReady(actorId: 'reviewer-123', at: t1);
}

RefinementBatch inProgressBatch() =>
    readyBatch().start(actorId: 'opencode', at: t1);

BatchValidation passedValidation() => BatchValidation(
      status: BatchValidationStatus.passed,
      checks: const [
        ValidationCheck(name: 'flutter test test/review', passed: true, details: 'ok'),
      ],
    );

BatchValidation failedValidation() => BatchValidation(
      status: BatchValidationStatus.failed,
      checks: const [
        ValidationCheck(name: 'flutter test test/review', passed: false, details: 'boom'),
      ],
    );

BatchExecution execution() => BatchExecution(
      agent: 'opencode',
      model: 'deepseek-v4-pro',
      commitSha: 'abc123',
      filesChanged: const ['lib/review/refinement_batch.dart'],
    );

void main() {
  group('wire values', () {
    test('statuses round-trip through stable wire values', () {
      for (final status in RefinementBatchStatus.values) {
        expect(refinementBatchStatusFromWire(refinementBatchStatusToWire(status)),
            status);
      }
      expect(refinementBatchStatusToWire(RefinementBatchStatus.inProgress),
          'in_progress');
      expect(refinementBatchStatusToWire(RefinementBatchStatus.readyForReview),
          'ready_for_review');
      expect(() => refinementBatchStatusFromWire('approved'), throwsFormatException);
    });

    test('classifications round-trip through stable wire values', () {
      for (final value in ChangeClassification.values) {
        expect(changeClassificationFromWire(changeClassificationToWire(value)),
            value);
      }
      expect(changeClassificationToWire(ChangeClassification.implementationOnly),
          'implementation_only');
      expect(changeClassificationToWire(ChangeClassification.contractImpacting),
          'contract_impacting');
      expect(() => changeClassificationFromWire('cosmetic'), throwsFormatException);
    });

    test('validation statuses and event types round-trip', () {
      for (final value in BatchValidationStatus.values) {
        expect(batchValidationStatusFromWire(batchValidationStatusToWire(value)),
            value);
      }
      for (final value in RefinementBatchEventType.values) {
        expect(
          refinementBatchEventTypeFromWire(refinementBatchEventTypeToWire(value)),
          value,
        );
      }
      expect(() => batchValidationStatusFromWire('unknown'), throwsFormatException);
      expect(() => refinementBatchEventTypeFromWire('unknown'), throwsFormatException);
    });
  });

  group('draft invariants', () {
    test('requires a non-empty id, client, and positive round', () {
      expect(() => draftBatch(id: '  '), throwsFormatException);
      expect(() => draftBatch(clientId: '  '), throwsFormatException);
      expect(() => draftBatch(reviewRound: 0), throwsFormatException);
    });

    test('requires at least one linked feedback id', () {
      expect(() => draftBatch(feedbackIds: const []), throwsFormatException);
    });

    test('requires a non-empty intended scope', () {
      expect(
        () => draftBatch(scope: IntendedScope(screens: const [], sections: const [])),
        throwsFormatException,
      );
    });

    test('normalizes and freezes the collections', () {
      final batch = draftBatch(
        feedbackIds: const ['feedback-2', 'feedback-1'],
        scope: IntendedScope(
          screens: const ['commerce.home', 'commerce.plp'],
          sections: const ['plp.product-grid'],
        ),
      );

      expect(batch.feedbackIds, ['feedback-1', 'feedback-2']);
      expect(batch.intendedScope.screens, ['commerce.home', 'commerce.plp']);
      expect(batch.intendedScope.sections, ['plp.product-grid']);
      expect(() => batch.feedbackIds.add('x'), throwsUnsupportedError);
      expect(() => batch.evidence.add('x'), throwsUnsupportedError);
      expect(() => batch.history.add(batch.history.first), throwsUnsupportedError);
    });

    test('starts with a single created history event', () {
      final batch = draftBatch();
      expect(batch.history, hasLength(1));
      expect(batch.history.single.type, RefinementBatchEventType.created);
      expect(batch.history.single.actorId, 'reviewer-123');
      expect(batch.status, RefinementBatchStatus.draft);
      expect(batch.changeClassification.isConfirmed, isFalse);
    });
  });

  group('lifecycle transitions', () {
    test('draft -> ready -> in_progress -> ready_for_review -> completed', () {
      final ready = readyBatch();
      expect(ready.status, RefinementBatchStatus.ready);
      expect(ready.changeClassification.confirmed,
          ChangeClassification.implementationOnly);

      final started = ready.start(actorId: 'opencode', at: t1, agent: 'opencode');
      expect(started.status, RefinementBatchStatus.inProgress);
      expect(started.execution.agent, 'opencode');

      final reviewed = started.recordValidation(
        actorId: 'opencode',
        at: t2,
        validation: passedValidation(),
        execution: execution(),
        evidence: const ['screenshot-1'],
      );
      expect(reviewed.status, RefinementBatchStatus.readyForReview);
      expect(reviewed.validation.status, BatchValidationStatus.passed);
      expect(reviewed.evidence, ['screenshot-1']);

      final completed = reviewed.complete(actorId: 'reviewer-123', at: t2);
      expect(completed.status, RefinementBatchStatus.completed);
      expect(completed.history.map((event) => event.type), [
        RefinementBatchEventType.created,
        RefinementBatchEventType.classificationConfirmed,
        RefinementBatchEventType.markedReady,
        RefinementBatchEventType.started,
        RefinementBatchEventType.validationPassed,
        RefinementBatchEventType.completed,
      ]);
    });

    test('in_progress -> validation_failed -> in_progress retry', () {
      final failed = inProgressBatch().recordValidation(
        actorId: 'opencode',
        at: t1,
        validation: failedValidation(),
        execution: execution(),
      );
      expect(failed.status, RefinementBatchStatus.validationFailed);
      expect(failed.validation.status, BatchValidationStatus.failed);

      final retried = failed.start(actorId: 'opencode', at: t2);
      expect(retried.status, RefinementBatchStatus.inProgress);
      expect(retried.validation.status, BatchValidationStatus.pending);
      // Prior checks are retained for audit.
      expect(retried.validation.checks, hasLength(1));
    });

    test('validation_failed -> completed is legal', () {
      final failed = inProgressBatch().recordValidation(
        actorId: 'opencode',
        at: t1,
        validation: failedValidation(),
        execution: execution(),
      );
      final completed = failed.complete(actorId: 'reviewer-123', at: t2);
      expect(completed.status, RefinementBatchStatus.completed);
    });

    test('illegal transitions throw InvalidBatchTransition', () {
      expect(
        () => readyBatch().complete(actorId: 'reviewer-123', at: t1),
        throwsA(isA<InvalidBatchTransition>()),
      );
      expect(
        () => inProgressBatch().markReady(actorId: 'reviewer-123', at: t1),
        throwsA(isA<InvalidBatchTransition>()),
      );
      expect(
        () => draftBatch().start(actorId: 'opencode', at: t1),
        throwsA(isA<BatchNotReady>()),
      );
    });

    test('canTransition encodes exactly the legal matrix', () {
      expect(
        RefinementBatch.canTransition(
          RefinementBatchStatus.draft,
          RefinementBatchStatus.ready,
        ),
        isTrue,
      );
      expect(
        RefinementBatch.canTransition(
          RefinementBatchStatus.ready,
          RefinementBatchStatus.completed,
        ),
        isFalse,
      );
      expect(
        RefinementBatch.canTransition(
          RefinementBatchStatus.draft,
          RefinementBatchStatus.inProgress,
        ),
        isFalse,
      );
    });
  });

  group('classification confirmation and scope freezing', () {
    test('ready requires a confirmed classification', () {
      expect(
        () => draftBatch().markReady(actorId: 'reviewer-123', at: t1),
        throwsA(
          isA<ContractClassificationUnconfirmed>().having(
            (error) => error.code,
            'code',
            'contract_classification_unconfirmed',
          ),
        ),
      );
    });

    test('linked feedback and scope are frozen after ready', () {
      final ready = readyBatch();
      expect(
        () => ready.editDraft(
          actorId: 'reviewer-123',
          at: t2,
          feedbackIds: const ['feedback-2'],
        ),
        throwsA(isA<BatchScopeFrozen>()),
      );
      expect(
        () => ready.confirmClassification(
          actorId: 'reviewer-123',
          at: t2,
          confirmed: ChangeClassification.contractImpacting,
        ),
        throwsA(isA<BatchScopeFrozen>()),
      );
    });

    test('draft edits are allowed and append an edited event', () {
      final edited = draftBatch().editDraft(
        actorId: 'reviewer-123',
        at: t1,
        feedbackIds: const ['feedback-1', 'feedback-2'],
        intendedScope: IntendedScope(screens: const ['commerce.plp']),
      );
      expect(edited.feedbackIds, ['feedback-1', 'feedback-2']);
      expect(edited.intendedScope.screens, ['commerce.plp']);
      expect(edited.history.last.type, RefinementBatchEventType.edited);
    });
  });

  group('validation evidence', () {
    test('a passed result without a passed check is rejected', () {
      final batch = inProgressBatch();
      expect(
        () => batch.recordValidation(
          actorId: 'opencode',
          at: t1,
          validation: BatchValidation(status: BatchValidationStatus.passed),
          execution: execution(),
        ),
        throwsA(
          isA<BatchValidationRequired>().having(
            (error) => error.code,
            'code',
            'batch_validation_required',
          ),
        ),
      );
    });

    test('a passed result with a failing check is rejected', () {
      final batch = inProgressBatch();
      expect(
        () => batch.recordValidation(
          actorId: 'opencode',
          at: t1,
          validation: BatchValidation(
            status: BatchValidationStatus.passed,
            checks: const [
              ValidationCheck(name: 'flutter test', passed: true, details: 'ok'),
              ValidationCheck(
                name: 'flutter analyze',
                passed: false,
                details: 'issue',
              ),
            ],
          ),
          execution: execution(),
        ),
        throwsA(
          isA<BatchValidationFailed>().having(
            (error) => error.code,
            'code',
            'batch_validation_failed',
          ),
        ),
      );
    });

    test('a passed result with no checks is rejected', () {
      final batch = inProgressBatch();
      expect(
        () => batch.recordValidation(
          actorId: 'opencode',
          at: t1,
          validation: BatchValidation(status: BatchValidationStatus.passed),
          execution: execution(),
        ),
        throwsA(isA<BatchValidationRequired>()),
      );
    });

    test('a pending result is not a valid record', () {
      expect(
        () => inProgressBatch().recordValidation(
          actorId: 'opencode',
          at: t1,
          validation: BatchValidation(status: BatchValidationStatus.pending),
          execution: execution(),
        ),
        throwsA(isA<InvalidBatchTransition>()),
      );
    });

    test('recordValidation outside in_progress is rejected', () {
      expect(
        () => readyBatch().recordValidation(
          actorId: 'opencode',
          at: t1,
          validation: passedValidation(),
          execution: execution(),
        ),
        throwsA(isA<BatchNotReady>()),
      );
    });
  });

  group('completed batches are frozen', () {
    RefinementBatch completed() {
      final reviewed = inProgressBatch().recordValidation(
        actorId: 'opencode',
        at: t1,
        validation: passedValidation(),
        execution: execution(),
      );
      return reviewed.complete(actorId: 'reviewer-123', at: t2);
    }

    test('no operation is legal on a completed batch', () {
      final batch = completed();
      expect(batch.isCompleted, isTrue);
      expect(
        () => batch.editDraft(actorId: 'reviewer-123', at: t2),
        throwsA(isA<BatchAlreadyCompleted>()),
      );
      expect(
        () => batch.markReady(actorId: 'reviewer-123', at: t2),
        throwsA(isA<BatchAlreadyCompleted>()),
      );
      expect(
        () => batch.start(actorId: 'opencode', at: t2),
        throwsA(isA<BatchAlreadyCompleted>()),
      );
      expect(
        () => batch.complete(actorId: 'reviewer-123', at: t2),
        throwsA(isA<BatchAlreadyCompleted>()),
      );
    });
  });

  group('serialization', () {
    test('round-trips a completed batch deterministically', () {
      final original = inProgressBatch()
          .recordValidation(
            actorId: 'opencode',
            at: t1,
            validation: passedValidation(),
            execution: execution(),
            evidence: const ['screenshot-1'],
          )
          .complete(actorId: 'reviewer-123', at: t2);

      final json = original.toJson();
      expect(json.keys.toSet(), {
        'id',
        'client_id',
        'review_round',
        'status',
        'feedback_ids',
        'intended_scope',
        'change_classification',
        'execution',
        'validation',
        'evidence',
        'created_at',
        'updated_at',
        'history',
      });
      expect(json['status'], 'completed');
      expect(json['change_classification'], {
        'proposed_by': 'opencode',
        'proposed': 'contract_impacting',
        'confirmed_by': 'reviewer-123',
        'confirmed': 'implementation_only',
      });
      expect(RefinementBatch.fromJson(json), original);
    });

    test('rejects malformed payloads', () {
      final valid = draftBatch().toJson();

      expect(
        () => RefinementBatch.fromJson(valid..['status'] = 'approved'),
        throwsFormatException,
      );
      expect(
        () => RefinementBatch.fromJson(draftBatch().toJson()..remove('intended_scope')),
        throwsFormatException,
      );
      expect(
        () => RefinementBatch.fromJson(draftBatch().toJson()..['feedback_ids'] = 'nope'),
        throwsFormatException,
      );
      expect(
        () => RefinementBatch.fromJson(
          draftBatch().toJson()..['history'] = 'nope',
        ),
        throwsFormatException,
      );
    });

    test('rejects a persisted ready batch without confirmation', () {
      final json = draftBatch().toJson()
        ..['status'] = 'ready';
      expect(() => RefinementBatch.fromJson(json), throwsFormatException);
    });
  });

  group('value equality', () {
    test('compares every field and history', () {
      expect(draftBatch(), equals(draftBatch()));
      expect(draftBatch().hashCode, equals(draftBatch().hashCode));
      expect(draftBatch(), isNot(equals(draftBatch(id: 'batch-2'))));
      expect(
        draftBatch(),
        isNot(equals(draftBatch(feedbackIds: const ['feedback-2']))),
      );
      expect(
        readyBatch(),
        isNot(equals(readyBatch(confirmed: ChangeClassification.contractImpacting))),
      );
    });
  });
}
