import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/approval_snapshot.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/persistence/file_approval_repository.dart';
import 'package:prototype_app/review/persistence/file_feedback_repository.dart';
import 'package:prototype_app/review/persistence/file_refinement_batch_repository.dart';
import 'package:prototype_app/review/persistence/file_review_index_repository.dart';
import 'package:prototype_app/review/persistence/review_index.dart';
import 'package:prototype_app/review/persistence/review_persistence_layout.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_domain_error.dart';

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

FeedbackRecord feedback(String id, {bool blocking = true}) {
  return FeedbackRecord(
    id: id,
    scope: FeedbackScope.general,
    text: 'note $id',
    status: FeedbackStatus.open,
    blocking: blocking,
    createdRound: 1,
    target: const FeedbackTarget(),
    history: [
      FeedbackEvent(
        type: FeedbackEventType.created,
        actorId: 'reviewer-123',
        at: DateTime.utc(2026, 9, 17, 10),
        round: 1,
      ),
    ],
  );
}

ApprovalSnapshot approval(int version) {
  return ApprovalSnapshot(
    version: version,
    clientId: 'prototype-demo',
    reviewRound: version,
    reviewedBy: reviewer,
    approvedBy: approver,
    approvedAt: DateTime.utc(2026, 9, 17, 12, 30),
    selectedDirection: 'a',
    screenSelections: const {},
    unresolvedNonBlockingFeedbackIds: const [],
    sourceCommitSha: 'abc123',
    reviewStateHash: 'sha256:deadbeef',
    supersedes: version > 1 ? version - 1 : null,
  );
}

void main() {
  late Directory tempRoot;
  late ReviewPersistenceLayout layout;
  late FileFeedbackRepository feedbackRepository;
  late FileApprovalRepository approvalRepository;
  late FileReviewIndexRepository indexRepository;
  late FileRefinementBatchRepository batchRepository;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('review-files-');
    layout = ReviewPersistenceLayout(clientProjectsDirectory: tempRoot);
    feedbackRepository = FileFeedbackRepository(layout: layout);
    approvalRepository = FileApprovalRepository(layout: layout);
    indexRepository = FileReviewIndexRepository(layout: layout);
    batchRepository = FileRefinementBatchRepository(layout: layout);
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  String normalize(String path) => path.replaceAll('\\', '/');

  group('deterministic paths', () {
    test('derive the documented review layout', () {
      expect(
        normalize(layout.feedbackFile('prototype-demo', 'feedback-1').path),
        endsWith('/prototype-demo/review/feedback/feedback-1.json'),
      );
      expect(
        normalize(layout.reviewIndexFile('prototype-demo').path),
        endsWith('/prototype-demo/review/review-index.json'),
      );
      expect(
        normalize(layout.refinementBatchFile('prototype-demo', 'batch-7').path),
        endsWith('/prototype-demo/review/refinement-batches/batch-7.json'),
      );
      expect(
        normalize(layout.approvalFile('prototype-demo', 1).path),
        endsWith('/prototype-demo/review/approvals/approval-v1.json'),
      );
    });
  });

  group('file feedback repository', () {
    test('stores stable feedback file identity and reads it back', () async {
      final record = feedback('feedback-1');
      await feedbackRepository.create('prototype-demo', record);

      final file = layout.feedbackFile('prototype-demo', 'feedback-1');
      expect(file.existsSync(), isTrue);

      expect(
        await feedbackRepository.load('prototype-demo', 'feedback-1'),
        record,
      );
      expect(
        await feedbackRepository.load('prototype-demo', 'missing'),
        isNull,
      );
    });

    test('lists records in deterministic id order', () async {
      await feedbackRepository.create('prototype-demo', feedback('feedback-3'));
      await feedbackRepository.create('prototype-demo', feedback('feedback-1'));

      expect(
        (await feedbackRepository.list('prototype-demo')).map((r) => r.id),
        ['feedback-1', 'feedback-3'],
      );
    });

    test('rejects a duplicate id and keeps the original', () async {
      final original = feedback('feedback-1', blocking: true);
      await feedbackRepository.create('prototype-demo', original);

      await expectLater(
        () => feedbackRepository.create(
          'prototype-demo',
          feedback('feedback-1', blocking: false),
        ),
        throwsStateError,
      );
      expect(
        await feedbackRepository.load('prototype-demo', 'feedback-1'),
        original,
      );
    });

    test('rejects a stale replacement without overwriting', () async {
      final current = feedback('feedback-1', blocking: true);
      await feedbackRepository.create('prototype-demo', current);

      await expectLater(
        () => feedbackRepository.replace(
          'prototype-demo',
          current.copyWith(blocking: false),
          current,
        ),
        throwsStateError,
      );
      expect(
        await feedbackRepository.load('prototype-demo', 'feedback-1'),
        current,
      );

      final next = current.copyWith(blocking: false);
      await feedbackRepository.replace('prototype-demo', current, next);
      expect(
        await feedbackRepository.load('prototype-demo', 'feedback-1'),
        next,
      );
    });
  });

  group('file approval repository (create-only)', () {
    test('writes approval-v1.json and refuses to overwrite it', () async {
      await approvalRepository.create('prototype-demo', approval(1));
      final file = layout.approvalFile('prototype-demo', 1);
      expect(file.existsSync(), isTrue);

      final contentsBefore = await file.readAsString();
      final decoded = jsonDecode(contentsBefore);
      expect((decoded as Map)['approval_version'], 1);

      await expectLater(
        () => approvalRepository.create('prototype-demo', approval(1)),
        throwsA(
          isA<ApprovalVersionConflict>().having(
            (error) => error.code,
            'code',
            'approval_version_conflict',
          ),
        ),
      );
      expect(await file.readAsString(), contentsBefore);
    });

    test('appends approval-v2 without touching v1', () async {
      await approvalRepository.create('prototype-demo', approval(1));
      final v1 = await layout.approvalFile('prototype-demo', 1).readAsString();

      await approvalRepository.create('prototype-demo', approval(2));

      expect(layout.approvalFile('prototype-demo', 2).existsSync(), isTrue);
      expect(await layout.approvalFile('prototype-demo', 1).readAsString(), v1);
      expect(
        (await approvalRepository.list('prototype-demo')).map((s) => s.version),
        [1, 2],
      );
    });
  });

  group('operational index', () {
    test('saves and loads atomically', () async {
      final index = ReviewIndex(
        clientId: 'prototype-demo',
        reviewRound: 2,
        feedbackIds: const ['feedback-1', 'feedback-2'],
        batchIds: const ['batch-1'],
        approvalVersions: const [1],
      );

      await indexRepository.save(index);

      expect(await indexRepository.load('prototype-demo'), index);
      expect(await indexRepository.load('other-client'), isNull);
    });

    test('rebuilds a missing index from immutable records', () async {
      await feedbackRepository.create('prototype-demo', feedback('feedback-1'));
      await approvalRepository.create('prototype-demo', approval(1));
      await batchRepository.create(
        'prototype-demo',
        'batch-1',
        <String, Object?>{'id': 'batch-1'},
      );

      final rebuilt = await indexRepository.loadOrRebuild('prototype-demo');

      expect(rebuilt.feedbackIds, ['feedback-1']);
      expect(rebuilt.batchIds, ['batch-1']);
      expect(rebuilt.approvalVersions, [1]);
      expect(rebuilt.currentApprovalVersion, 1);
      // Recovery persists the rebuilt index.
      expect(await indexRepository.load('prototype-demo'), rebuilt);
    });

    test('recovers when an immutable record exists but the index is stale',
        () async {
      await indexRepository.save(
        ReviewIndex(clientId: 'prototype-demo', reviewRound: 1),
      );
      // A new immutable record is written but the index update "failed".
      await feedbackRepository.create('prototype-demo', feedback('feedback-1'));

      final recovered = await indexRepository.loadOrRebuild('prototype-demo');

      expect(recovered.feedbackIds, ['feedback-1']);
      expect(await indexRepository.load('prototype-demo'), recovered);
    });
  });

  group('refinement batch adapter skeleton', () {
    test('stores stable batch file identity and lists ids', () async {
      await batchRepository.create(
        'prototype-demo',
        'batch-1',
        <String, Object?>{'id': 'batch-1', 'status': 'draft'},
      );

      expect(
        await batchRepository.load('prototype-demo', 'batch-1'),
        {'id': 'batch-1', 'status': 'draft'},
      );
      expect(await batchRepository.listIds('prototype-demo'), ['batch-1']);
      await expectLater(
        () => batchRepository.create(
          'prototype-demo',
          'batch-1',
          <String, Object?>{'id': 'batch-1'},
        ),
        throwsStateError,
      );
    });
  });
}
