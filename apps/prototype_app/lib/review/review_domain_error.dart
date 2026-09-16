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
