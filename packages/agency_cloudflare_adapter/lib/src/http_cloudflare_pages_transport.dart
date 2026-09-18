import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloudflare_pages_deployment_adapter.dart';

/// Default HTTP-backed [CloudflarePagesTransport] for the Cloudflare Pages API.
///
/// Every provider HTTP detail (API base, auth header, endpoint paths, status
/// handling) stays inside this class; the [http.Client] is injectable so tests
/// run without network access. The adapter calls only deployment endpoints and
/// never invokes a source build.
final class HttpCloudflarePagesTransport implements CloudflarePagesTransport {
  HttpCloudflarePagesTransport({
    required Uri apiBaseUri,
    required String project,
    required CloudflareCredentials credentials,
    http.Client? client,
  })  : _apiBaseUri = apiBaseUri,
        _project = project,
        _credentials = credentials,
        _client = client ?? http.Client();

  final Uri _apiBaseUri;
  final String _project;
  final CloudflareCredentials _credentials;
  final http.Client _client;

  @override
  Future<CloudflareDeployment> createDeployment({
    required String project,
    required String branch,
    required String artifactPath,
    required String artifactDigest,
    required String environment,
    required CloudflareCredentials credentials,
  }) async {
    final response = await _client.post(
      _uri(
        '/accounts/${credentials.accountId}/pages/projects/$project/deployments',
      ),
      headers: _headers(credentials),
      body: jsonEncode(<String, Object?>{
        'branch': branch,
        'artifact_path': artifactPath,
        'artifact_digest': artifactDigest,
        'environment': environment,
      }),
    );
    return _decode(response);
  }

  @override
  Future<CloudflareDeployment?> getDeployment(String deploymentId) async {
    final response = await _client.get(
      _uri(
        '/accounts/${_credentials.accountId}/pages/projects/$_project/'
        'deployments/$deploymentId',
      ),
      headers: _headers(_credentials),
    );
    if (response.statusCode == 404) {
      return null;
    }
    return _decode(response);
  }

  @override
  Future<CloudflareDeployment?> currentDeployment(String environment) async {
    final response = await _client.get(
      _uri(
        '/accounts/${_credentials.accountId}/pages/projects/$_project/'
        'deployments?environment=${Uri.encodeQueryComponent(environment)}',
      ),
      headers: _headers(_credentials),
    );
    if (response.statusCode == 404) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    final results = decoded is List
        ? decoded
        : (decoded as Map<String, dynamic>)['result'] as List<dynamic>? ??
            const <dynamic>[];
    if (results.isEmpty) {
      return null;
    }
    return _deploymentFromJson(results.first as Map<String, dynamic>);
  }

  @override
  Future<CloudflareDeployment> rollback({
    required String project,
    required String deploymentId,
    required CloudflareCredentials credentials,
  }) async {
    final response = await _client.post(
      _uri(
        '/accounts/${credentials.accountId}/pages/projects/$project/'
        'deployments/$deploymentId/rollback',
      ),
      headers: _headers(credentials),
    );
    return _decode(response);
  }

  Map<String, String> _headers(CloudflareCredentials credentials) =>
      <String, String>{
        'authorization': 'Bearer ${credentials.apiToken}',
        'content-type': 'application/json',
      };

  Uri _uri(String path) {
    final base = _apiBaseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  CloudflareDeployment _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Cloudflare Pages request failed with HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    final json = decoded is Map<String, dynamic> &&
            decoded['result'] is Map<String, dynamic>
        ? decoded['result'] as Map<String, dynamic>
        : decoded as Map<String, dynamic>;
    return _deploymentFromJson(json);
  }

  CloudflareDeployment _deploymentFromJson(Map<String, dynamic> json) {
    final checks = <String, bool>{};
    final rawChecks = json['checks'];
    if (rawChecks is Map) {
      rawChecks.forEach((key, value) {
        checks[key.toString()] = value == true;
      });
    }
    final details = <String, Object?>{};
    final rawDetails = json['details'];
    if (rawDetails is Map) {
      rawDetails.forEach((key, value) {
        details[key.toString()] = value;
      });
    }
    return CloudflareDeployment(
      id: json['id'] as String,
      environment: json['environment'] as String? ?? 'production',
      artifactDigest: json['artifact_digest'] as String? ?? '',
      status: _statusFromJson(json['status']),
      url: json['url'] as String?,
      checks: checks,
      details: details,
    );
  }

  static CloudflareDeploymentStatus _statusFromJson(Object? status) =>
      switch (status) {
        'succeeded' || 'success' || 'active' =>
          CloudflareDeploymentStatus.succeeded,
        'failed' || 'failure' => CloudflareDeploymentStatus.failed,
        'in_progress' || 'running' => CloudflareDeploymentStatus.inProgress,
        _ => CloudflareDeploymentStatus.queued,
      };
}
