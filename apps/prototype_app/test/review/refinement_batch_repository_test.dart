import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/persistence/file_refinement_batch_repository.dart';
import 'package:prototype_app/review/persistence/review_persistence_layout.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/refinement_batch_repository.dart';

RefinementBatch batch(String id, {int round = 1}) {
  return RefinementBatch.draft(
    id: id,
    clientId: 'prototype-demo',
    reviewRound: round,
    feedbackIds: const ['feedback-1'],
    intendedScope: IntendedScope(screens: const ['commerce.home']),
    proposedBy: 'opencode',
    proposed: ChangeClassification.contractImpacting,
    createdBy: 'reviewer-123',
    createdAt: DateTime.utc(2026, 9, 17, 10),
  );
}

void runRepositoryContract(
  String label,
  RefinementBatchRepository Function() build,
) {
  group('$label repository contract', () {
    test('create/load/list round-trip in deterministic order', () async {
      final repository = build();
      await repository.create('prototype-demo', batch('batch-2'));
      await repository.create('prototype-demo', batch('batch-1'));

      expect(await repository.load('prototype-demo', 'batch-1'), batch('batch-1'));
      expect(await repository.load('prototype-demo', 'missing'), isNull);
      expect(
        (await repository.list('prototype-demo')).map((value) => value.id),
        ['batch-1', 'batch-2'],
      );
      expect(await repository.list('other-client'), isEmpty);
    });

    test('rejects a duplicate id and keeps the original', () async {
      final repository = build();
      final original = batch('batch-1');
      await repository.create('prototype-demo', original);

      await expectLater(
        () => repository.create('prototype-demo', batch('batch-1', round: 2)),
        throwsStateError,
      );
      expect(await repository.load('prototype-demo', 'batch-1'), original);
    });

    test('rejects a stale replacement without overwriting', () async {
      final repository = build();
      final current = batch('batch-1');
      await repository.create('prototype-demo', current);

      final stale = current.copyWith(updatedAt: DateTime.utc(2026, 9, 17, 11));
      await expectLater(
        () => repository.replace('prototype-demo', stale, current),
        throwsStateError,
      );
      expect(await repository.load('prototype-demo', 'batch-1'), current);

      final next = current.copyWith(updatedAt: DateTime.utc(2026, 9, 17, 12));
      await repository.replace('prototype-demo', current, next);
      expect(await repository.load('prototype-demo', 'batch-1'), next);
    });
  });
}

void main() {
  runRepositoryContract('memory', MemoryRefinementBatchRepository.new);

  group('file-backed repository', () {
    late Directory tempRoot;
    late ReviewPersistenceLayout layout;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('refinement-batches-');
      layout = ReviewPersistenceLayout(clientProjectsDirectory: tempRoot);
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('uses the documented deterministic batch path', () async {
      final repository = FileRefinementBatchRepository(layout: layout);
      await repository.create('prototype-demo', batch('batch-7'));

      final path = layout.refinementBatchFile('prototype-demo', 'batch-7').path
          .replaceAll('\\', '/');
      expect(path, endsWith('/prototype-demo/review/refinement-batches/batch-7.json'));
    });
  });
}
