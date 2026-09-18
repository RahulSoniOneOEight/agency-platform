import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _shaA = '0123456789abcdef0123456789abcdef01234567';
const _shaB = 'fedcba9876543210fedcba9876543210fedcba98';

const _digestA =
    'sha256:1111111111111111111111111111111111111111111111111111111111111111';
const _digestB =
    'sha256:2222222222222222222222222222222222222222222222222222222222222222';
const _configA =
    'sha256:4444444444444444444444444444444444444444444444444444444444444444';

final _startedAt = DateTime.utc(2026, 9, 18, 10, 0, 0);
final _completedAt = DateTime.utc(2026, 9, 18, 10, 5, 0);

ReleaseRecord _record({
  ReleaseOutcome releaseStatus = ReleaseOutcome.healthy,
  String releaseId = 'release-1',
  String clientId = 'reference-commerce',
  String environment = 'production',
  String sourceSha = _shaA,
  String artifactDigest = _digestA,
  String buildVersion = '1.0.0',
  List<String> migrationSet = const ['2026-01-init.sql'],
  String releaseConfigIdentity = _configA,
  String hardeningReportId = 'h2-hardening-report@1',
  String? productionAuthorizationId = 'authorization-1',
  String? stagingEvidence = 'staging-evidence@1',
  String? productionSmokeEvidence = 'production-smoke@1',
  String? telemetryHealthEvidence = 'telemetry-health@1',
  String? deploymentTarget = 'cloudflare:pages/reference-commerce/production',
  List<String> incidentOrAdvisoryRefs = const [],
  String? rollbackOrRecoveryRef,
  String? previousKnownGoodReleaseId,
  DateTime? startedAt,
  DateTime? completedAt,
}) {
  return ReleaseRecord(
    releaseId: releaseId,
    clientId: clientId,
    environment: environment,
    sourceSha: sourceSha,
    artifactDigest: artifactDigest,
    buildVersion: buildVersion,
    migrationSet: migrationSet,
    releaseConfigIdentity: releaseConfigIdentity,
    hardeningReportId: hardeningReportId,
    productionAuthorizationId: productionAuthorizationId,
    stagingEvidence: stagingEvidence,
    productionSmokeEvidence: productionSmokeEvidence,
    telemetryHealthEvidence: telemetryHealthEvidence,
    deploymentTarget: deploymentTarget,
    releaseStatus: releaseStatus,
    incidentOrAdvisoryRefs: incidentOrAdvisoryRefs,
    rollbackOrRecoveryRef: rollbackOrRecoveryRef,
    previousKnownGoodReleaseId: previousKnownGoodReleaseId,
    startedAt: startedAt ?? _startedAt,
    completedAt: completedAt ?? _completedAt,
  );
}

void main() {
  test('a healthy release with all evidence is constructible', () {
    final record = _record();
    expect(record.releaseStatus, ReleaseOutcome.healthy);
    expect(record.releaseIdentity, startsWith('sha256:'));
  });

  test('healthy cannot omit production deployment evidence', () {
    expect(
      () => _record(deploymentTarget: null),
      throwsArgumentError,
    );
  });

  test('healthy cannot omit production smoke evidence', () {
    expect(
      () => _record(productionSmokeEvidence: null),
      throwsArgumentError,
    );
  });

  test('healthy cannot omit telemetry health evidence', () {
    expect(
      () => _record(telemetryHealthEvidence: null),
      throwsArgumentError,
    );
  });

  test('healthy cannot omit the production authorization id', () {
    expect(
      () => _record(productionAuthorizationId: null),
      throwsArgumentError,
    );
    expect(
      () => _record(productionAuthorizationId: ''),
      throwsArgumentError,
    );
  });

  test('degraded requires incident/advisory refs', () {
    expect(
      () => _record(
        releaseStatus: ReleaseOutcome.degraded,
        productionSmokeEvidence: null,
        telemetryHealthEvidence: null,
      ),
      throwsArgumentError,
    );

    final record = _record(
      releaseStatus: ReleaseOutcome.degraded,
      incidentOrAdvisoryRefs: const ['advisory-1'],
    );
    expect(record.releaseStatus, ReleaseOutcome.degraded);
  });

  test('failed requires failure/recovery evidence', () {
    expect(
      () => _record(
        releaseStatus: ReleaseOutcome.failed,
        productionSmokeEvidence: null,
        telemetryHealthEvidence: null,
      ),
      throwsArgumentError,
    );

    final withRollback = _record(
      releaseStatus: ReleaseOutcome.failed,
      productionSmokeEvidence: null,
      telemetryHealthEvidence: null,
      rollbackOrRecoveryRef: 'recovery-report@1',
    );
    expect(withRollback.releaseStatus, ReleaseOutcome.failed);

    final withIncident = _record(
      releaseStatus: ReleaseOutcome.failed,
      productionSmokeEvidence: null,
      telemetryHealthEvidence: null,
      incidentOrAdvisoryRefs: const ['incident-1'],
    );
    expect(withIncident.releaseStatus, ReleaseOutcome.failed);
  });

  test('release identity is stable for identical content', () {
    expect(_record().releaseIdentity, _record().releaseIdentity);
  });

  test('release identity changes when a bound evidence field changes', () {
    expect(
      _record(productionSmokeEvidence: 'production-smoke@1').releaseIdentity,
      isNot(
        _record(productionSmokeEvidence: 'production-smoke@2').releaseIdentity,
      ),
    );
    expect(
      _record(telemetryHealthEvidence: 'telemetry-health@1').releaseIdentity,
      isNot(
        _record(telemetryHealthEvidence: 'telemetry-health@2').releaseIdentity,
      ),
    );
    expect(
      _record(stagingEvidence: 'staging-evidence@1').releaseIdentity,
      isNot(_record(stagingEvidence: 'staging-evidence@2').releaseIdentity),
    );
  });

  test('release identity changes when the authorization changes', () {
    expect(
      _record(productionAuthorizationId: 'authorization-1').releaseIdentity,
      isNot(
        _record(productionAuthorizationId: 'authorization-2').releaseIdentity,
      ),
    );
  });

  test('release identity changes when the artifact digest changes', () {
    expect(
      _record(artifactDigest: _digestA).releaseIdentity,
      isNot(_record(artifactDigest: _digestB).releaseIdentity),
    );
  });

  test('release identity changes when the source SHA changes', () {
    expect(
      _record(sourceSha: _shaA).releaseIdentity,
      isNot(_record(sourceSha: _shaB).releaseIdentity),
    );
  });

  test('release identity changes when the release status changes', () {
    expect(
      _record().releaseIdentity,
      isNot(
        _record(
          releaseStatus: ReleaseOutcome.degraded,
          incidentOrAdvisoryRefs: const ['advisory-1'],
        ).releaseIdentity,
      ),
    );
  });

  test('timestamps are normalized to UTC', () {
    final record = _record(
      startedAt: DateTime.parse('2026-09-18T10:00:00+02:00'),
      completedAt: DateTime.parse('2026-09-18T10:05:00+02:00'),
    );

    expect(record.startedAt.isUtc, isTrue);
    expect(record.startedAt, DateTime.utc(2026, 9, 18, 8, 0, 0));
  });

  test('completedAt before startedAt is rejected', () {
    expect(
      () => _record(
        startedAt: DateTime.utc(2026, 9, 18, 11, 0, 0),
        completedAt: DateTime.utc(2026, 9, 18, 10, 0, 0),
      ),
      throwsArgumentError,
    );
  });

  test('invalid source SHA is rejected', () {
    expect(() => _record(sourceSha: 'nope'), throwsArgumentError);
  });

  test('invalid artifact digest is rejected', () {
    expect(() => _record(artifactDigest: 'sha256:xyz'), throwsArgumentError);
  });

  test('migration set is defensively copied', () {
    final source = <String>['a.sql'];
    final record = _record(migrationSet: source);

    source.add('b.sql');

    expect(record.migrationSet, ['a.sql']);
    expect(() => record.migrationSet.add('c.sql'), throwsUnsupportedError);
  });

  test('incident refs are defensively copied', () {
    final source = <String>['incident-1'];
    final record = _record(
      releaseStatus: ReleaseOutcome.degraded,
      incidentOrAdvisoryRefs: source,
    );

    source.add('incident-2');

    expect(record.incidentOrAdvisoryRefs, ['incident-1']);
    expect(
      () => record.incidentOrAdvisoryRefs.add('incident-3'),
      throwsUnsupportedError,
    );
  });

  test('toJson/fromJson round-trip preserves identity and equality', () {
    final original = _record(
      migrationSet: const ['a.sql', 'b.sql'],
      previousKnownGoodReleaseId: 'release-0',
    );

    final restored = ReleaseRecord.fromJson(original.toJson());

    expect(restored, original);
    expect(restored.releaseIdentity, original.releaseIdentity);
    expect(restored.toJson(), original.toJson());
  });

  test('fromJson rejects a tampered release identity', () {
    final json = _record().toJson()
      ..['release_identity'] = 'sha256:${'0' * 64}';
    expect(() => ReleaseRecord.fromJson(json), throwsArgumentError);
  });

  test('toJson/fromJson round-trip preserves a degraded record', () {
    final original = _record(
      releaseStatus: ReleaseOutcome.degraded,
      productionSmokeEvidence: null,
      telemetryHealthEvidence: null,
      incidentOrAdvisoryRefs: const ['advisory-1'],
    );

    final restored = ReleaseRecord.fromJson(original.toJson());

    expect(restored, original);
    expect(restored.releaseIdentity, original.releaseIdentity);
  });
}
