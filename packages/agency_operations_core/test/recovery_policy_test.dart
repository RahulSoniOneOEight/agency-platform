import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _knownGoodDigest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newArtifactDigest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final _policy = RecoveryPolicy(allowApplicationRollbackToKnownGood: true);

RecoveryRequest _request({
  required RecoveryAction action,
  bool migrationReversible = false,
  String target = _knownGoodDigest,
  String authorized = _knownGoodDigest,
}) {
  return RecoveryRequest(
    action: action,
    migrationReversible: migrationReversible,
    targetArtifactDigest: target,
    authorizedArtifactDigest: authorized,
  );
}

void main() {
  test('blocking severity is policy data, not inferred from provider', () {
    final finding = HardeningFinding(
      id: 'security-1',
      area: HardeningArea.security,
      severity: HardeningSeverity.high,
      disposition: GateDisposition.blocking,
      summary: 'example',
    );
    expect(finding.disposition, GateDisposition.blocking);
    expect(finding.status, FindingStatus.open);
    expect(finding.blocksRelease, isTrue);
  });

  test('HardeningFinding defensively copies evidenceRefs', () {
    final source = <String>['evidence-1'];
    final finding = HardeningFinding(
      id: 'security-2',
      area: HardeningArea.security,
      severity: HardeningSeverity.medium,
      disposition: GateDisposition.advisory,
      summary: 'example',
      evidenceRefs: source,
    );

    source.add('evidence-2');

    expect(finding.evidenceRefs, ['evidence-1']);
    expect(() => finding.evidenceRefs.add('evidence-3'), throwsUnsupportedError);
  });

  test('previous-known-good application rollback may be allowed', () {
    final decision = _policy.evaluate(
      _request(action: RecoveryAction.applicationRollbackToKnownGood),
    );

    expect(decision.permitted, isTrue);
    expect(decision.outcome, RecoveryOutcome.permitted);
  });

  test('application rollback is halted when the policy forbids it', () {
    final policy = RecoveryPolicy(allowApplicationRollbackToKnownGood: false);

    final decision = policy.evaluate(
      _request(action: RecoveryAction.applicationRollbackToKnownGood),
    );

    expect(decision.permitted, isFalse);
    expect(decision.outcome, RecoveryOutcome.manualHaltRequired);
  });

  test('a different/new artifact digest is rejected as rollback', () {
    final decision = _policy.evaluate(
      _request(
        action: RecoveryAction.applicationRollbackToKnownGood,
        target: _newArtifactDigest,
        authorized: _knownGoodDigest,
      ),
    );

    expect(decision.permitted, isFalse);
    expect(decision.outcome, RecoveryOutcome.denied);
  });

  test('database reversal requires migrationReversible == true', () {
    final reversible = _policy.evaluate(
      _request(
        action: RecoveryAction.databaseReverseMigration,
        migrationReversible: true,
      ),
    );
    expect(reversible.permitted, isTrue);

    final nonReversible = _policy.evaluate(
      _request(
        action: RecoveryAction.databaseReverseMigration,
        migrationReversible: false,
      ),
    );
    expect(nonReversible.permitted, isFalse);
    expect(nonReversible.outcome, RecoveryOutcome.forwardRecoveryRequired);
  });

  test('non-reversible migration yields forward recovery rather than reverse '
      'execution', () {
    final decision = _policy.evaluate(
      _request(
        action: RecoveryAction.databaseReverseMigration,
        migrationReversible: false,
      ),
    );

    expect(decision.requiresForwardRecovery, isTrue);
    expect(decision.requiresManualHalt, isFalse);
    expect(decision.permitted, isFalse);
  });

  test('non-reversible migration halts when forward recovery is not required',
      () {
    final policy = RecoveryPolicy(
      allowApplicationRollbackToKnownGood: true,
      forwardRecoveryRequired: false,
    );

    final decision = policy.evaluate(
      _request(
        action: RecoveryAction.databaseReverseMigration,
        migrationReversible: false,
      ),
    );

    expect(decision.outcome, RecoveryOutcome.manualHaltRequired);
    expect(decision.permitted, isFalse);
  });

  test('database reversal is never authorized when the policy disallows it',
      () {
    final policy = RecoveryPolicy(
      allowApplicationRollbackToKnownGood: true,
      allowDatabaseReverseMigration: false,
    );

    final decision = policy.evaluate(
      _request(
        action: RecoveryAction.databaseReverseMigration,
        migrationReversible: true,
      ),
    );

    expect(decision.permitted, isFalse);
  });

  test('allowed recovery modes preserve declared order', () {
    final policy = RecoveryPolicy(
      allowApplicationRollbackToKnownGood: true,
      allowedRecoveryModes: [
        RecoveryAction.forwardRecoveryMigration,
        RecoveryAction.applicationRollbackToKnownGood,
        RecoveryAction.manualHalt,
      ],
    );

    expect(policy.allowedRecoveryModes.first,
        RecoveryAction.forwardRecoveryMigration);
    expect(policy.allows(RecoveryAction.manualHalt), isTrue);
    expect(policy.allows(RecoveryAction.databaseReverseMigration), isFalse);
  });

  test('RecoveryPolicy defensively copies allowedRecoveryModes', () {
    final modes = <RecoveryAction>[RecoveryAction.manualHalt];
    final policy = RecoveryPolicy(
      allowApplicationRollbackToKnownGood: true,
      allowedRecoveryModes: modes,
    );

    modes.add(RecoveryAction.databaseReverseMigration);

    expect(policy.allowedRecoveryModes, [RecoveryAction.manualHalt]);
    expect(
      () => policy.allowedRecoveryModes.add(
        RecoveryAction.forwardRecoveryMigration,
      ),
      throwsUnsupportedError,
    );
  });

  test('forward recovery and manual halt are permitted modes', () {
    final forward = _policy.evaluate(
      _request(action: RecoveryAction.forwardRecoveryMigration),
    );
    final halt = _policy.evaluate(
      _request(action: RecoveryAction.manualHalt),
    );

    expect(forward.permitted, isTrue);
    expect(halt.permitted, isTrue);
  });
}
