import 'approval_repository.dart';
import 'approval_snapshot.dart';
import 'feedback_record.dart';
import 'feedback_repository.dart';
import 'review_actor.dart';
import 'review_controller.dart';
import 'review_domain_error.dart';
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
  })  : _controller = controller,
        _feedback = feedbackRepository,
        _approvals = approvalRepository;

  final ReviewController _controller;
  final FeedbackRepository _feedback;
  final ApprovalRepository _approvals;

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

  /// Marks feedback `open -> addressed`; the agent/OpenCode authority.
  Future<FeedbackRecord> markAddressed({
    required ReviewActor actor,
    required String feedbackId,
    String? batchId,
  }) async {
    if (!actor.isAgent) {
      throw const UnauthorizedReviewAction(
        'only an agent may mark feedback addressed',
      );
    }
    final current = await _requireFeedback(feedbackId);
    if (current.status != FeedbackStatus.open) {
      throw InvalidFeedbackTransition(
        'cannot mark ${current.status.name} feedback addressed',
      );
    }
    final next = current.copyWith(
      status: FeedbackStatus.addressed,
      history: _append(
        current,
        FeedbackEvent(
          type: FeedbackEventType.addressed,
          actorId: actor.id,
          at: DateTime.now().toUtc(),
          round: _controller.state.reviewRound,
          batchId: batchId,
        ),
      ),
    );
    await _feedback.replace(clientId, current, next);
    return next;
  }

  /// Resolves addressed feedback; reviewer-only.
  Future<FeedbackRecord> resolveFeedback({
    required ReviewActor actor,
    required String feedbackId,
  }) async {
    _requireReviewer(actor, 'resolve feedback');
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
    _requireReviewer(actor, 'reopen feedback');
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
    _requireReviewer(actor, 'change blocking classification');
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
    // No C.7 batch dependency exists yet; when batches land they must be
    // checked here so an unresolved dependency blocks approval.
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
