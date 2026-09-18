import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sentry_observability_adapter.dart';

/// Default HTTP-backed [SentryTransport].
///
/// Every provider HTTP detail (store endpoint, auth header, status handling)
/// stays inside this class; the [http.Client] is injectable so tests run
/// without network access. No Sentry SDK package is required.
final class HttpSentryTransport implements SentryTransport {
  HttpSentryTransport({
    required Uri storeEndpoint,
    String? authHeader,
    http.Client? client,
  })  : _storeEndpoint = storeEndpoint,
        _authHeader = authHeader,
        _client = client ?? http.Client();

  final Uri _storeEndpoint;
  final String? _authHeader;
  final http.Client _client;

  @override
  Future<void> capture(Map<String, Object?> payload) async {
    final response = await _client.post(
      _storeEndpoint,
      headers: <String, String>{
        'content-type': 'application/json',
        if (_authHeader != null) 'x-sentry-auth': _authHeader,
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Sentry capture failed with HTTP ${response.statusCode}',
      );
    }
  }

  @override
  Future<void> flush() async {}
}
