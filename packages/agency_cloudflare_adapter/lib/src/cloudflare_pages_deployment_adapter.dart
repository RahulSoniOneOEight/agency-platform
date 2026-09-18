import 'package:agency_operations_core/agency_operations_core.dart';

/// Constructor-only Cloudflare Pages credential.
///
/// [accountId] and [apiToken] are server/CI secrets. They are never serialized
/// and never rendered by [toString]; [apiToken] is always redacted.
final class CloudflareCredentials {
  const CloudflareCredentials({
    required this.accountId,
    required this.apiToken,
  });

  final String accountId;
  final String apiToken;

  @override
  String toString() =>
      'CloudflareCredentials(accountId: $accountId, apiToken: [REDACTED])';
}

/// Provider deployment lifecycle status.
enum CloudflareDeploymentStatus { queued, inProgress, succeeded, failed }

/// A provider deployment record bound to one exact artifact digest.
final class CloudflareDeployment {
  CloudflareDeployment({
    required this.id,
    required this.environment,
    required this.artifactDigest,
    required this.status,
    this.url,
    Map<String, bool> checks = const {},
    Map<String, Object?> details = const {},
  })  : checks = Map.unmodifiable(checks),
        details = Map.unmodifiable(details);

  final String id;
  final String environment;
  final String? url;
  final String artifactDigest;
  final CloudflareDeploymentStatus status;
  final Map<String, bool> checks;
  final Map<String, Object?> details;
}

/// Narrow, injectable transport seam for the Cloudflare Pages adapter.
///
/// A concrete transport owns every Cloudflare HTTP detail. Tests inject a
/// recording transport, so no network access or credential is required.
abstract interface class CloudflarePagesTransport {
  /// Creates a deployment from an already-built artifact. This never builds
  /// from source; [artifactPath] and [artifactDigest] are supplied by the
  /// caller and forwarded unchanged.
  Future<CloudflareDeployment> createDeployment({
    required String project,
    required String branch,
    required String artifactPath,
    required String artifactDigest,
    required String environment,
    required CloudflareCredentials credentials,
  });

  /// Looks up a deployment by its provider id.
  Future<CloudflareDeployment?> getDeployment(String deploymentId);

  /// Looks up the deployment currently bound to [environment].
  Future<CloudflareDeployment?> currentDeployment(String environment);

  /// Rolls the project back to an existing deployment.
  Future<CloudflareDeployment> rollback({
    required String project,
    required String deploymentId,
    required CloudflareCredentials credentials,
  });
}

/// Cloudflare Pages implementation of the provider-neutral [DeploymentPort].
///
/// The adapter never rebuilds from source. Staging forwards the exact supplied
/// artifact path and digest; production promotion reuses the staged digest and
/// rejects any other digest; rollback targets the supplied known-good
/// deployment and rejects a digest that differs from it, because a new artifact
/// is a new candidate rather than a rollback.
final class CloudflarePagesDeploymentAdapter implements DeploymentPort {
  CloudflarePagesDeploymentAdapter({
    required CloudflarePagesTransport transport,
    required this.project,
    required CloudflareCredentials credentials,
  })  : _transport = transport,
        _credentials = credentials;

  final CloudflarePagesTransport _transport;
  final String project;
  final CloudflareCredentials _credentials;

  String? _stagedArtifactDigest;

  @override
  Future<DeploymentResult> deployStaging(DeploymentRequest request) async {
    final deployment = await _transport.createDeployment(
      project: project,
      branch: request.environment,
      artifactPath: _requireArtifactPath(request),
      artifactDigest: request.artifactDigest,
      environment: request.environment,
      credentials: _credentials,
    );
    _stagedArtifactDigest = request.artifactDigest;
    return _toResult(deployment, request.artifactDigest);
  }

  @override
  Future<DeploymentResult> promoteExactArtifactToProduction(
    DeploymentRequest request,
  ) async {
    final staged = _stagedArtifactDigest;
    if (staged == null) {
      throw StateError(
        'cannot promote to production before a staging artifact is deployed',
      );
    }
    if (staged != request.artifactDigest) {
      throw ArgumentError(
        'promotion artifact digest does not match the staged artifact digest',
      );
    }
    final deployment = await _transport.createDeployment(
      project: project,
      branch: request.environment,
      artifactPath: _requireArtifactPath(request),
      artifactDigest: request.artifactDigest,
      environment: request.environment,
      credentials: _credentials,
    );
    return _toResult(deployment, request.artifactDigest);
  }

  @override
  Future<DeploymentResult> rollbackToKnownGood(DeploymentRequest request) async {
    final knownGoodRef = request.deploymentRef;
    if (knownGoodRef == null || knownGoodRef.trim().isEmpty) {
      throw ArgumentError(
        'rollback requires DeploymentRequest.deploymentRef to name the '
        'known-good deployment',
      );
    }
    final knownGood = await _transport.getDeployment(knownGoodRef);
    if (knownGood == null) {
      throw StateError(
        'known-good deployment $knownGoodRef could not be resolved',
      );
    }
    if (knownGood.artifactDigest != request.artifactDigest) {
      throw ArgumentError(
        'rollback artifact digest does not match the known-good deployment '
        'digest; a new artifact is a new candidate, not a rollback',
      );
    }
    final deployment = await _transport.rollback(
      project: project,
      deploymentId: knownGoodRef,
      credentials: _credentials,
    );
    return _toResult(deployment, request.artifactDigest);
  }

  @override
  Future<DeploymentResult?> currentDeployment(String environment) async {
    final deployment = await _transport.currentDeployment(environment);
    if (deployment == null) {
      return null;
    }
    return _toResult(deployment, deployment.artifactDigest);
  }

  @override
  Future<DeploymentHealth> deploymentHealth(String deploymentId) async {
    final deployment = await _transport.getDeployment(deploymentId);
    if (deployment == null) {
      throw StateError('deployment $deploymentId could not be resolved');
    }
    return DeploymentHealth(
      deploymentId: deployment.id,
      healthy: deployment.status == CloudflareDeploymentStatus.succeeded,
      checks: deployment.checks,
      details: deployment.details,
    );
  }

  String _requireArtifactPath(DeploymentRequest request) {
    final artifactPath = request.artifactRef;
    if (artifactPath == null || artifactPath.trim().isEmpty) {
      throw ArgumentError(
        'DeploymentRequest.artifactRef must be the exact artifact path',
      );
    }
    return artifactPath;
  }

  DeploymentResult _toResult(
    CloudflareDeployment deployment,
    String requestedDigest,
  ) {
    if (deployment.artifactDigest != requestedDigest) {
      throw StateError(
        'provider deployment digest does not match the requested artifact '
        'digest',
      );
    }
    return DeploymentResult(
      deploymentId: deployment.id,
      environment: deployment.environment,
      url: deployment.url,
      artifactDigest: deployment.artifactDigest,
      status: _mapStatus(deployment.status),
    );
  }

  static DeploymentStatus _mapStatus(CloudflareDeploymentStatus status) =>
      switch (status) {
        CloudflareDeploymentStatus.succeeded => DeploymentStatus.succeeded,
        CloudflareDeploymentStatus.failed => DeploymentStatus.failed,
        CloudflareDeploymentStatus.queued ||
        CloudflareDeploymentStatus.inProgress =>
          DeploymentStatus.inProgress,
      };
}
