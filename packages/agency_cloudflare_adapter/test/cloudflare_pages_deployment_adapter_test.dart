import 'dart:io';

import 'package:agency_cloudflare_adapter/agency_cloudflare_adapter.dart';
import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

String _digest(String character) => 'sha256:${character * 64}';

final _digestA = _digest('a');
final _digestB = _digest('b');

/// Recording transport: no network, no credentials, full call capture.
final class RecordingCloudflareTransport implements CloudflarePagesTransport {
  RecordingCloudflareTransport({this.responseDigestOverride});

  final String? responseDigestOverride;

  final List<
      ({
        String project,
        String branch,
        String artifactPath,
        String artifactDigest,
        String environment,
      })> creates = <
      ({
        String project,
        String branch,
        String artifactPath,
        String artifactDigest,
        String environment,
      })>[];
  final List<({String project, String deploymentId})> rollbacks =
      <({String project, String deploymentId})>[];
  final Map<String, CloudflareDeployment> deployments =
      <String, CloudflareDeployment>{};
  CloudflareDeployment? current;

  @override
  Future<CloudflareDeployment> createDeployment({
    required String project,
    required String branch,
    required String artifactPath,
    required String artifactDigest,
    required String environment,
    required CloudflareCredentials credentials,
  }) async {
    creates.add((
      project: project,
      branch: branch,
      artifactPath: artifactPath,
      artifactDigest: artifactDigest,
      environment: environment,
    ));
    return CloudflareDeployment(
      id: 'deployment-${creates.length}',
      environment: environment,
      artifactDigest: responseDigestOverride ?? artifactDigest,
      status: CloudflareDeploymentStatus.succeeded,
      url: 'https://$environment.example.pages.dev',
    );
  }

  @override
  Future<CloudflareDeployment?> getDeployment(String deploymentId) async =>
      deployments[deploymentId];

  @override
  Future<CloudflareDeployment?> currentDeployment(String environment) async =>
      current;

  @override
  Future<CloudflareDeployment> rollback({
    required String project,
    required String deploymentId,
    required CloudflareCredentials credentials,
  }) async {
    rollbacks.add((project: project, deploymentId: deploymentId));
    final target = deployments[deploymentId]!;
    return CloudflareDeployment(
      id: target.id,
      environment: 'production',
      artifactDigest: target.artifactDigest,
      status: CloudflareDeploymentStatus.succeeded,
      url: target.url,
    );
  }
}

CloudflarePagesDeploymentAdapter _adapter(
  RecordingCloudflareTransport transport,
) =>
    CloudflarePagesDeploymentAdapter(
      transport: transport,
      project: 'agency-platform',
      credentials: const CloudflareCredentials(
        accountId: 'acct-1',
        apiToken: 'api-token-xyz',
      ),
    );

DeploymentRequest _request({
  required String digest,
  required String environment,
  String artifactRef = '/artifacts/app.tar.gz',
  String? deploymentRef,
}) =>
    DeploymentRequest(
      environment: environment,
      artifactDigest: digest,
      sourceSha: 'src-1',
      buildVersion: '1.0.0',
      migrationSet: const <String>[],
      releaseConfigIdentity: 'cfg-1',
      artifactRef: artifactRef,
      deploymentRef: deploymentRef,
    );

void main() {
  group('CloudflarePagesDeploymentAdapter staging', () {
    test('sends the exact supplied artifact path and digest', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await adapter.deployStaging(
        _request(digest: _digestA, environment: 'staging'),
      );

      final call = transport.creates.single;
      expect(call.project, 'agency-platform');
      expect(call.environment, 'staging');
      expect(call.artifactPath, '/artifacts/app.tar.gz');
      expect(call.artifactDigest, _digestA);
    });

    test('maps the provider response to a DeploymentResult', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      final result = await adapter.deployStaging(
        _request(digest: _digestA, environment: 'staging'),
      );

      expect(result.deploymentId, 'deployment-1');
      expect(result.environment, 'staging');
      expect(result.artifactDigest, _digestA);
      expect(result.status, DeploymentStatus.succeeded);
      expect(result.url, 'https://staging.example.pages.dev');
    });
  });

  group('CloudflarePagesDeploymentAdapter production promotion', () {
    test('promotes the exact staged digest without rebuilding', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await adapter.deployStaging(
        _request(digest: _digestA, environment: 'staging'),
      );
      final result = await adapter.promoteExactArtifactToProduction(
        _request(digest: _digestA, environment: 'production'),
      );

      expect(transport.creates, hasLength(2));
      expect(transport.creates[1].artifactDigest, _digestA);
      expect(transport.creates[1].environment, 'production');
      expect(result.artifactDigest, _digestA);
    });

    test('rejects a promotion whose digest differs from the staged artifact',
        () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await adapter.deployStaging(
        _request(digest: _digestA, environment: 'staging'),
      );

      await expectLater(
        adapter.promoteExactArtifactToProduction(
          _request(digest: _digestB, environment: 'production'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.creates, hasLength(1));
    });

    test('rejects a promotion before any staging deployment', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.promoteExactArtifactToProduction(
          _request(digest: _digestA, environment: 'production'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(transport.creates, isEmpty);
    });

    test('rejects a provider response bound to a different digest', () async {
      final transport = RecordingCloudflareTransport(
        responseDigestOverride: _digestB,
      );
      final adapter = _adapter(transport);

      await expectLater(
        adapter.deployStaging(
          _request(digest: _digestA, environment: 'staging'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a mismatched provider digest leaves no staged digest', () async {
      final transport = RecordingCloudflareTransport(
        responseDigestOverride: _digestB,
      );
      final adapter = _adapter(transport);

      await expectLater(
        adapter.deployStaging(
          _request(digest: _digestA, environment: 'staging'),
        ),
        throwsA(isA<StateError>()),
      );

      // Because the failed staging must not have recorded a staged digest, a
      // later promotion of that same digest is rejected as "no staging".
      await expectLater(
        adapter.promoteExactArtifactToProduction(
          _request(digest: _digestA, environment: 'production'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(transport.creates, hasLength(1));
    });
  });

  group('CloudflarePagesDeploymentAdapter rollback', () {
    test('targets the supplied known-good deployment', () async {
      final transport = RecordingCloudflareTransport();
      transport.deployments['deployment-known-good'] = CloudflareDeployment(
        id: 'deployment-known-good',
        environment: 'production',
        artifactDigest: _digestA,
        status: CloudflareDeploymentStatus.succeeded,
      );
      final adapter = _adapter(transport);

      final result = await adapter.rollbackToKnownGood(
        _request(
          digest: _digestA,
          environment: 'production',
          deploymentRef: 'deployment-known-good',
        ),
      );

      expect(transport.rollbacks.single.deploymentId, 'deployment-known-good');
      expect(result.artifactDigest, _digestA);
    });

    test('rejects a rollback whose digest is a new artifact', () async {
      final transport = RecordingCloudflareTransport();
      transport.deployments['deployment-known-good'] = CloudflareDeployment(
        id: 'deployment-known-good',
        environment: 'production',
        artifactDigest: _digestA,
        status: CloudflareDeploymentStatus.succeeded,
      );
      final adapter = _adapter(transport);

      await expectLater(
        adapter.rollbackToKnownGood(
          _request(
            digest: _digestB,
            environment: 'production',
            deploymentRef: 'deployment-known-good',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.rollbacks, isEmpty);
    });

    test('requires a known-good deployment reference', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.rollbackToKnownGood(
          _request(digest: _digestA, environment: 'production'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an unknown known-good deployment', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.rollbackToKnownGood(
          _request(
            digest: _digestA,
            environment: 'production',
            deploymentRef: 'missing',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CloudflarePagesDeploymentAdapter inspection', () {
    test('currentDeployment maps the provider record', () async {
      final transport = RecordingCloudflareTransport();
      transport.current = CloudflareDeployment(
        id: 'deployment-current',
        environment: 'production',
        artifactDigest: _digestA,
        status: CloudflareDeploymentStatus.succeeded,
        url: 'https://app.example.pages.dev',
      );
      final adapter = _adapter(transport);

      final result = await adapter.currentDeployment('production');

      expect(result, isNotNull);
      expect(result!.deploymentId, 'deployment-current');
      expect(result.artifactDigest, _digestA);
    });

    test('currentDeployment returns null when none is bound', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      expect(await adapter.currentDeployment('production'), isNull);
    });

    test('deploymentHealth maps status, checks, and details', () async {
      final transport = RecordingCloudflareTransport();
      transport.deployments['deployment-1'] = CloudflareDeployment(
        id: 'deployment-1',
        environment: 'production',
        artifactDigest: _digestA,
        status: CloudflareDeploymentStatus.succeeded,
        checks: const <String, bool>{'http': true},
        details: const <String, Object?>{'region': 'iad1'},
      );
      final adapter = _adapter(transport);

      final health = await adapter.deploymentHealth('deployment-1');

      expect(health.healthy, isTrue);
      expect(health.checks['http'], isTrue);
      expect(health.details['region'], 'iad1');
    });

    test('deploymentHealth rejects an unknown deployment', () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.deploymentHealth('missing'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CloudflarePagesDeploymentAdapter no-build guarantee', () {
    test('no file under lib/ exposes a build method or build command', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);

      const buildCommands = <String>[
        'Process.',
        'build_runner',
        'flutter build',
        'build web',
        'wrangler pages',
        'npm run build',
        'dart run build',
      ];
      final buildMethod = RegExp(
        r'\b(?:Future<[^>]*>|void|DeploymentResult)\s+build\s*\(',
      );

      for (final file in files) {
        final source = file.readAsStringSync();
        for (final command in buildCommands) {
          expect(
            source,
            isNot(contains(command)),
            reason: '${file.path} must not reference a build command '
                '("$command")',
          );
        }
        expect(
          buildMethod.hasMatch(source),
          isFalse,
          reason: '${file.path} must not expose a build method',
        );
      }
    });
  });

  group('Cloudflare credentials', () {
    test('toString never renders the api token', () {
      const credentials = CloudflareCredentials(
        accountId: 'acct-1',
        apiToken: 'api-token-xyz',
      );

      expect(credentials.toString(), isNot(contains('api-token-xyz')));
    });

    test('the adapter and deployment result never render the api token',
        () async {
      final transport = RecordingCloudflareTransport();
      final adapter = _adapter(transport);

      final result = await adapter.deployStaging(
        _request(digest: _digestA, environment: 'staging'),
      );

      expect(adapter.toString(), isNot(contains('api-token-xyz')));
      expect(result.toString(), isNot(contains('api-token-xyz')));
    });
  });
}
