import 'package:flutter/foundation.dart';

/// Lifecycle status of a deployment operation.
enum DeploymentStatus { succeeded, failed, inProgress }

/// Provider-neutral deployment contract.
///
/// Reference adapter: Cloudflare Pages. Production promotion must deploy the
/// exact authorized artifact and must never rebuild from source.
abstract interface class DeploymentPort {
  Future<DeploymentResult> deployStaging(DeploymentRequest request);

  Future<DeploymentResult> promoteExactArtifactToProduction(
    DeploymentRequest request,
  );

  Future<DeploymentResult> rollbackToKnownGood(DeploymentRequest request);

  Future<DeploymentResult?> currentDeployment(String environment);

  Future<DeploymentHealth> deploymentHealth(String deploymentId);
}

/// A request that binds the exact artifact being deployed or promoted.
///
/// [artifactDigest] must be a canonical `sha256:` digest. [migrationSet] is the
/// exact ordered set of migration identifiers bound to the candidate.
final class DeploymentRequest {
  DeploymentRequest({
    required this.environment,
    required this.artifactDigest,
    required this.sourceSha,
    required this.buildVersion,
    required List<String> migrationSet,
    required this.releaseConfigIdentity,
    this.artifactRef,
    this.deploymentRef,
  }) : migrationSet = List.unmodifiable(migrationSet) {
    _requireNonEmpty(environment, 'environment');
    if (!_artifactDigestPattern.hasMatch(artifactDigest)) {
      throw ArgumentError.value(
        artifactDigest,
        'artifactDigest',
        r'must match ^sha256:[0-9a-f]{64}$',
      );
    }
    _requireNonEmpty(sourceSha, 'sourceSha');
    _requireNonEmpty(buildVersion, 'buildVersion');
    _requireNonEmpty(releaseConfigIdentity, 'releaseConfigIdentity');
  }

  final String environment;
  final String artifactDigest;
  final String sourceSha;
  final String buildVersion;
  final List<String> migrationSet;
  final String releaseConfigIdentity;
  final String? artifactRef;
  final String? deploymentRef;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentRequest &&
          other.environment == environment &&
          other.artifactDigest == artifactDigest &&
          other.sourceSha == sourceSha &&
          other.buildVersion == buildVersion &&
          listEquals(other.migrationSet, migrationSet) &&
          other.releaseConfigIdentity == releaseConfigIdentity &&
          other.artifactRef == artifactRef &&
          other.deploymentRef == deploymentRef;

  @override
  int get hashCode => Object.hash(
        environment,
        artifactDigest,
        sourceSha,
        buildVersion,
        Object.hashAll(migrationSet),
        releaseConfigIdentity,
        artifactRef,
        deploymentRef,
      );

  @override
  String toString() => 'DeploymentRequest(environment: $environment, '
      'artifactDigest: $artifactDigest, sourceSha: $sourceSha, '
      'buildVersion: $buildVersion, migrationSet: $migrationSet, '
      'releaseConfigIdentity: $releaseConfigIdentity, '
      'artifactRef: $artifactRef, deploymentRef: $deploymentRef)';
}

/// The result of a deployment operation.
final class DeploymentResult {
  const DeploymentResult({
    required this.deploymentId,
    required this.environment,
    required this.artifactDigest,
    required this.status,
    this.url,
  });

  final String deploymentId;
  final String environment;
  final String? url;
  final String artifactDigest;
  final DeploymentStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentResult &&
          other.deploymentId == deploymentId &&
          other.environment == environment &&
          other.url == url &&
          other.artifactDigest == artifactDigest &&
          other.status == status;

  @override
  int get hashCode =>
      Object.hash(deploymentId, environment, url, artifactDigest, status);

  @override
  String toString() =>
      'DeploymentResult(deploymentId: $deploymentId, environment: $environment, '
      'url: $url, artifactDigest: $artifactDigest, status: ${status.name})';
}

/// A health snapshot for a deployed artifact.
final class DeploymentHealth {
  DeploymentHealth({
    required this.deploymentId,
    required this.healthy,
    Map<String, bool> checks = const {},
    Map<String, Object?> details = const {},
  })  : checks = Map.unmodifiable(checks),
        details = Map.unmodifiable(details);

  final String deploymentId;
  final bool healthy;
  final Map<String, bool> checks;
  final Map<String, Object?> details;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentHealth &&
          other.deploymentId == deploymentId &&
          other.healthy == healthy &&
          mapEquals(other.checks, checks) &&
          mapEquals(other.details, details);

  @override
  int get hashCode => Object.hash(
        deploymentId,
        healthy,
        Object.hashAll(checks.keys.toList()..sort()),
        Object.hashAll(details.keys.toList()..sort()),
      );

  @override
  String toString() => 'DeploymentHealth(deploymentId: $deploymentId, '
      'healthy: $healthy, checks: $checks, details: $details)';
}

final _artifactDigestPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
