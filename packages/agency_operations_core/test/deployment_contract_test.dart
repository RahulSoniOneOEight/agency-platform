import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _validDigest =
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _otherDigest =
    'sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

DeploymentRequest _request({String digest = _validDigest}) {
  return DeploymentRequest(
    environment: 'staging',
    artifactDigest: digest,
    sourceSha: 'abc123def456',
    buildVersion: '1.0.0+1',
    migrationSet: const ['202609180001_reference_commerce_foundation.sql'],
    releaseConfigIdentity: 'release-config-1',
  );
}

/// A deployment fake with no build capability by design.
///
/// It records the exact requests it receives and can never produce a new
/// artifact: promotion is accepted only when it reuses the exact artifact
/// digest previously deployed to staging, and is rejected otherwise.
class FakeDeploymentPort implements DeploymentPort {
  final List<DeploymentRequest> stagingDeployments = [];
  final List<DeploymentRequest> productionPromotions = [];
  final List<DeploymentRequest> rollbacks = [];
  String? _stagingDigest;
  DeploymentResult? _current;
  DeploymentHealth? _health;

  @override
  Future<DeploymentResult> deployStaging(DeploymentRequest request) async {
    stagingDeployments.add(request);
    _stagingDigest = request.artifactDigest;
    _current = DeploymentResult(
      deploymentId: 'staging-1',
      environment: request.environment,
      artifactDigest: request.artifactDigest,
      status: DeploymentStatus.succeeded,
      url: 'https://staging.example',
    );
    return _current!;
  }

  @override
  Future<DeploymentResult> promoteExactArtifactToProduction(
    DeploymentRequest request,
  ) async {
    if (request.artifactDigest != _stagingDigest) {
      throw StateError(
        'Promotion must reuse the exact artifact digest deployed to staging; '
        'the fake refuses to rebuild or substitute an artifact.',
      );
    }
    productionPromotions.add(request);
    _current = DeploymentResult(
      deploymentId: 'production-1',
      environment: request.environment,
      artifactDigest: request.artifactDigest,
      status: DeploymentStatus.succeeded,
      url: 'https://production.example',
    );
    return _current!;
  }

  @override
  Future<DeploymentResult> rollbackToKnownGood(DeploymentRequest request) async {
    rollbacks.add(request);
    return DeploymentResult(
      deploymentId: 'rollback-1',
      environment: request.environment,
      artifactDigest: request.artifactDigest,
      status: DeploymentStatus.succeeded,
    );
  }

  @override
  Future<DeploymentResult?> currentDeployment(String environment) async {
    return _current;
  }

  @override
  Future<DeploymentHealth> deploymentHealth(String deploymentId) async {
    _health = DeploymentHealth(
      deploymentId: deploymentId,
      healthy: true,
      checks: const {'http': true},
    );
    return _health!;
  }
}

void main() {
  test('DeploymentRequest accepts a canonical sha256 digest', () {
    final request = _request();
    expect(request.artifactDigest, _validDigest);
    expect(request.migrationSet, hasLength(1));
  });

  test('DeploymentRequest rejects a malformed artifact digest', () {
    final malformed = <String>[
      'sha256:abc',
      '0123456789abcdef',
      'sha256:${'A' * 64}',
      'sha256:${'z' * 64}',
      'sha512:${'a' * 64}',
    ];

    for (final digest in malformed) {
      expect(
        () => _request(digest: digest),
        throwsA(isA<ArgumentError>()),
        reason: 'expected $digest to be rejected',
      );
    }
  });

  test('promotion receives the exact digest deployed to staging', () async {
    final port = FakeDeploymentPort();
    final request = _request();

    final staging = await port.deployStaging(request);
    final production =
        await port.promoteExactArtifactToProduction(request);

    expect(port.productionPromotions.single.artifactDigest,
        staging.artifactDigest);
    expect(port.productionPromotions.single.artifactDigest,
        production.artifactDigest);
    expect(port.productionPromotions.single.artifactDigest, _validDigest);
    expect(port.productionPromotions.single, equals(port.stagingDeployments.single));
  });

  test('promotion reuses the exact staging digest and rejects a different '
      'artifact', () async {
    final port = FakeDeploymentPort();
    final request = _request();

    await port.deployStaging(request);
    await port.promoteExactArtifactToProduction(request);

    expect(
      port.productionPromotions.single.artifactDigest,
      port.stagingDeployments.single.artifactDigest,
    );
    expect(
      port.productionPromotions.single.artifactDigest,
      request.artifactDigest,
    );

    expect(
      () => port.promoteExactArtifactToProduction(_request(digest: _otherDigest)),
      throwsA(isA<StateError>()),
    );
    expect(port.productionPromotions, hasLength(1));
  });

  test('rollback and deployment queries are provider neutral', () async {
    final port = FakeDeploymentPort();
    final request = _request();

    await port.deployStaging(request);
    final current = await port.currentDeployment('staging');
    final health = await port.deploymentHealth('staging-1');
    final rollback = await port.rollbackToKnownGood(request);

    expect(current?.artifactDigest, _validDigest);
    expect(health.healthy, isTrue);
    expect(health.checks['http'], isTrue);
    expect(rollback.status, DeploymentStatus.succeeded);
  });

  test('DeploymentResult and DeploymentHealth have value equality', () {
    const first = DeploymentResult(
      deploymentId: 'd-1',
      environment: 'production',
      artifactDigest: _validDigest,
      status: DeploymentStatus.succeeded,
      url: 'https://example',
    );
    const second = DeploymentResult(
      deploymentId: 'd-1',
      environment: 'production',
      artifactDigest: _validDigest,
      status: DeploymentStatus.succeeded,
      url: 'https://example',
    );
    expect(first, equals(second));
    expect(first.hashCode, second.hashCode);

    final healthA = DeploymentHealth(
      deploymentId: 'd-1',
      healthy: true,
      checks: const {'http': true},
      details: const {'latency_ms': 12},
    );
    final healthB = DeploymentHealth(
      deploymentId: 'd-1',
      healthy: true,
      checks: const {'http': true},
      details: const {'latency_ms': 12},
    );
    expect(healthA, equals(healthB));
  });
}
