import 'feedback_record.dart';
import 'feedback_repository.dart';
import 'review_actor.dart';
import 'review_controller.dart';
import 'review_domain_error.dart';
import 'review_state.dart';

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
  })  : _controller = controller,
        _feedback = feedbackRepository;

  final ReviewController _controller;
  final FeedbackRepository _feedback;

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
