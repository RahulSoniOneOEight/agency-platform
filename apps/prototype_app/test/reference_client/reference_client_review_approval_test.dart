import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/persistence/file_qa_finding_repository.dart';
import 'package:prototype_app/qa/persistence/file_qa_run_repository.dart';
import 'package:prototype_app/qa/persistence/qa_persistence_layout.dart';
import 'package:prototype_app/qa/qa_coordinator.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/qa/visual_qa_provider.dart';
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
import 'package:prototype_app/review/visual_attachment.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import 'support/reference_client_fixtures.dart';

/// Milestone F.2 — the canonical reference-client journey through the real
/// C (review/approval) and D (automated visual QA) authorities:
///
/// ```text
/// Compare / Select / Mix
///   -> blocking + non-blocking feedback + visual annotation
///   -> refinement batch (addressed, never auto-resolved)
///   -> explicit reviewer resolution + explicit round close
///   -> ApprovalSnapshot v1 (immutable, hash-pinned)
///   -> automated visual QA finding -> triage -> explicit promotion
/// ```
///
/// The journey runs against a temp copy of the client (RF4/RF9): the file-backed
/// repositories point at `Directory.systemTemp`, so CI never mutates committed
/// authority. Determinism is asserted behaviourally (RF5). The evidence JSON is
/// written only when `REFERENCE_EVIDENCE_PATH` is provided, so the test never
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

/// A fixed 40-hex source commit, so the approval snapshot pins a stable SHA.
const fixedSourceCommitSha = '0123456789abcdef0123456789abcdef01234567';

const captureId =
    'sha256:4187fa0a2878b8298f57f293c933c880520b2014ff1279c00d029c566e16ce44';

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

Map<String, Object?> _runtimeSnapshot(PrototypeRuntime runtime) => {
      'directions': {
        for (final entry in runtime.directions.entries)
          entry.key: {
            'patterns': List<String>.from(entry.value.patterns),
          },
      },
      'directionThemes': runtime.directionThemes.keys.toList()..sort(),
      'themeColors': runtime.theme.colors.keys.toList()..sort(),
    };

Map<String, Object?> _feedbackRef(FeedbackRecord record) => {
      'id': record.id,
      'scope': feedbackScopeToWire(record.scope),
      'status': feedbackStatusToWire(record.status),
      'blocking': record.blocking,
      'target': record.target.toJson(),
      'origin_qa_finding_id': record.originQaFindingId,
      'history_types': [
        for (final event in record.history) feedbackEventTypeToWire(event.type),
      ],
    };

Map<String, Object?> _visualRef(FeedbackRecord record) {
  final attachment = record.visualAttachment!;
  return {
    'id': record.id,
    'status': feedbackStatusToWire(record.status),
    'screenshot_ref': attachment.screenshotRef,
    'screen': attachment.screenId,
    'section': attachment.sectionId,
    'effective_direction': attachment.effectiveDirection,
  };
}

void main() {
  late Directory tempRoot;
  late QaPersistenceLayout qaLayout;
  late ReviewPersistenceLayout reviewLayout;
  late PrototypeRuntime runtime;
  late ReviewController controller;
  late ReviewCoordinator review;
  late QaCoordinator qa;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('f2-review-approval-');
    qaLayout = QaPersistenceLayout(clientProjectsDirectory: tempRoot);
    reviewLayout = ReviewPersistenceLayout(clientProjectsDirectory: tempRoot);
    runtime = loadReferenceRuntime();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: _FileReviewRepository(layout: reviewLayout),
      runtime: runtime,
    );
    review = ReviewCoordinator(
      controller: controller,
      feedbackRepository: FileFeedbackRepository(layout: reviewLayout),
      approvalRepository: FileApprovalRepository(layout: reviewLayout),
      refinementBatchRepository:
          FileRefinementBatchRepository(layout: reviewLayout),
    );
    qa = QaCoordinator(
      findings: FileQaFindingRepository(layout: qaLayout),
      review: review,
      runs: FileQaRunRepository(layout: qaLayout),
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('reference client review -> approval v1 -> QA journey', () async {
    final assertions = <Map<String, Object?>>[];
    void check(String id, bool condition) {
      assertions.add({'id': id, 'passed': condition});
      expect(condition, isTrue, reason: id);
    }

    // --- Read-only baseline (item 7) ---------------------------------------
    final bundleBytesBefore = File(referenceBundlePath).readAsBytesSync();
    final runtimeBefore = jsonEncode(_runtimeSnapshot(runtime));

    // --- 1. Compare / Select / Mix ----------------------------------------
    await controller.selectDirection('b');
    await controller.setScreenDirection('commerce.search', 'a');
    await controller.setSectionDirection('commerce.pdp', 'pdp.price', 'a');

    check('mix.selected_direction_b', controller.state.selectedDirection == 'b');
    check(
      'mix.screen_override_search_a',
      controller.state.screenSelections['commerce.search']?.direction == 'a',
    );
    check(
      'mix.section_override_pdp_price_a',
      controller.state.screenSelections['commerce.pdp']
              ?.sections['pdp.price'] ==
          'a',
    );
    check('mix.state_version_2', controller.state.toJson()['version'] == 2);

    final persistedRaw =
        await reviewLayout.reviewStateFile(runtime.clientId).readAsString();
    final persisted = ReviewState.fromJson(
      (jsonDecode(persistedRaw) as Map).cast<String, dynamic>(),
    );
    check('mix.persisted_selected_direction_b', persisted.selectedDirection == 'b');
    check(
      'mix.persisted_screen_override_search_a',
      persisted.screenSelections['commerce.search']?.direction == 'a',
    );
    check(
      'mix.persisted_section_override_pdp_price_a',
      persisted.screenSelections['commerce.pdp']?.sections['pdp.price'] == 'a',
    );

    // --- 2. Feedback (blocking, non-blocking, visual annotation) -----------
    final blocking = await review.createFeedback(
      actor: reviewer,
      id: 'feedback-blocking',
      scope: FeedbackScope.section,
      text: 'Price block spacing is off the governed 4px grid.',
      target: const FeedbackTarget(
        screen: 'commerce.pdp',
        section: 'pdp.price',
      ),
      blocking: true,
    );
    check(
      'feedback.blocking_sets_needs_revision',
      controller.state.status == ReviewStatus.needsRevision,
    );

    final nonBlocking = await review.createFeedback(
      actor: reviewer,
      id: 'feedback-non-blocking',
      scope: FeedbackScope.general,
      text: 'Consider a denser footer rhythm.',
      target: const FeedbackTarget(),
      blocking: false,
    );

    final visual = await review.createFeedback(
      actor: reviewer,
      id: 'feedback-visual',
      scope: FeedbackScope.visualAnnotation,
      text: 'The price rule overlaps the container edge.',
      target: const FeedbackTarget(),
      blocking: false,
      visualAttachment: VisualAttachment(
        screenshotRef: captureId,
        viewportWidth: 390,
        viewportHeight: 844,
        clientId: runtime.clientId,
        reviewRound: controller.state.reviewRound,
        screenId: 'commerce.pdp',
        effectiveDirection: 'b',
        sourceCommitSha: fixedSourceCommitSha,
        annotation: NormalizedRect(x: 0.1, y: 0.4, width: 0.6, height: 0.1),
        providerName: 'fixture',
        externalRef: 'fixture://pdp-price',
        sectionId: 'pdp.price',
      ),
    );

    for (final record in [blocking, nonBlocking, visual]) {
      check(
        'feedback.${record.id}_append_only_created_history',
        record.history.length == 1 &&
            record.history.first.type == FeedbackEventType.created,
      );
    }
    check('feedback.non_blocking_does_not_block', nonBlocking.blocking == false);

    final blockers = await review.blockingUnresolved();
    check(
      'feedback.blocking_unresolved_exactly_blocking',
      blockers.length == 1 && blockers.single.id == blocking.id,
    );

    // --- 3. Refinement ------------------------------------------------------
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
          ValidationCheck(
            name: 'flutter analyze',
            passed: true,
            details: 'no issues',
          ),
        ],
        evidence: const ['build/visual-qa/screenshots/pdp-price.png'],
      ),
    );

    final addressed = await review.loadFeedback(blocking.id);
    check(
      'refinement.blocking_addressed_not_resolved',
      addressed?.status == FeedbackStatus.addressed,
    );

    // Approval is blocked while the blocker is unresolved (addressed != resolved).
    check(
      'approval.ineligible_while_blocking_unresolved',
      (await review.isEligibleForApproval()) == false,
    );
    await expectLater(
      review.createApproval(
        reviewer: reviewer,
        approver: approver,
        sourceCommitSha: fixedSourceCommitSha,
      ),
      throwsA(isA<ApprovalNotEligible>()),
    );
    check('approval.blocked_attempt_created_no_snapshot',
        (await review.listApprovals()).isEmpty);

    await review.completeBatch(actor: reviewer, batchId: 'batch-001');
    await review.resolveFeedback(actor: reviewer, feedbackId: blocking.id);
    final resolved = await review.loadFeedback(blocking.id);
    check(
      'refinement.blocking_resolved_by_reviewer',
      resolved?.status == FeedbackStatus.resolved,
    );

    // --- 6. Automated visual QA -> explicit promotion ----------------------
    final provider = FixtureVisualQaProvider(
      candidates: [
        VisualQaCandidate.fromJson({
          'category': 'spacing',
          'severity': 'major',
          'summary': 'Price block spacing is inconsistent with the token grid.',
          'surface': 'prototype',
          'screen': 'commerce.pdp',
          'state': 'default',
          'direction': 'b',
          'section': 'pdp.price',
          'screenshot_ref': captureId,
          'rule_source': 'design_contract',
          'rule_ref': 'spacing.price.rule',
          'confidence': 0.9,
        }),
      ],
    );
    final qaContext = VisualQaContext(
      clientId: runtime.clientId,
      surface: QaSurface.prototype,
      screen: 'commerce.pdp',
      state: 'default',
      direction: 'b',
      section: 'pdp.price',
      sourceCommitSha: fixedSourceCommitSha,
      fixtureVersion: '1',
    );
    final qaAuthority = VisualQaAuthorityBundle(
      entries: const [
        VisualQaAuthorityEntry(
          source: QaRuleSource.designContract,
          refs: ['design-contract/tokens'],
        ),
      ],
    );
    final candidates = await provider.review(
      VisualQaRequest(
        context: qaContext,
        artifacts: const [
          VisualQaArtifactRef(captureId: captureId, contentHash: 'sha256:content'),
        ],
        authority: qaAuthority,
      ),
    );
    final finding = await qa.recordFinding(
      candidates.single.toFinding(
        id: 'qa-001',
        context: qaContext,
        actorId: 'visual-qa',
        at: DateTime.utc(2026, 9, 18, 10),
      ),
    );
    check('qa.finding_detected', finding.status == QaFindingStatus.detected);
    check('qa.finding_blocking_null', finding.blocking == null);
    check('qa.finding_origin_feedback_absent', finding.feedbackId == null);
    check(
      'qa.no_feedback_before_promotion',
      (await review.allFeedback())
          .where((record) => record.originQaFindingId != null)
          .isEmpty,
    );

    await qa.triageFinding(findingId: 'qa-001', actor: reviewer);
    final triaged = await qa.loadFinding('qa-001');
    check('qa.finding_triaged', triaged?.status == QaFindingStatus.triaged);

    final promoted = await qa.promoteFinding(
      findingId: 'qa-001',
      actor: reviewer,
    );
    check(
      'qa.promotion_origin_link',
      promoted.originQaFindingId == finding.id,
    );
    check('qa.promotion_open', promoted.status == FeedbackStatus.open);
    check('qa.promotion_non_blocking', promoted.blocking == false);
    check('qa.promotion_did_not_auto_resolve',
        promoted.status != FeedbackStatus.resolved);

    final promotedAgain =
        await qa.promoteFinding(findingId: 'qa-001', actor: reviewer);
    check('qa.promotion_idempotent', promotedAgain.id == promoted.id);
    check(
      'qa.exactly_one_promoted_feedback',
      (await review.allFeedback())
              .where((record) => record.originQaFindingId == finding.id)
              .length ==
          1,
    );

    // --- 4. Explicit round close -------------------------------------------
    await review.closeCurrentRound(actor: reviewer);
    check(
      'round.closed_ready_for_final_review',
      controller.state.status == ReviewStatus.readyForFinalReview,
    );
    check('round.review_round_1', controller.state.reviewRound == 1);

    // --- 5. ApprovalSnapshot v1 --------------------------------------------
    final snapshot = await review.createApproval(
      reviewer: reviewer,
      approver: approver,
      sourceCommitSha: fixedSourceCommitSha,
    );
    check('approval.version_1', snapshot.version == 1);
    check('approval.supersedes_null', snapshot.supersedes == null);
    check(
      'approval.review_round_matches',
      snapshot.reviewRound == controller.state.reviewRound,
    );
    check('approval.hash_sha256', snapshot.reviewStateHash.startsWith('sha256:'));
    check(
      'approval.carries_non_blocking_feedback',
      snapshot.unresolvedNonBlockingFeedbackIds.contains(nonBlocking.id),
    );

    final approvalFile = reviewLayout.approvalFile(runtime.clientId, 1);
    final approvalBytes = await approvalFile.readAsString();
    final canonicalApproval =
        '${const JsonEncoder.withIndent('  ').convert(snapshot.toJson())}\n';
    check('approval.file_byte_identical', approvalBytes == canonicalApproval);

    // --- 7. Runtime and committed bundle are read-only ---------------------
    check(
      'runtime.bundle_bytes_unchanged',
      _bytesEqual(File(referenceBundlePath).readAsBytesSync(), bundleBytesBefore),
    );
    check(
      'runtime.snapshot_unchanged',
      jsonEncode(_runtimeSnapshot(runtime)) == runtimeBefore,
    );

    // --- Evidence emission (only when an output path is provided) ----------
    final batch = await review.loadBatch('batch-001');
    final qaFinding = await qa.loadFinding('qa-001');
    final evidence = <String, Object?>{
      'client_id': runtime.clientId,
      'fixture_version': 1,
      'scenario_id': 'normal-happy-path',
      'source_commit_sha': fixedSourceCommitSha,
      'selected_direction': controller.state.selectedDirection,
      'screen_overrides': {
        for (final entry in controller.state.screenSelections.entries)
          if (entry.value.direction != null) entry.key: entry.value.direction,
      },
      'section_overrides': {
        for (final entry in controller.state.screenSelections.entries)
          if (entry.value.sections.isNotEmpty)
            entry.key: Map<String, String>.from(entry.value.sections),
      },
      'feedback': {
        'blocking': [
          _feedbackRef((await review.loadFeedback(blocking.id))!),
        ],
        'non_blocking': [
          _feedbackRef((await review.loadFeedback(nonBlocking.id))!),
        ],
        'visual_annotations': [
          _visualRef((await review.loadFeedback(visual.id))!),
        ],
      },
      'refinement_batches': [
        {
          'id': batch!.id,
          'status': refinementBatchStatusToWire(batch.status),
          'feedback_ids': List<String>.from(batch.feedbackIds),
          'classification': batch.changeClassification.confirmed == null
              ? null
              : changeClassificationToWire(batch.changeClassification.confirmed!),
        },
      ],
      'review_rounds': controller.state.reviewRound,
      'approval_versions': [snapshot.version],
      'qa': {
        'findings': [
          {
            'id': qaFinding!.id,
            'status': qaFindingStatusToWire(qaFinding.status),
            'severity': qaSeverityToWire(qaFinding.severity),
            'category': qaFinding.category,
            'surface': qaSurfaceToWire(qaFinding.surface),
            'screen': qaFinding.screen,
            'section': qaFinding.section,
            'rule_source': qaRuleSourceToWire(qaFinding.ruleSource),
            'screenshot_ref': qaFinding.screenshotRef,
            'source_commit_sha': qaFinding.sourceCommitSha,
          },
        ],
        'promotions': [
          {
            'finding_id': finding.id,
            'feedback_id': promoted.id,
            'blocking': promoted.blocking,
          },
        ],
      },
      'assertions': assertions,
    };

    const evidencePath = String.fromEnvironment('REFERENCE_EVIDENCE_PATH');
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
