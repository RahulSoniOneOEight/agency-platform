/// Typed, machine-readable domain errors for cross-domain review operations.
///
/// Each error carries a stable [code] so callers (UI, tooling, persistence) can
/// branch deterministically; UI copy may map these to human-friendly messages.
/// Later cycles add approval/visual/batch errors to this sealed hierarchy.
sealed class ReviewDomainError implements Exception {
  const ReviewDomainError(this.message);

  /// Human-readable description; not intended as a stable identifier.
  final String message;

  /// Stable machine-readable error code.
  String get code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// A lifecycle transition that the feedback state machine does not allow.
final class InvalidFeedbackTransition extends ReviewDomainError {
  const InvalidFeedbackTransition(super.message);

  @override
  String get code => 'invalid_feedback_transition';
}

/// A feedback target that is not valid for the selected scope.
final class InvalidFeedbackTarget extends ReviewDomainError {
  const InvalidFeedbackTarget(super.message);

  @override
  String get code => 'invalid_feedback_target';
}

/// An action attempted by an actor without the required review authority.
final class UnauthorizedReviewAction extends ReviewDomainError {
  const UnauthorizedReviewAction(super.message);

  @override
  String get code => 'unauthorized_review_action';
}

/// A review round cannot close while blocking feedback is unresolved.
final class BlockingFeedbackUnresolved extends ReviewDomainError {
  const BlockingFeedbackUnresolved(super.message);

  @override
  String get code => 'blocking_feedback_unresolved';
}

/// A review round is not in a state that can be closed.
final class ReviewRoundNotClosable extends ReviewDomainError {
  const ReviewRoundNotClosable(super.message);

  @override
  String get code => 'review_round_not_closable';
}

/// Readiness was requested outside the coordinator's round-close authority.
///
/// `ready_for_final_review` is reachable only through
/// `ReviewCoordinator.closeCurrentRound`; the interactive status control must
/// never set it directly.
final class ReadinessRequiresRoundClose extends ReviewDomainError {
  const ReadinessRequiresRoundClose(super.message);

  @override
  String get code => 'readiness_requires_round_close';
}

/// A feedback id that is already referenced or persisted.
final class DuplicateFeedbackId extends ReviewDomainError {
  const DuplicateFeedbackId(super.message);

  @override
  String get code => 'duplicate_feedback_id';
}

/// A referenced feedback record does not exist.
final class FeedbackNotFound extends ReviewDomainError {
  const FeedbackNotFound(super.message);

  @override
  String get code => 'feedback_not_found';
}

/// A candidate ReviewState failed normalization/validation.
final class InvalidReviewState extends ReviewDomainError {
  const InvalidReviewState(super.message);

  @override
  String get code => 'invalid_review_state';
}

/// Approval was requested while one or more eligibility gates failed.
///
/// Every gate (readiness, blocking feedback, valid C.3 decision tree, recorded
/// reviewer/approver identities, source commit SHA, review-state hash) reports
/// through this single stable code; no partial approval is ever persisted.
final class ApprovalNotEligible extends ReviewDomainError {
  const ApprovalNotEligible(super.message);

  @override
  String get code => 'approval_not_eligible';
}

/// An approval version already exists; approvals are append-only.
final class ApprovalVersionConflict extends ReviewDomainError {
  const ApprovalVersionConflict(super.message);

  @override
  String get code => 'approval_version_conflict';
}

/// A contract-impacting change requires a new review round before re-approval.
final class ContractImpactRequiresNewRound extends ReviewDomainError {
  const ContractImpactRequiresNewRound(super.message);

  @override
  String get code => 'contract_impact_requires_new_round';
}

/// A visual annotation payload is structurally or numerically invalid.
final class InvalidVisualAnnotation extends ReviewDomainError {
  const InvalidVisualAnnotation(super.message);

  @override
  String get code => 'invalid_visual_annotation';
}

/// A visual feedback provider payload could not be normalized.
final class UnsupportedVisualProviderPayload extends ReviewDomainError {
  const UnsupportedVisualProviderPayload(super.message);

  @override
  String get code => 'unsupported_visual_provider_payload';
}
