import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/approval_repository.dart';
import 'package:prototype_app/review/approval_snapshot.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
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

ApprovalSnapshot snapshot(int version, {String clientId = 'prototype-demo'}) {
  return ApprovalSnapshot(
    version: version,
    clientId: clientId,
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
  late ApprovalRepository repository;

  setUp(() {
    repository = MemoryApprovalRepository();
  });

  test('list returns an empty list for an unknown client', () async {
    expect(await repository.list('missing'), isEmpty);
  });

  test('create then list round-trips the snapshot', () async {
    final value = snapshot(1);

    await repository.create('prototype-demo', value);

    expect(await repository.list('prototype-demo'), [value]);
  });

  test('rejects a duplicate version without overwriting the original',
      () async {
    final original = snapshot(1);
    await repository.create('prototype-demo', original);

    final duplicate = ApprovalSnapshot(
      version: 1,
      clientId: 'prototype-demo',
      reviewRound: 9,
      reviewedBy: reviewer,
      approvedBy: approver,
      approvedAt: DateTime.utc(2026, 9, 18),
      selectedDirection: 'b',
      screenSelections: const {},
      unresolvedNonBlockingFeedbackIds: const [],
      sourceCommitSha: 'different',
      reviewStateHash: 'sha256:other',
    );

    await expectLater(
      () => repository.create('prototype-demo', duplicate),
      throwsA(
        isA<ApprovalVersionConflict>()
            .having((error) => error.code, 'code', 'approval_version_conflict'),
      ),
    );

    expect(await repository.list('prototype-demo'), [original]);
  });

  test('rejects an out-of-order version to keep history monotonic', () async {
    await repository.create('prototype-demo', snapshot(2));

    await expectLater(
      () => repository.create('prototype-demo', snapshot(1)),
      throwsA(isA<ApprovalVersionConflict>()),
    );
    expect((await repository.list('prototype-demo')).map((s) => s.version), [2]);
  });

  test('appends versions and lists them in ascending order', () async {
    await repository.create('prototype-demo', snapshot(1));
    await repository.create('prototype-demo', snapshot(2));

    expect(
      (await repository.list('prototype-demo')).map((s) => s.version).toList(),
      [1, 2],
    );
  });

  test('keeps distinct clients isolated', () async {
    await repository.create('alpha', snapshot(1, clientId: 'alpha'));
    await repository.create('beta', snapshot(1, clientId: 'beta'));

    expect((await repository.list('alpha')).single.clientId, 'alpha');
    expect((await repository.list('beta')).single.clientId, 'beta');
  });
}
