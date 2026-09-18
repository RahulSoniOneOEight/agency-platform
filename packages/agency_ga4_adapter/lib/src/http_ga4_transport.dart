import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ga4_analytics_adapter.dart';

/// Default HTTP-backed [Ga4Transport] using the GA4 Measurement Protocol.
///
/// Every provider HTTP detail (collect endpoint, measurement id, api secret,
/// status handling) stays inside this class; the [http.Client] is injectable so
/// tests run without network access. The api secret travels only in the request
/// query string, never in an event payload.
final class HttpGa4Transport implements Ga4Transport {
  HttpGa4Transport({
    required Ga4Credentials credentials,
    required String measurementId,
    Uri? endpoint,
    http.Client? client,
  })  : _credentials = credentials,
        _measurementId = measurementId,
        _endpoint = endpoint ??
            Uri.parse('https://www.google-analytics.com/mp/collect'),
        _client = client ?? http.Client();

  final Ga4Credentials _credentials;
  final String _measurementId;
  final Uri _endpoint;
  final http.Client _client;

  @override
  Future<void> sendEvent(
    String eventName,
    Map<String, Object?> parameters,
  ) =>
      _post(<String, Object?>{
        'client_id': _credentials.clientId ?? 'anonymous',
        'events': <Object?>[
          <String, Object?>{'name': eventName, 'params': parameters},
        ],
      });

  @override
  Future<void> sendUserProperties(Map<String, Object?> properties) =>
      _post(<String, Object?>{
        'client_id': _credentials.clientId ?? 'anonymous',
        'user_properties': properties,
      });

  @override
  Future<void> flush() async {}

  Future<void> _post(Map<String, Object?> body) async {
    final uri = _endpoint.replace(
      queryParameters: <String, String>{
        'measurement_id': _measurementId,
        'api_secret': _credentials.apiSecret,
      },
    );
    final response = await _client.post(
      uri,
      headers: <String, String>{'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('GA4 request failed with HTTP ${response.statusCode}');
    }
  }
}
