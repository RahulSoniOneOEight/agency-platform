/// Typed, machine-readable domain errors for the automated QA subsystem.
///
/// Each error carries a stable [code] so callers (UI, tooling, persistence, CI)
/// can branch deterministically instead of parsing prose. QA errors are
/// deliberately separate from [ReviewDomainError]: automated QA failures must
/// never be confused with human review/approval authority.
library;

/// Base class for every QA-domain failure.
sealed class QaDomainError implements Exception {
  const QaDomainError(this.message);

  /// Human-readable description; not intended as a stable identifier.
  final String message;

  /// Stable machine-readable error code.
  String get code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// A [QaFinding] is structurally or semantically invalid.
final class InvalidQaFinding extends QaDomainError {
  const InvalidQaFinding(super.message);

  @override
  String get code => 'invalid_qa_finding';
}

/// A normalized evidence region is outside the [0, 1] unit square.
final class InvalidQaRegion extends QaDomainError {
  const InvalidQaRegion(super.message);

  @override
  String get code => 'invalid_qa_region';
}

/// An evidence entry carries no region, reference, or note.
final class InvalidQaEvidence extends QaDomainError {
  const InvalidQaEvidence(super.message);

  @override
  String get code => 'invalid_qa_evidence';
}

/// A finding lifecycle transition the state machine does not allow.
final class InvalidQaTransition extends QaDomainError {
  const InvalidQaTransition(super.message);

  @override
  String get code => 'invalid_qa_transition';
}

/// An operation required evidence (a reason, reference, or feedback link) that
/// was not supplied.
final class QaEvidenceMissing extends QaDomainError {
  const QaEvidenceMissing(super.message);

  @override
  String get code => 'qa_evidence_missing';
}

/// A finding is not in a state that may be promoted into human review.
final class QaFindingNotPromotable extends QaDomainError {
  const QaFindingNotPromotable(super.message);

  @override
  String get code => 'qa_finding_not_promotable';
}

/// A finding id that is already persisted.
final class DuplicateQaFindingId extends QaDomainError {
  const DuplicateQaFindingId(super.message);

  @override
  String get code => 'duplicate_qa_finding_id';
}

/// A referenced QA finding does not exist.
final class QaFindingNotFound extends QaDomainError {
  const QaFindingNotFound(super.message);

  @override
  String get code => 'qa_finding_not_found';
}

/// A persisted finding changed since it was read (stale write).
final class QaFindingChangedSinceRead extends QaDomainError {
  const QaFindingChangedSinceRead(super.message);

  @override
  String get code => 'qa_finding_changed_since_read';
}
