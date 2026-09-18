import 'package:flutter/foundation.dart';

/// Ordered recovery modes that a [RecoveryPolicy] may authorize.
enum RecoveryAction {
  applicationRollbackToKnownGood,
  databaseReverseMigration,
  forwardRecoveryMigration,
  manualHalt,
}

/// Outcome of evaluating a [RecoveryRequest] against a [RecoveryPolicy].
enum RecoveryOutcome {
  permitted,
  denied,
  forwardRecoveryRequired,
  manualHaltRequired,
}

/// A requested recovery expressed with provider-neutral values.
///
/// [targetArtifactDigest] is the artifact the operator asks to move to.
/// [authorizedArtifactDigest] is the previous-known-good artifact digest that
/// the release-record chain and recovery policy authorize for rollback. A
/// target that differs from the authorized digest is a new artifact, not a
/// rollback.
final class RecoveryRequest {
  const RecoveryRequest({
    required this.action,
    required this.migrationReversible,
    required this.targetArtifactDigest,
    required this.authorizedArtifactDigest,
  });

  final RecoveryAction action;
  final bool migrationReversible;
  final String targetArtifactDigest;
  final String authorizedArtifactDigest;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecoveryRequest &&
          other.action == action &&
          other.migrationReversible == migrationReversible &&
          other.targetArtifactDigest == targetArtifactDigest &&
          other.authorizedArtifactDigest == authorizedArtifactDigest;

  @override
  int get hashCode => Object.hash(
        action,
        migrationReversible,
        targetArtifactDigest,
        authorizedArtifactDigest,
      );

  @override
  String toString() => 'RecoveryRequest(action: ${action.name}, '
      'migrationReversible: $migrationReversible, '
      'targetArtifactDigest: $targetArtifactDigest, '
      'authorizedArtifactDigest: $authorizedArtifactDigest)';
}

/// The policy decision for a [RecoveryRequest].
final class RecoveryDecision {
  const RecoveryDecision({
    required this.action,
    required this.outcome,
    required this.reason,
  });

  final RecoveryAction action;
  final RecoveryOutcome outcome;
  final String reason;

  bool get permitted => outcome == RecoveryOutcome.permitted;

  bool get requiresForwardRecovery =>
      outcome == RecoveryOutcome.forwardRecoveryRequired;

  bool get requiresManualHalt =>
      outcome == RecoveryOutcome.manualHaltRequired;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecoveryDecision &&
          other.action == action &&
          other.outcome == outcome &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(action, outcome, reason);

  @override
  String toString() =>
      'RecoveryDecision(action: ${action.name}, outcome: ${outcome.name}, '
      'reason: $reason)';
}

/// Pre-authorized, provider-neutral recovery policy.
///
/// The policy encodes whether automated application rollback to the previous
/// known-good artifact is allowed, whether database reversal requires an
/// explicitly reversible migration, and whether a blocked reversal falls back
/// to forward recovery or a manual halt. [allowedRecoveryModes] preserves the
/// declared order of authorized modes.
final class RecoveryPolicy {
  const RecoveryPolicy({
    required this.allowApplicationRollbackToKnownGood,
    this.requireReversibleMigrationForDatabaseRollback = true,
    this.forwardRecoveryRequired = true,
    this.allowedRecoveryModes = const [
      RecoveryAction.applicationRollbackToKnownGood,
      RecoveryAction.databaseReverseMigration,
      RecoveryAction.forwardRecoveryMigration,
    ],
  });

  final bool allowApplicationRollbackToKnownGood;
  final bool requireReversibleMigrationForDatabaseRollback;
  final bool forwardRecoveryRequired;
  final List<RecoveryAction> allowedRecoveryModes;

  bool allows(RecoveryAction action) => allowedRecoveryModes.contains(action);

  RecoveryDecision evaluate(RecoveryRequest request) {
    switch (request.action) {
      case RecoveryAction.applicationRollbackToKnownGood:
        if (!allowApplicationRollbackToKnownGood) {
          return RecoveryDecision(
            action: request.action,
            outcome: RecoveryOutcome.manualHaltRequired,
            reason: 'Application rollback to known good is not authorized '
                'by the recovery policy.',
          );
        }
        if (!allows(RecoveryAction.applicationRollbackToKnownGood)) {
          return RecoveryDecision(
            action: request.action,
            outcome: RecoveryOutcome.denied,
            reason: 'Application rollback to known good is not an allowed '
                'recovery mode.',
          );
        }
        if (request.targetArtifactDigest != request.authorizedArtifactDigest) {
          return RecoveryDecision(
            action: request.action,
            outcome: RecoveryOutcome.denied,
            reason: 'Target artifact digest is not the authorized '
                'previous-known-good artifact; a different artifact is a new '
                'candidate, not a rollback.',
          );
        }
        return RecoveryDecision(
          action: request.action,
          outcome: RecoveryOutcome.permitted,
          reason: 'Rolling back to the authorized previous-known-good '
              'artifact is permitted.',
        );

      case RecoveryAction.databaseReverseMigration:
        if (!allows(RecoveryAction.databaseReverseMigration)) {
          return RecoveryDecision(
            action: request.action,
            outcome: RecoveryOutcome.denied,
            reason: 'Database reverse migration is not an allowed recovery mode.',
          );
        }
        if (!request.migrationReversible) {
          return _forwardOrHalt(
            request.action,
            'The exact migration is not reversible; reverse execution is '
            'prohibited.',
          );
        }
        if (!requireReversibleMigrationForDatabaseRollback) {
          return _forwardOrHalt(
            request.action,
            'The recovery policy does not require reversible migrations, so '
            'database reversal cannot be authorized.',
          );
        }
        return RecoveryDecision(
          action: request.action,
          outcome: RecoveryOutcome.permitted,
          reason: 'The exact migration is reversible and database reversal is '
              'permitted.',
        );

      case RecoveryAction.forwardRecoveryMigration:
        if (!allows(RecoveryAction.forwardRecoveryMigration)) {
          return RecoveryDecision(
            action: request.action,
            outcome: RecoveryOutcome.denied,
            reason: 'Forward recovery migration is not an allowed recovery mode.',
          );
        }
        return RecoveryDecision(
          action: request.action,
          outcome: RecoveryOutcome.permitted,
          reason: 'Forward recovery migration is permitted.',
        );

      case RecoveryAction.manualHalt:
        return RecoveryDecision(
          action: request.action,
          outcome: RecoveryOutcome.permitted,
          reason: 'Manual halt is always permitted.',
        );
    }
  }

  RecoveryDecision _forwardOrHalt(RecoveryAction action, String reason) {
    if (forwardRecoveryRequired) {
      return RecoveryDecision(
        action: action,
        outcome: RecoveryOutcome.forwardRecoveryRequired,
        reason: '$reason Use a forward recovery migration.',
      );
    }
    return RecoveryDecision(
      action: action,
      outcome: RecoveryOutcome.manualHaltRequired,
      reason: '$reason Halt and require manual recovery.',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecoveryPolicy &&
          other.allowApplicationRollbackToKnownGood ==
              allowApplicationRollbackToKnownGood &&
          other.requireReversibleMigrationForDatabaseRollback ==
              requireReversibleMigrationForDatabaseRollback &&
          other.forwardRecoveryRequired == forwardRecoveryRequired &&
          listEquals(other.allowedRecoveryModes, allowedRecoveryModes);

  @override
  int get hashCode => Object.hash(
        allowApplicationRollbackToKnownGood,
        requireReversibleMigrationForDatabaseRollback,
        forwardRecoveryRequired,
        Object.hashAll(allowedRecoveryModes),
      );

  @override
  String toString() =>
      'RecoveryPolicy(allowApplicationRollbackToKnownGood: '
      '$allowApplicationRollbackToKnownGood, '
      'requireReversibleMigrationForDatabaseRollback: '
      '$requireReversibleMigrationForDatabaseRollback, '
      'forwardRecoveryRequired: $forwardRecoveryRequired, '
      'allowedRecoveryModes: $allowedRecoveryModes)';
}
