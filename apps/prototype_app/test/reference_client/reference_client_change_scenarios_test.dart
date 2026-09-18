import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/approval_snapshot.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/persistence/file_approval_repository.dart';
import 'package:prototype_app/review/persistence/file_feedback_repository.dart';
import 'package:prototype_app/review/persistence/file_refinement_batch_repository.dart';
import 'package:prototype_app/review/persistence/review_persistence_layout.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/refinement_execution_result.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_domain_error.dart';
import 'package:prototype_app/review/review_repository.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/review/review_state_hash.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import 'support/reference_client_fixtures.dart';

/// Milestone F.3 — the reference client's post-approval change boundaries,
/// proven through the real C (review/approval) and C.7 (refinement) authorities:
///
/// ```text
/// ApprovalSnapshot v1
///   -> contract-impacting change
///        -> new blocking feedback -> contract-impacting refinement batch
///        -> reviewer resolve + explicit new round close
///        -> ApprovalSnapshot v2 (supersedes v1, v1 left byte-identical)
///        -> a further approval without a new round is refused
///   -> implementation-only change
///        -> refinement batch only (no review decision, no new blocker)
///        -> approved experience identity (review-state hash) is unchanged
///        -> no new approval version
/// ```
///
/// Both scenarios start from a freshly built post-Approval-v1 state and run
/// against a temp copy of the client (RF4/RF9): the file-backed repositories
/// point at `Directory.systemTemp`, so CI never mutates committed authority.
/// Determinism is asserted behaviourally (RF5). The evidence JSON is written
/// only when `REFERENCE_CHANGE_EVIDENCE_PATH` is provided, so the test never
/// writes inside the repository by default.
const reviewer = ReviewActor(
  id: 'reviewer-123',
  name: 'Rahul',
  role: ReviewRole.reviewer,
);
const agent = ReviewActor(
  id: 'opencode',
  name: 'OpenCode',
  role: ReviewRole.agent,
);
const approver = ReviewActor(
  id: 'approver-456',
  name: 'Priya',
  role: ReviewRole.approver,
);

/// Fixed 40-hex commit SHAs, so approval snapshots pin stable source commits.
const fixedSourceCommitSha = '0123456789abcdef0123456789abcdef01234567';
const secondSourceCommitSha = '89abcdef0123456789abcdef0123456789abcdef';
const contractCommitSha = 'fedcba9876543210fedcba9876543210fedcba98';
const implementationCommitSha = 'abcdef0123456789abcdef0123456789abcdef01';

/// File-backed [ReviewRepository] equivalent, writing the canonical
/// `review-state.json` artifact into a [ReviewPersistenceLayout].
final class _FileReviewRepository implements ReviewRepository {
  _FileReviewRepository({required this.layout});

  final ReviewPersistenceLayout layout;

  @override
  Future<ReviewState?> load(String clientId) async {
    final raw = await readFileOrNull(layout.reviewStateFile(clientId));
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid review state');
    }
    return ReviewState.fromJson(decoded.cast<String, dynamic>());
  }

  @override
  Future<void> save(ReviewState state) async {
    await writeFileAtomic(
      layout.reviewStateFile(state.clientId),
      '${const JsonEncoder.withIndent('  ').convert(state.toJson())}\n',
    );
  }
}

/// The temp workspace and the real C/C.7 authorities for one scenario run.
final class _ChangeHarness {
  _ChangeHarness({
    required this.reviewLayout,
    required this.runtime,
    required this.controller,
    required this.review,
  });

  final ReviewPersistenceLayout reviewLayout;
  final PrototypeRuntime runtime;
  final ReviewController controller;
  final ReviewCoordinator review;
}

/// Collects `{id, passed}` evidence entries while asserting each condition.
final class _AssertionLog {
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];

  void check(String id, bool condition) {
    entries.add({'id': id, 'passed': condition});
    expect(condition, isTrue, reason: id);
  }
}

/// Builds a temp workspace and seeds the exact F.2 post-Approval-v1 state:
/// select `b`, screen override `commerce.search -> a`, governed section
/// override `commerce.pdp/pdp.price -> a`, one blocking + one non-blocking
/// feedback, a completed implementation-only refinement batch that addresses
/// the blocker, explicit reviewer resolution, an explicit round close, and
/// ApprovalSnapshot v1.
Future<({_ChangeHarness harness, ApprovalSnapshot v1})> _buildPostApprovalV1() async {
  final tempRoot = await Directory.systemTemp.createTemp('f3-change-');
  addTearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  final reviewLayout = ReviewPersistenceLayout(clientProjectsDirectory: tempRoot);
  final runtime = loadReferenceRuntime();
  final controller = ReviewController(
    clientId: runtime.clientId,
    repository: _FileReviewRepository(layout: reviewLayout),
    runtime: runtime,
  );
  final review = ReviewCoordinator(
    controller: controller,
    feedbackRepository: FileFeedbackRepository(layout: reviewLayout),
    approvalRepository: FileApprovalRepository(layout: reviewLayout),
    refinementBatchRepository: FileRefinementBatchRepository(layout: reviewLayout),
  );

  await controller.selectDirection('b');
  await controller.setScreenDirection('commerce.search', 'a');
  await controller.setSectionDirection('commerce.pdp', 'pdp.price', 'a');

  final blocking = await review.createFeedback(
    actor: reviewer,
    id: 'feedback-blocking',
    scope: FeedbackScope.section,
    text: 'Price block spacing is off the governed 4px grid.',
    target: const FeedbackTarget(screen: 'commerce.pdp', section: 'pdp.price'),
    blocking: true,
  );
  await review.createFeedback(
    actor: reviewer,
    id: 'feedback-non-blocking',
    scope: FeedbackScope.general,
    text: 'Consider a denser footer rhythm.',
    target: const FeedbackTarget(),
    blocking: false,
  );

  await review.createDraftBatch(
    actor: reviewer,
    id: 'batch-001',
    feedbackIds: [blocking.id],
    intendedScope: IntendedScope(sections: const ['pdp.price']),
    proposed: ChangeClassification.implementationOnly,
  );
  await review.confirmBatchClassification(
    actor: reviewer,
    batchId: 'batch-001',
    confirmed: ChangeClassification.implementationOnly,
  );
  await review.markBatchReady(actor: reviewer, batchId: 'batch-001');
  await review.startBatch(
    actor: agent,
    batchId: 'batch-001',
    agent: 'opencode',
    model: 'deepseek/deepseek-v4-pro',
  );
  await review.recordBatchValidation(
    actor: agent,
    batchId: 'batch-001',
    result: RefinementExecutionResult(
      status: RefinementExecutionStatus.passed,
      commitSha: fixedSourceCommitSha,
      filesChanged: const ['lib/review/pdp_price.dart'],
      checks: const [
        ValidationCheck(name: 'flutter test', passed: true, details: 'all green'),
        ValidationCheck(name: 'flutter analyze', passed: true, details: 'no issues'),
      ],
      evidence: const ['build/visual-qa/screenshots/pdp-price.png'],
    ),
  );
  await review.completeBatch(actor: reviewer, batchId: 'batch-001');
  await review.resolveFeedback(actor: reviewer, feedbackId: blocking.id);
  await review.closeCurrentRound(actor: reviewer);

  final v1 = await review.createApproval(
    reviewer: reviewer,
    approver: approver,
    sourceCommitSha: fixedSourceCommitSha,
  );

  return (
    harness: _ChangeHarness(
      reviewLayout: reviewLayout,
      runtime: runtime,
      controller: controller,
      review: review,
    ),
    v1: v1,
  );
}

/// Scenario A — a deterministic contract-impacting change forces a new review
/// round and an immutable ApprovalSnapshot v2 that supersedes v1.
Future<({Map<String, Object?> evidence, List<Map<String, Object?>> assertions})>
    _runContractScenario() async {
  final log = _AssertionLog();
  final built = await _buildPostApprovalV1();
  final harness = built.harness;
  final v1 = built.v1;

  final v1File = harness.reviewLayout.approvalFile(harness.runtime.clientId, 1);
  final v1BytesBefore = await v1File.readAsBytes();

  final contractFeedback = await harness.review.createFeedback(
    actor: reviewer,
    id: 'feedback-contract',
    scope: FeedbackScope.section,
    text: 'The governed price experience contract changed.',
    target: const FeedbackTarget(screen: 'commerce.pdp', section: 'pdp.price'),
    blocking: true,
  );
  log.check('contract.review_round_2', harness.controller.state.reviewRound == 2);

  await harness.review.createDraftBatch(
    actor: reviewer,
    id: 'batch-contract',
    feedbackIds: [contractFeedback.id],
    intendedScope: IntendedScope(sections: const ['pdp.price']),
  );
  await harness.review.confirmBatchClassification(
    actor: reviewer,
    batchId: 'batch-contract',
    confirmed: ChangeClassification.contractImpacting,
  );
  await harness.review.markBatchReady(actor: reviewer, batchId: 'batch-contract');
  await harness.review.startBatch(
    actor: agent,
    batchId: 'batch-contract',
    agent: 'opencode',
    model: 'deepseek/deepseek-v4-pro',
  );
  await harness.review.recordBatchValidation(
    actor: agent,
    batchId: 'batch-contract',
    result: RefinementExecutionResult(
      status: RefinementExecutionStatus.passed,
      commitSha: contractCommitSha,
      filesChanged: const ['lib/review/pdp_price_contract.dart'],
      checks: const [
        ValidationCheck(name: 'flutter test', passed: true, details: 'all green'),
        ValidationCheck(name: 'flutter analyze', passed: true, details: 'no issues'),
      ],
      evidence: const ['build/visual-qa/screenshots/pdp-price-contract.png'],
    ),
  );
  await harness.review.resolveFeedback(
    actor: reviewer,
    feedbackId: contractFeedback.id,
  );
  await harness.review.completeBatch(actor: reviewer, batchId: 'batch-contract');

  // The round is not closed yet, so approval must be refused until the reviewer
  // explicitly closes it.
  var closeRequired = false;
  try {
    await harness.review.createApproval(
      reviewer: reviewer,
      approver: approver,
      sourceCommitSha: secondSourceCommitSha,
    );
  } on ApprovalNotEligible {
    closeRequired = true;
  }
  log.check('contract.close_required_before_approval', closeRequired);

  await harness.review.closeCurrentRound(actor: reviewer);
  final v2 = await harness.review.createApproval(
    reviewer: reviewer,
    approver: approver,
    sourceCommitSha: secondSourceCommitSha,
  );

  final v1BytesAfter = await v1File.readAsBytes();
  final v1Immutable = _bytesEqual(v1BytesBefore, v1BytesAfter);
  final hashDiffers = v2.reviewStateHash != v1.reviewStateHash;
  final shaDiffers = v2.sourceCommitSha != v1.sourceCommitSha;

  log.check('contract.v1_immutable', v1Immutable);
  log.check('contract.v2_version_2', v2.version == 2);
  log.check('contract.v2_supersedes_1', v2.supersedes == 1);
  log.check('contract.v2_review_round_2', v2.reviewRound == 2);
  log.check('contract.v2_review_round_gt_v1', v2.reviewRound > v1.reviewRound);
  log.check('contract.v2_hash_sha256', v2.reviewStateHash.startsWith('sha256:'));
  log.check('contract.v2_hash_differs', hashDiffers);
  log.check('contract.v2_source_sha_differs', shaDiffers);

  final approvals = await harness.review.listApprovals();
  log.check(
    'contract.list_approvals_two_ascending',
    approvals.length == 2 &&
        approvals[0].version == 1 &&
        approvals[1].version == 2,
  );

  var refused = false;
  try {
    await harness.review.createApproval(
      reviewer: reviewer,
      approver: approver,
      sourceCommitSha: secondSourceCommitSha,
    );
  } on ContractImpactRequiresNewRound {
    refused = true;
  }
  log.check('contract.third_approval_refused', refused);
  log.check(
    'contract.no_v1_mutation',
    _bytesEqual(v1BytesBefore, await v1File.readAsBytes()),
  );

  return (
    evidence: <String, Object?>{
      'review_rounds': harness.controller.state.reviewRound,
      'approval_versions': [v1.version, v2.version],
      'v1_immutable': v1Immutable,
      'v2_version': v2.version,
      'v2_supersedes': v2.supersedes,
      'v2_review_round': v2.reviewRound,
      'v2_hash_differs': hashDiffers,
      'v2_source_sha_differs': shaDiffers,
      'third_approval_refused': refused,
    },
    assertions: log.entries,
  );
}

/// Scenario B — a deterministic implementation-only change preserves the
/// approved experience identity and therefore creates no new approval version.
Future<({Map<String, Object?> evidence, List<Map<String, Object?>> assertions})>
    _runImplementationScenario() async {
  final log = _AssertionLog();
  final built = await _buildPostApprovalV1();
  final harness = built.harness;
  final v1 = built.v1;
  final v1Hash = v1.reviewStateHash;

  // `createDraftBatch` is called with no explicit classification, so the
  // proposed class defaults to the safer contract-impacting (uncertainty rule).
  final draft = await harness.review.createDraftBatch(
    actor: reviewer,
    id: 'batch-implementation',
    feedbackIds: const ['feedback-non-blocking'],
    intendedScope: IntendedScope(screens: const ['commerce.pdp']),
  );
  await harness.review.confirmBatchClassification(
    actor: reviewer,
    batchId: 'batch-implementation',
    confirmed: ChangeClassification.implementationOnly,
  );
  await harness.review.markBatchReady(
    actor: reviewer,
    batchId: 'batch-implementation',
  );
  await harness.review.startBatch(
    actor: agent,
    batchId: 'batch-implementation',
    agent: 'opencode',
    model: 'deepseek/deepseek-v4-pro',
  );
  await harness.review.recordBatchValidation(
    actor: agent,
    batchId: 'batch-implementation',
    result: RefinementExecutionResult(
      status: RefinementExecutionStatus.passed,
      commitSha: implementationCommitSha,
      filesChanged: const ['lib/review/pdp_layout.dart'],
      checks: const [
        ValidationCheck(name: 'flutter test', passed: true, details: 'all green'),
      ],
      evidence: const ['build/visual-qa/screenshots/pdp-layout.png'],
    ),
  );
  await harness.review.completeBatch(
    actor: reviewer,
    batchId: 'batch-implementation',
  );

  final completed = await harness.review.loadBatch('batch-implementation');
  final approvals = await harness.review.listApprovals();
  final hashUnchanged =
      reviewStateHash(harness.controller.state) == v1Hash;
  final stillEligible = await harness.review.isEligibleForApproval();
  final classification =
      completed?.changeClassification.confirmed == ChangeClassification.implementationOnly;
  final defaultClassification = draft.changeClassification.proposed;

  log.check('implementation.approval_count_1', approvals.length == 1);
  log.check('implementation.review_round_1', harness.controller.state.reviewRound == 1);
  log.check('implementation.classification_confirmed_implementation_only', classification);
  log.check('implementation.approved_hash_unchanged', hashUnchanged);
  log.check('implementation.still_eligible', stillEligible);
  log.check(
    'implementation.default_classification_contract_impacting',
    defaultClassification == ChangeClassification.contractImpacting,
  );

  return (
    evidence: <String, Object?>{
      'approval_versions': [approvals.single.version],
      'review_round': harness.controller.state.reviewRound,
      'classification': changeClassificationToWire(
        completed!.changeClassification.confirmed!,
      ),
      'approved_hash_unchanged': hashUnchanged,
      'still_eligible': stillEligible,
      'default_classification': changeClassificationToWire(defaultClassification),
    },
    assertions: log.entries,
  );
}

void main() {
  test('reference client post-approval change boundaries', () async {
    final contract = await _runContractScenario();
    final implementation = await _runImplementationScenario();

    final evidence = <String, Object?>{
      'client_id': referenceClientId,
      'fixture_version': 1,
      'scenario_ids': const [
        'contract-change-reapproval',
        'implementation-only-change',
      ],
      'source_commit_sha': secondSourceCommitSha,
      'contract_change': contract.evidence,
      'implementation_only': implementation.evidence,
      'assertions': <Map<String, Object?>>[
        ...contract.assertions,
        ...implementation.assertions,
      ],
    };

    const evidencePath = String.fromEnvironment('REFERENCE_CHANGE_EVIDENCE_PATH');
    if (evidencePath.isNotEmpty) {
      final output = _resolveEvidenceFile(evidencePath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
      );
    }
  });
}

/// Resolves the evidence output path against the repository root.
///
/// `flutter test` runs from the package directory (`apps/prototype_app`), so a
/// caller-supplied relative path is anchored at the repository root; any leading
/// `..` segments are normalized away. This keeps the evidence file inside the
/// repository exactly when (and where) a caller asks for it, and never writes
/// anywhere by default.
File _resolveEvidenceFile(String raw) {
  final direct = File(raw);
  if (direct.isAbsolute) {
    return direct;
  }
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/client-projects').existsSync() &&
        Directory('${dir.path}/apps').existsSync()) {
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  var relative = raw;
  while (relative.startsWith('../') || relative.startsWith('..\\')) {
    relative = relative.substring(3);
  }
  return File('${dir.path}/$relative');
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
