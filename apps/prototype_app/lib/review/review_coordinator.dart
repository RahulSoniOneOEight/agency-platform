import 'approval_repository.dart';
import 'approval_snapshot.dart';
import 'feedback_record.dart';
import 'feedback_repository.dart';
import 'review_actor.dart';
import 'review_controller.dart';
import 'refinement_batch.dart';
import 'refinement_batch_repository.dart';
import 'refinement_execution_result.dart';
import 'review_domain_error.dart';
import 'review_screen_availability.dart';
import 'review_screen_registry.dart';
import 'review_section_registry.dart';
import 'review_state.dart';
import 'review_state_hash.dart';
import 'visual_attachment.dart';

/// Thin cross-domain orchestration for C.4 review feedback and review rounds.
///
/// The coordinator owns the workflow rules that span [ReviewState] and
/// [FeedbackRecord] (blocking gates, round closure, next-round advancement) and
/// delegates all ReviewState persistence to [ReviewController] so its C.3
/// transactional `normalize -> validate -> save -> adopt` path is preserved.
/// Feedback records are immutable and append-only; [FeedbackRepository.replace]
/// uses expected-current semantics so a stale copy can never overwrite newer
/// state.
///
/// Operations validate the complete candidate first. Invalid operations perform
/// no repository write, append no history event, mutate no state, and throw a
/// deterministic typed [ReviewDomainError].
final class ReviewCoordinator {
  ReviewCoordinator({
    required ReviewController controller,
    required FeedbackRepository feedbackRepository,
    required ApprovalRepository approvalRepository,
    required RefinementBatchRepository refinementBatchRepository,
  })  : _controller = controller,
        _feedback = feedbackRepository,
        _approvals = approvalRepository,
        _batches = refinementBatchRepository;

  final ReviewController _controller;
  final FeedbackRepository _feedback;
  final ApprovalRepository _approvals;
  final RefinementBatchRepository _batches;

  String get clientId => _controller.clientId;

  ReviewState get reviewState => _controller.state;

  /// All feedback for this client, in deterministic id order.
  Future<List<FeedbackRecord>> allFeedback() => _feedback.list(clientId);

  /// Loads a single feedback record, or `null` when it does not exist.
  Future<FeedbackRecord?> loadFeedback(String feedbackId) =>
      _feedback.load(clientId, feedbackId);

  /// Feedback created in [round].
  Future<List<FeedbackRecord>> feedbackForRound(int round) async {
    final records = await allFeedback();
    return <FeedbackRecord>[
      for (final record in records)
        if (record.createdRound == round) record,
    ];
  }

  /// Blocking feedback that is not yet resolved.
  Future<List<FeedbackRecord>> blockingUnresolved() async {
    final records = await allFeedback();
    return <FeedbackRecord>[
      for (final record in records)
        if (record.blocking && record.status != FeedbackStatus.resolved) record,
    ];
  }

  /// Whether the current round may be closed: every blocker is resolved.
  ///
  /// Non-blocking open items never prevent closure. Eligibility alone does not
  /// close the round; the reviewer must call [closeCurrentRound].
  Future<bool> isEligibleToCloseRound() async =>
      (await blockingUnresolved()).isEmpty;

  /// Creates reviewer feedback and references it from [ReviewState].
  ///
  /// Blocking feedback moves the review to `needsRevision`; new feedback after
  /// `readyForFinalReview` advances to a new round first. Defaults to blocking.
  Future<FeedbackRecord> createFeedback({
    required ReviewActor actor,
    required String id,
    required FeedbackScope scope,
    required String text,
    required FeedbackTarget target,
    bool blocking = true,
    VisualAttachment? visualAttachment,
  }) async {
    _requireReviewer(actor, 'create feedback');
    final feedbackId = id.trim();
    if (feedbackId.isEmpty) {
      throw const FormatException('Feedback id is required');
    }
    final feedbackText = text.trim();
    if (feedbackText.isEmpty) {
      throw const FormatException('Feedback text is required');
    }
    if (!target.isValidForScope(scope)) {
      throw InvalidFeedbackTarget('target is not valid for $scope feedback');
    }
    if (scope != FeedbackScope.visualAnnotation) {
      _validateGovernedTarget(target);
    }
    if (visualAttachment != null && scope != FeedbackScope.visualAnnotation) {
      throw const InvalidVisualAnnotation(
        'visual evidence is only valid for visual_annotation feedback',
      );
    }
    if (visualAttachment != null) {
      _validateVisualAttachment(visualAttachment);
    }
    if (await _feedback.load(clientId, feedbackId) != null) {
      throw DuplicateFeedbackId('feedback record already exists: $feedbackId');
    }

    final state = _controller.state;
    final ready = state.status == ReviewStatus.readyForFinalReview;
    final round = ready ? state.reviewRound + 1 : state.reviewRound;
    final status = blocking
        ? ReviewStatus.needsRevision
        : (ready ? ReviewStatus.inReview : state.status);
    final feedbackIds = <String>[...state.feedbackIds, feedbackId];

    // Validate the complete candidate ReviewState before any repository write so
    // an invalid operation (e.g. duplicate id) performs no persistence at all.
    try {
      _controller.normalizeAndValidateCandidate(
        reviewRound: round,
        status: status,
        feedbackIds: feedbackIds,
      );
    } on StateError catch (error) {
      final message = error.message;
      if (message.contains('duplicate feedback id')) {
        throw DuplicateFeedbackId(message);
      }
      throw InvalidReviewState(message);
    }

    final record = FeedbackRecord(
      id: feedbackId,
      scope: scope,
      text: feedbackText,
      status: FeedbackStatus.open,
      blocking: blocking,
      createdRound: round,
      target: target,
      visualAttachment: visualAttachment,
      history: <FeedbackEvent>[
        FeedbackEvent(
          type: FeedbackEventType.created,
          actorId: actor.id,
          at: DateTime.now().toUtc(),
          round: round,
        ),
      ],
    );

    await _feedback.create(clientId, record);
    await _controller.applyState(
      reviewRound: round,
      status: status,
      feedbackIds: feedbackIds,
    );
    return record;
  }

  /// Resolves addressed feedback; reviewer-only.
  Future<FeedbackRecord> resolveFeedback({
    required ReviewActor actor,
    required String feedbackId,
  }) async {
    if (!actor.isReviewer) {
      throw const UnauthorizedFeedbackResolution(
        'reviewer role required to resolve feedback',
      );
    }
    final current = await _requireFeedback(feedbackId);
    if (current.status != FeedbackStatus.addressed) {
      throw InvalidFeedbackTransition(
        'cannot resolve ${current.status.name} feedback',
      );
    }
    final round = _controller.state.reviewRound;
    final next = current.copyWith(
      status: FeedbackStatus.resolved,
      resolvedRound: round,
      history: _append(
        current,
        FeedbackEvent(
          type: FeedbackEventType.resolved,
          actorId: actor.id,
          at: DateTime.now().toUtc(),
          round: round,
        ),
      ),
    );
    await _feedback.replace(clientId, current, next);
    return next;
  }

  /// Reopens addressed or resolved feedback; reviewer-only.
  ///
  /// Reopening a blocking item while the review is `readyForFinalReview`
  /// reconciles readiness: the round advances monotonically and the status
  /// returns to `needsRevision`. Reopening a non-blocking item (or reopening
  /// while not ready) leaves the review status untouched. The candidate state is
  /// validated before the feedback write, so a failed operation has no partial
  /// persistence.
  Future<FeedbackRecord> reopenFeedback({
    required ReviewActor actor,
    required String feedbackId,
  }) async {
    if (!actor.isReviewer) {
      throw const UnauthorizedFeedbackResolution(
        'reviewer role required to reopen feedback',
      );
    }
    final current = await _requireFeedback(feedbackId);
    if (current.status == FeedbackStatus.open) {
      throw const InvalidFeedbackTransition('feedback is already open');
    }
    final next = current.copyWith(
      status: FeedbackStatus.open,
      resolvedRound: null,
      history: _append(
        current,
        FeedbackEvent(
          type: FeedbackEventType.reopened,
          actorId: actor.id,
          at: DateTime.now().toUtc(),
          round: _controller.state.reviewRound,
        ),
      ),
    );

    final state = _controller.state;
    final reconcile = current.blocking &&
        state.status == ReviewStatus.readyForFinalReview;
    final int? nextRound = reconcile ? state.reviewRound + 1 : null;
    if (reconcile) {
      _validateCandidate(reviewRound: nextRound, status: ReviewStatus.needsRevision);
    }

    await _feedback.replace(clientId, current, next);
    if (reconcile) {
      await _controller.applyState(
        reviewRound: nextRound,
        status: ReviewStatus.needsRevision,
      );
    }
    return next;
  }

  /// Changes the blocking classification; reviewer-only.
  ///
  /// Setting an *unresolved* item blocking moves the review to `needsRevision`
  /// (advancing a ready round first). A resolved item toggled to blocking does
  /// not change the review status. Setting the same value is a no-op with no
  /// history event. The candidate state is validated before the feedback write.
  Future<FeedbackRecord> setBlocking({
    required ReviewActor actor,
    required String feedbackId,
    required bool blocking,
  }) async {
    if (!actor.isReviewer) {
      throw const UnauthorizedBlockingChange(
        'reviewer role required to change blocking classification',
      );
    }
    final current = await _requireFeedback(feedbackId);
    if (current.blocking == blocking) {
      return current;
    }
    final next = current.copyWith(
      blocking: blocking,
      history: _append(
        current,
        FeedbackEvent(
          type: FeedbackEventType.blockingChanged,
          actorId: actor.id,
          at: DateTime.now().toUtc(),
          round: _controller.state.reviewRound,
        ),
      ),
    );

    final state = _controller.state;
    final drivesStatus = blocking && current.status != FeedbackStatus.resolved;
    final ready = state.status == ReviewStatus.readyForFinalReview;
    final int? nextRound =
        drivesStatus && ready ? state.reviewRound + 1 : null;
    if (drivesStatus) {
      _validateCandidate(
        reviewRound: nextRound,
        status: ReviewStatus.needsRevision,
      );
    }

    await _feedback.replace(clientId, current, next);
    if (drivesStatus) {
      await _controller.applyState(
        reviewRound: nextRound,
        status: ReviewStatus.needsRevision,
      );
    }
    return next;
  }

  /// Closes the current round; reviewer-only and eligibility-gated.
  ///
  /// Eligibility (all blockers resolved) alone never closes the round; this
  /// explicit reviewer action sets `readyForFinalReview`.
  Future<void> closeCurrentRound({required ReviewActor actor}) async {
    _requireReviewer(actor, 'close the review round');
    final state = _controller.state;
    if (state.status == ReviewStatus.readyForFinalReview) {
      throw ReviewRoundNotClosable(
        'review round ${state.reviewRound} is already ready for final review',
      );
    }
    if (!await isEligibleToCloseRound()) {
      throw const BlockingFeedbackUnresolved(
        'blocking feedback must be resolved before closing the round',
      );
    }
    await _controller.applyState(status: ReviewStatus.readyForFinalReview);
  }

  /// Advances to the next review round; reviewer-only.
  ///
  /// The round increments monotonically, the status returns to `inReview`, and
  /// every feedback record and reference is preserved.
  Future<void> startNextRound({required ReviewActor actor}) async {
    _requireReviewer(actor, 'advance the review round');
    await _controller.applyState(
      reviewRound: _controller.state.reviewRound + 1,
      status: ReviewStatus.inReview,
    );
  }

  /// All immutable approval snapshots for this client, ascending by version.
  Future<List<ApprovalSnapshot>> listApprovals() => _approvals.list(clientId);

  /// Human-readable reasons approval is currently blocked; empty when eligible.
  ///
  /// Mirrors the [createApproval] eligibility gates for UI display without
  /// performing any write. Actor identities and the source commit SHA are
  /// captured at creation time and are not part of this state-level check.
  Future<List<String>> approvalBlockingReasons() async {
    final reasons = <String>[];
    final state = _controller.state;
    if (state.status != ReviewStatus.readyForFinalReview) {
      reasons.add(
        'Review status must be ready_for_final_review '
        '(currently ${reviewStatusToWire(state.status)}).',
      );
    }
    final blockers = await blockingUnresolved();
    if (blockers.isNotEmpty) {
      reasons.add(
        'Blocking feedback unresolved: '
        '${blockers.map((record) => record.id).join(', ')}.',
      );
    }
    final unresolvedContract = await _unresolvedContractImpactingBatches();
    if (unresolvedContract.isNotEmpty) {
      reasons.add(
        'Contract-impacting refinement batches must be completed: '
        '${unresolvedContract.map((batch) => batch.id).join(', ')}.',
      );
    }
    final existingApprovals = await _approvals.list(clientId);
    if (existingApprovals.isNotEmpty) {
      final latest = existingApprovals.last;
      if (await _hasContractImpactingBatch() &&
          state.reviewRound <= latest.reviewRound) {
        reasons.add(
          'A contract-impacting change requires a new review round before '
          'approval (last approval round ${latest.reviewRound}).',
        );
      }
    }
    try {
      _controller.normalizeAndValidateCandidate();
    } on StateError catch (error) {
      reasons.add('C.3 decision tree is invalid: ${error.message}');
    }
    return reasons;
  }

  /// Whether the review currently passes every state-level approval gate.
  Future<bool> isEligibleForApproval() async =>
      (await approvalBlockingReasons()).isEmpty;

  /// Creates an immutable approval snapshot after revalidating every gate.
  ///
  /// Gates: readiness, all blocking feedback resolved, a valid C.3 decision
  /// tree, recorded reviewer and approver identities, a non-empty source commit
  /// SHA, and an available review-state hash. The version is
  /// `(max existing version) + 1`. Any failed gate throws a typed
  /// [ReviewDomainError] and persists nothing; a duplicate version throws
  /// [ApprovalVersionConflict]. Unresolved non-blocking feedback is carried
  /// forward explicitly.
  Future<ApprovalSnapshot> createApproval({
    required ReviewActor reviewer,
    required ReviewActor approver,
    required String sourceCommitSha,
    String? themePreset,
  }) async {
    _requireReviewer(reviewer, 'create approval');
    if (reviewer.id.trim().isEmpty || reviewer.name.trim().isEmpty) {
      throw const ApprovalNotEligible('reviewer identity must be recorded');
    }
    if (!approver.isApprover ||
        approver.id.trim().isEmpty ||
        approver.name.trim().isEmpty) {
      throw const ApprovalNotEligible('approver identity must be recorded');
    }
    final commitSha = sourceCommitSha.trim();
    if (commitSha.isEmpty) {
      throw const ApprovalNotEligible('source commit SHA is required');
    }

    final state = _controller.state;
    if (state.status != ReviewStatus.readyForFinalReview) {
      throw ApprovalNotEligible(
        'review status must be ready_for_final_review to approve',
      );
    }
    final blockers = await blockingUnresolved();
    if (blockers.isNotEmpty) {
      throw ApprovalNotEligible(
        'blocking feedback must be resolved before approval',
      );
    }
    // C.7 refinement dependency gate (ledger M2): an unresolved
    // contract-impacting refinement batch blocks approval.
    final unresolvedContract = await _unresolvedContractImpactingBatches();
    if (unresolvedContract.isNotEmpty) {
      throw ContractImpactRequiresNewRound(
        'contract-impacting refinement batch '
        '${unresolvedContract.first.id} must be completed before approval',
      );
    }
    // Contract-impacting changes require a new review round: an existing
    // approval at round R cannot be followed by a new approval at round <= R
    // while a contract-impacting change exists.
    final existingApprovals = await _approvals.list(clientId);
    if (existingApprovals.isNotEmpty &&
        await _hasContractImpactingBatch() &&
        state.reviewRound <= existingApprovals.last.reviewRound) {
      throw ContractImpactRequiresNewRound(
        'contract-impacting change requires a new review round before approval',
      );
    }
    try {
      _controller.normalizeAndValidateCandidate();
    } on StateError catch (error) {
      throw ApprovalNotEligible('C.3 decision tree is invalid: ${error.message}');
    }

    final hash = reviewStateHash(state);
    final records = await allFeedback();
    final unresolvedNonBlocking = <String>[
      for (final record in records)
        if (!record.blocking && record.status != FeedbackStatus.resolved)
          record.id,
    ]..sort();

    final existing = await _approvals.list(clientId);
    var maxVersion = 0;
    for (final snapshot in existing) {
      if (snapshot.version > maxVersion) maxVersion = snapshot.version;
    }
    final version = maxVersion + 1;

    final snapshot = ApprovalSnapshot(
      version: version,
      clientId: clientId,
      reviewRound: state.reviewRound,
      reviewedBy: reviewer,
      approvedBy: approver,
      approvedAt: DateTime.now().toUtc(),
      selectedDirection: state.selectedDirection,
      screenSelections: state.screenSelections,
      unresolvedNonBlockingFeedbackIds: unresolvedNonBlocking,
      sourceCommitSha: commitSha,
      reviewStateHash: hash,
      themePreset: themePreset,
      supersedes: maxVersion == 0 ? null : maxVersion,
    );

    await _approvals.create(clientId, snapshot);
    return snapshot;
  }

  // ---------------------------------------------------------------------------
  // C.7 refinement batches
  // ---------------------------------------------------------------------------

  /// All refinement batches for this client, in deterministic id order.
  Future<List<RefinementBatch>> allBatches() => _batches.list(clientId);

  /// Loads a single refinement batch, or `null` when it does not exist.
  Future<RefinementBatch?> loadBatch(String batchId) =>
      _batches.load(clientId, batchId);

  /// Creates a reviewer-owned `draft` batch from eligible open feedback.
  ///
  /// OpenCode can never auto-create a batch; only a reviewer may call this.
  /// Every linked feedback id must exist and be `open`. The proposed
  /// classification defaults to `contract_impacting` (R7 uncertainty rule) and
  /// must be confirmed by a reviewer before the batch can become `ready`.
  Future<RefinementBatch> createDraftBatch({
    required ReviewActor actor,
    required String id,
    required List<String> feedbackIds,
    required IntendedScope intendedScope,
    ChangeClassification proposed = ChangeClassification.contractImpacting,
    String proposedBy = 'opencode',
  }) async {
    _requireReviewer(actor, 'create a refinement batch');
    final batchId = id.trim();
    if (batchId.isEmpty) {
      throw const FormatException('Refinement batch id is required');
    }
    if (await _batches.load(clientId, batchId) != null) {
      throw DuplicateBatchId('refinement batch already exists: $batchId');
    }
    await _requireEligibleFeedback(feedbackIds);
    final now = DateTime.now().toUtc();
    final batch = RefinementBatch.draft(
      id: batchId,
      clientId: clientId,
      reviewRound: _controller.state.reviewRound,
      feedbackIds: feedbackIds,
      intendedScope: intendedScope,
      proposedBy: proposedBy,
      proposed: proposed,
      createdBy: actor.id,
      createdAt: now,
    );
    await _batches.create(clientId, batch);
    return batch;
  }

  /// Edits linked feedback/scope while the batch is still `draft`.
  Future<RefinementBatch> updateDraftBatch({
    required ReviewActor actor,
    required String batchId,
    List<String>? feedbackIds,
    IntendedScope? intendedScope,
  }) async {
    _requireReviewer(actor, 'update a refinement batch');
    final current = await _requireBatch(batchId);
    if (feedbackIds != null) {
      await _requireEligibleFeedback(feedbackIds);
    }
    final next = current.editDraft(
      actorId: actor.id,
      at: DateTime.now().toUtc(),
      feedbackIds: feedbackIds,
      intendedScope: intendedScope,
    );
    await _batches.replace(clientId, current, next);
    return next;
  }

  /// Records the reviewer-confirmed change classification; draft only.
  Future<RefinementBatch> confirmBatchClassification({
    required ReviewActor actor,
    required String batchId,
    required ChangeClassification confirmed,
  }) async {
    _requireReviewer(actor, 'confirm a batch change classification');
    final current = await _requireBatch(batchId);
    final next = current.confirmClassification(
      actorId: actor.id,
      at: DateTime.now().toUtc(),
      confirmed: confirmed,
    );
    await _batches.replace(clientId, current, next);
    return next;
  }

  /// Freezes scope and classification and hands the batch to execution.
  Future<RefinementBatch> markBatchReady({
    required ReviewActor actor,
    required String batchId,
  }) async {
    _requireReviewer(actor, 'mark a refinement batch ready');
    final current = await _requireBatch(batchId);
    final next = current.markReady(
      actorId: actor.id,
      at: DateTime.now().toUtc(),
    );
    await _batches.replace(clientId, current, next);
    return next;
  }

  /// Starts execution of a `ready` batch; agent/OpenCode authority.
  Future<RefinementBatch> startBatch({
    required ReviewActor actor,
    required String batchId,
    String? agent,
    String? model,
  }) async {
    _requireAgent(actor, 'start a refinement batch');
    final current = await _requireBatch(batchId);
    final next = current.start(
      actorId: actor.id,
      at: DateTime.now().toUtc(),
      agent: agent ?? actor.id,
      model: model,
    );
    await _batches.replace(clientId, current, next);
    return next;
  }

  /// Records an OpenCode execution result for an `in_progress` batch.
  ///
  /// A passing result moves the batch to `readyForReview` and then moves every
  /// linked `open` feedback to `addressed` with an `addressed` event carrying
  /// [batchId]. A failing result moves the batch to `validationFailed` and
  /// leaves linked feedback `open`. The authoritative batch is persisted before
  /// any feedback write, so a batch persistence failure can never produce a
  /// false addressed transition.
  Future<RefinementBatch> recordBatchValidation({
    required ReviewActor actor,
    required String batchId,
    required RefinementExecutionResult result,
    String? model,
  }) async {
    _requireAgent(actor, 'record batch validation');
    final current = await _requireBatch(batchId);
    if (current.status != RefinementBatchStatus.inProgress) {
      throw BatchNotReady(
        'refinement batch $batchId is not in progress '
        '(currently ${refinementBatchStatusToWire(current.status)})',
      );
    }
    if (result.passed) {
      if (result.checks.isEmpty) {
        throw BatchValidationRequired(
          'refinement batch $batchId requires at least one validation check',
        );
      }
      if (!result.batchValidation.allPassed) {
        throw BatchValidationFailed(
          'refinement batch $batchId requires every validation check to pass',
        );
      }
      if (await _hasVisualLinkedFeedback(current) && result.evidence.isEmpty) {
        throw BatchValidationRequired(
          'refinement batch $batchId requires screenshot/evidence for visual feedback',
        );
      }
    }
    final next = current.recordValidation(
      actorId: actor.id,
      at: DateTime.now().toUtc(),
      validation: result.batchValidation,
      execution: result.execution(agent: actor.id, model: model),
      evidence: result.evidence,
    );
    await _batches.replace(clientId, current, next);
    if (result.passed) {
      await _markLinkedFeedbackAddressed(current, actor);
    }
    return next;
  }

  /// Completes a batch after reviewer review; completed batches are frozen.
  Future<RefinementBatch> completeBatch({
    required ReviewActor actor,
    required String batchId,
  }) async {
    _requireReviewer(actor, 'complete a refinement batch');
    final current = await _requireBatch(batchId);
    final next = current.complete(
      actorId: actor.id,
      at: DateTime.now().toUtc(),
    );
    await _batches.replace(clientId, current, next);
    return next;
  }

  /// Reopens an already-addressed item invalidated by a later regression.
  ///
  /// This is the deterministic, append-only system-failure path (not reviewer
  /// reopen authority): it records the regression [cause], [evidence], and the
  /// [batchId] that identified it. Only the agent may trigger it, and only for
  /// `addressed` feedback.
  Future<FeedbackRecord> reopenAddressedForRegression({
    required ReviewActor actor,
    required String feedbackId,
    required String cause,
    required String evidence,
    required String batchId,
  }) async {
    if (!actor.isAgent) {
      throw const UnauthorizedFeedbackResolution(
        'only the system agent may reopen feedback for a regression',
      );
    }
    final regressionCause = cause.trim();
    final regressionEvidence = evidence.trim();
    final regressionBatchId = batchId.trim();
    if (regressionCause.isEmpty ||
        regressionEvidence.isEmpty ||
        regressionBatchId.isEmpty) {
      throw const FormatException(
        'regression reopen requires a cause, evidence, and batch id',
      );
    }
    final current = await _requireFeedback(feedbackId);
    if (current.status != FeedbackStatus.addressed) {
      throw InvalidFeedbackTransition(
        'regression reopen requires addressed feedback '
        '(currently ${feedbackStatusToWire(current.status)})',
      );
    }
    final next = current.copyWith(
      status: FeedbackStatus.open,
      resolvedRound: null,
      history: _append(
        current,
        FeedbackEvent(
          type: FeedbackEventType.reopened,
          actorId: actor.id,
          at: DateTime.now().toUtc(),
          round: _controller.state.reviewRound,
          batchId: regressionBatchId,
          cause: regressionCause,
          evidence: regressionEvidence,
        ),
      ),
    );

    final state = _controller.state;
    final reconcile =
        current.blocking && state.status == ReviewStatus.readyForFinalReview;
    final int? nextRound = reconcile ? state.reviewRound + 1 : null;
    if (reconcile) {
      _validateCandidate(
        reviewRound: nextRound,
        status: ReviewStatus.needsRevision,
      );
    }

    await _feedback.replace(clientId, current, next);
    if (reconcile) {
      await _controller.applyState(
        reviewRound: nextRound,
        status: ReviewStatus.needsRevision,
      );
    }
    return next;
  }

  Future<List<RefinementBatch>> _unresolvedContractImpactingBatches() async {
    final batches = await _batches.list(clientId);
    return <RefinementBatch>[
      for (final batch in batches)
        if (batch.changeClassification.confirmed ==
                ChangeClassification.contractImpacting &&
            batch.status != RefinementBatchStatus.completed)
          batch,
    ];
  }

  Future<bool> _hasContractImpactingBatch() async {
    final batches = await _batches.list(clientId);
    return batches.any(
      (batch) =>
          batch.changeClassification.confirmed ==
          ChangeClassification.contractImpacting,
    );
  }

  Future<bool> _hasVisualLinkedFeedback(RefinementBatch batch) async {
    for (final feedbackId in batch.feedbackIds) {
      final record = await _feedback.load(clientId, feedbackId);
      if (record != null && record.visualAttachment != null) {
        return true;
      }
    }
    return false;
  }

  Future<void> _markLinkedFeedbackAddressed(
    RefinementBatch batch,
    ReviewActor actor,
  ) async {
    final round = _controller.state.reviewRound;
    for (final feedbackId in batch.feedbackIds) {
      final record = await _feedback.load(clientId, feedbackId);
      if (record == null || record.status != FeedbackStatus.open) {
        continue;
      }
      final next = record.copyWith(
        status: FeedbackStatus.addressed,
        history: _append(
          record,
          FeedbackEvent(
            type: FeedbackEventType.addressed,
            actorId: actor.id,
            at: DateTime.now().toUtc(),
            round: round,
            batchId: batch.id,
          ),
        ),
      );
      await _feedback.replace(clientId, record, next);
    }
  }

  Future<void> _requireEligibleFeedback(List<String> feedbackIds) async {
    if (feedbackIds.isEmpty) {
      throw const InvalidBatchTransition(
        'a refinement batch requires at least one feedback id',
      );
    }
    for (final feedbackId in feedbackIds) {
      final record = await _feedback.load(clientId, feedbackId);
      if (record == null) {
        throw FeedbackNotFound('unknown feedback id: $feedbackId');
      }
      if (record.status != FeedbackStatus.open) {
        throw InvalidBatchTransition(
          'feedback $feedbackId is not eligible for refinement '
          '(status ${feedbackStatusToWire(record.status)})',
        );
      }
    }
  }

  Future<RefinementBatch> _requireBatch(String batchId) async {
    final batch = await _batches.load(clientId, batchId);
    if (batch == null) {
      throw BatchNotFound('unknown refinement batch id: $batchId');
    }
    return batch;
  }

  void _requireAgent(ReviewActor actor, String action) {
    if (!actor.isAgent) {
      throw UnauthorizedReviewAction('agent role required to $action');
    }
  }

  /// Validates a non-visual feedback target against the governed registries.
  ///
  /// A named screen must be a runtime-declared pattern, a named section must
  /// belong to the named screen, and a named direction must exist (and, when a
  /// screen is also named, be compatible with that screen). Failures throw a
  /// typed [InvalidFeedbackTarget] before any write.
  void _validateGovernedTarget(FeedbackTarget target) {
    final runtime = _controller.runtime;
    final screen = target.screen;
    if (screen != null &&
        !ReviewScreenRegistry.screenIdsFor(runtime).contains(screen)) {
      throw InvalidFeedbackTarget('unknown feedback target screen: $screen');
    }
    final section = target.section;
    if (section != null) {
      final definition = ReviewSectionRegistry.definition(section);
      if (definition == null || definition.screenId != screen) {
        throw InvalidFeedbackTarget(
          'feedback section $section does not belong to screen $screen',
        );
      }
    }
    final direction = target.direction;
    if (direction != null) {
      if (!runtime.directions.containsKey(direction)) {
        throw InvalidFeedbackTarget(
          'unknown feedback target direction: $direction',
        );
      }
      if (screen != null &&
          !ReviewScreenAvailability.isSupported(runtime, direction, screen)) {
        throw InvalidFeedbackTarget(
          'feedback screen $screen is not supported by direction $direction',
        );
      }
    }
  }

  /// Validates normalized visual evidence against governed screen/section IDs.
  void _validateVisualAttachment(VisualAttachment attachment) {
    if (attachment.clientId != clientId) {
      throw InvalidVisualAnnotation(
        'visual evidence belongs to client ${attachment.clientId}',
      );
    }
    final governedScreens =
        ReviewScreenRegistry.screenIdsFor(_controller.runtime);
    if (!governedScreens.contains(attachment.screenId)) {
      throw InvalidVisualAnnotation(
        'unknown visual evidence screen: ${attachment.screenId}',
      );
    }
    final sectionId = attachment.sectionId;
    if (sectionId != null) {
      final definition = ReviewSectionRegistry.definition(sectionId);
      if (definition == null || definition.screenId != attachment.screenId) {
        throw InvalidVisualAnnotation(
          'visual evidence section $sectionId does not belong to '
          '${attachment.screenId}',
        );
      }
    }
  }

  List<FeedbackEvent> _append(FeedbackRecord record, FeedbackEvent event) =>
      <FeedbackEvent>[...record.history, event];

  /// Validates a candidate primitive transition, mapping controller findings to
  /// a typed [InvalidReviewState] so callers never see a bare [StateError].
  void _validateCandidate({int? reviewRound, ReviewStatus? status}) {
    try {
      _controller.normalizeAndValidateCandidate(
        reviewRound: reviewRound,
        status: status,
      );
    } on StateError catch (error) {
      throw InvalidReviewState(error.message);
    }
  }

  Future<FeedbackRecord> _requireFeedback(String feedbackId) async {
    final record = await _feedback.load(clientId, feedbackId);
    if (record == null) {
      throw FeedbackNotFound('unknown feedback id: $feedbackId');
    }
    return record;
  }

  void _requireReviewer(ReviewActor actor, String action) {
    if (!actor.isReviewer) {
      throw UnauthorizedReviewAction('reviewer role required to $action');
    }
  }
}
