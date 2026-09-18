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
const _configB =
    'sha256:5555555555555555555555555555555555555555555555555555555555555555';

const _goldenValue = <String, Object?>{
  'client_id': 'caf\u00e9-commerce',
  'migration_set': <Object?>[
    '2026-01-init.sql',
    '2026-02-nested/\u00e9.sql',
  ],
  'nested': <String, Object?>{
    'labels': <Object?>['d\u00e9j\u00e0 vu', 'na\u00efve'],
    'flags': <Object?>[true, false, null],
  },
};

const _delGoldenValue = <String, Object?>{
  'boundary': <Object?>['tilde:~', 'del:\u007f', 'unit:\u001f'],
  'client_id': 'caf\u00e9-\u007f',
};

ReleaseCandidate _candidate({
  String clientId = 'reference-commerce',
  String targetEnvironment = 'production',
  String sourceSha = _shaA,
  String artifactDigest = _digestA,
  String buildVersion = '1.0.0',
  List<String> migrationSet = const ['2026-01-init.sql'],
  String releaseConfigIdentity = _configA,
  String approvedExperienceRef = 'approved-experience@1',
  String h1FoundationReportRef = 'h1-foundation-report@1',
}) {
  return ReleaseCandidate(
    clientId: clientId,
    targetEnvironment: targetEnvironment,
    sourceSha: sourceSha,
    artifactDigest: artifactDigest,
    buildVersion: buildVersion,
    migrationSet: migrationSet,
    releaseConfigIdentity: releaseConfigIdentity,
    approvedExperienceRef: approvedExperienceRef,
    h1FoundationReportRef: h1FoundationReportRef,
  );
}

void main() {
  test('candidate identity is stable for identical field values', () {
    expect(
      _candidate().candidateIdentity,
      _candidate().candidateIdentity,
    );
  });

  test('candidate identity changes when the artifact digest changes', () {
    expect(
      _candidate(artifactDigest: _digestA).candidateIdentity,
      isNot(_candidate(artifactDigest: _digestB).candidateIdentity),
    );
  });

  test('candidate identity changes when the source SHA changes', () {
    expect(
      _candidate(sourceSha: _shaA).candidateIdentity,
      isNot(_candidate(sourceSha: _shaB).candidateIdentity),
    );
  });

  test('candidate identity changes when the target environment changes', () {
    expect(
      _candidate(targetEnvironment: 'production').candidateIdentity,
      isNot(_candidate(targetEnvironment: 'staging').candidateIdentity),
    );
  });

  test('candidate identity changes when the migration set changes', () {
    expect(
      _candidate(migrationSet: const ['2026-01-init.sql']).candidateIdentity,
      isNot(
        _candidate(migrationSet: const ['2026-02-next.sql']).candidateIdentity,
      ),
    );
  });

  test('candidate identity changes when the release config identity changes',
      () {
    expect(
      _candidate(releaseConfigIdentity: _configA).candidateIdentity,
      isNot(_candidate(releaseConfigIdentity: _configB).candidateIdentity),
    );
  });

  test('candidate identity changes when the build version changes', () {
    expect(
      _candidate(buildVersion: '1.0.0').candidateIdentity,
      isNot(_candidate(buildVersion: '1.0.1').candidateIdentity),
    );
  });

  test('candidate identity changes when the client id changes', () {
    expect(
      _candidate(clientId: 'reference-commerce').candidateIdentity,
      isNot(_candidate(clientId: 'other-client').candidateIdentity),
    );
  });

  test('candidate identity changes when the approved experience ref changes',
      () {
    expect(
      _candidate(approvedExperienceRef: 'approved-experience@1')
          .candidateIdentity,
      isNot(
        _candidate(approvedExperienceRef: 'approved-experience@2')
            .candidateIdentity,
      ),
    );
  });

  test('candidate identity changes when the H.1 foundation report ref changes',
      () {
    expect(
      _candidate(h1FoundationReportRef: 'h1-foundation-report@1')
          .candidateIdentity,
      isNot(
        _candidate(h1FoundationReportRef: 'h1-foundation-report@2')
            .candidateIdentity,
      ),
    );
  });

  test('migration set identity changes when the ordered set changes', () {
    expect(
      _candidate(migrationSet: const ['2026-01-init.sql']).migrationSetIdentity,
      isNot(
        _candidate(migrationSet: const ['2026-01-init.sql', '2026-02-next.sql'])
            .migrationSetIdentity,
      ),
    );
  });

  test('migration set identity is order sensitive', () {
    final forward = _candidate(
      migrationSet: const ['2026-01-init.sql', '2026-02-next.sql'],
    );
    final reversed = _candidate(
      migrationSet: const ['2026-02-next.sql', '2026-01-init.sql'],
    );

    expect(forward.migrationSetIdentity, isNot(reversed.migrationSetIdentity));
  });

  test('migration set identity is distinct from candidate identity', () {
    final candidate = _candidate();
    expect(candidate.migrationSetIdentity, isNot(candidate.candidateIdentity));
  });

  test('migration set identity is stable for the same ordered set', () {
    expect(
      _candidate(migrationSet: const ['a.sql', 'b.sql']).migrationSetIdentity,
      _candidate(migrationSet: const ['a.sql', 'b.sql']).migrationSetIdentity,
    );
  });

  test('canonical JSON byte-matches the Python identity convention', () {
    expect(
      canonicalizeJson(_goldenValue),
      r'{"client_id":"caf\u00e9-commerce","migration_set":["2026-01-init.sql","2026-02-nested/\u00e9.sql"],"nested":{"flags":[true,false,null],"labels":["d\u00e9j\u00e0 vu","na\u00efve"]}}',
    );
  });

  test('canonical hash matches the pinned cross-language golden digest', () {
    expect(
      canonicalJsonHash(_goldenValue),
      'sha256:934f8ac3511500a156959782c6a51225d0f3595bbe10d1f40689546eeda6f20c',
    );
  });

  test('canonical JSON escapes U+007F DEL exactly as Python ensure_ascii', () {
    expect(
      canonicalizeJson(_delGoldenValue),
      r'{"boundary":["tilde:~","del:\u007f","unit:\u001f"],"client_id":"caf\u00e9-\u007f"}',
    );
  });

  test('canonical hash matches the pinned DEL cross-language golden digest', () {
    expect(
      canonicalJsonHash(_delGoldenValue),
      'sha256:4524d5df540240cacc11237736ea82483fdd205b875b4b748b1f1c9923c26f9e',
    );
  });

  test('canonicalization rejects numeric values', () {
    expect(() => canonicalizeJson(1), throwsArgumentError);
    expect(() => canonicalizeJson(1.5), throwsArgumentError);
    expect(() => canonicalizeJson(<String, Object?>{'n': 0}), throwsArgumentError);
    expect(() => canonicalizeJson(<Object?>[1]), throwsArgumentError);
  });

  test('canonicalization rejects non-String map keys with ArgumentError', () {
    expect(
      () => canonicalizeJson(<Object?, Object?>{1: 'value'}),
      throwsArgumentError,
    );
    expect(
      () => canonicalizeJson(<Object?, Object?>{null: 'value'}),
      throwsArgumentError,
    );
  });

  test('toString includes the migration set identity', () {
    final candidate = _candidate();
    expect(candidate.toString(), contains(candidate.migrationSetIdentity));
  });

  test('fromJson rejects a tampered candidate identity', () {
    final json = _candidate().toJson()
      ..['candidate_identity'] = 'sha256:${'0' * 64}';
    expect(() => ReleaseCandidate.fromJson(json), throwsArgumentError);
  });

  test('fromJson rejects a tampered migration set identity', () {
    final json = _candidate().toJson()
      ..['migration_set_identity'] = 'sha256:${'0' * 64}';
    expect(() => ReleaseCandidate.fromJson(json), throwsArgumentError);
  });

  test('invalid source SHA is rejected', () {
    expect(() => _candidate(sourceSha: 'not-a-sha'), throwsArgumentError);
    expect(() => _candidate(sourceSha: 'A' * 40), throwsArgumentError);
    expect(() => _candidate(sourceSha: 'a' * 39), throwsArgumentError);
  });

  test('invalid artifact digest is rejected', () {
    expect(() => _candidate(artifactDigest: 'abc'), throwsArgumentError);
    expect(
      () => _candidate(artifactDigest: 'sha256:${'g' * 64}'),
      throwsArgumentError,
    );
    expect(
      () => _candidate(artifactDigest: 'sha256:${'a' * 63}'),
      throwsArgumentError,
    );
  });

  test('invalid release config identity is rejected', () {
    expect(
      () => _candidate(releaseConfigIdentity: 'sha256:not-hex'),
      throwsArgumentError,
    );
  });

  test('migration set is defensively copied', () {
    final source = <String>['a.sql'];
    final candidate = _candidate(migrationSet: source);

    source.add('b.sql');

    expect(candidate.migrationSet, ['a.sql']);
    expect(() => candidate.migrationSet.add('c.sql'), throwsUnsupportedError);
  });

  test('toJson/fromJson round-trip preserves identity and equality', () {
    final original = _candidate(
      migrationSet: const ['a.sql', 'b.sql'],
      targetEnvironment: 'staging',
    );

    final restored = ReleaseCandidate.fromJson(original.toJson());

    expect(restored, original);
    expect(restored.candidateIdentity, original.candidateIdentity);
    expect(restored.migrationSetIdentity, original.migrationSetIdentity);
    expect(restored.toJson(), original.toJson());
  });
}
