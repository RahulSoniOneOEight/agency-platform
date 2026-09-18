import 'dart:convert';

import 'package:agency_ga4_adapter/agency_ga4_adapter.dart';
import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Recording transport: no network, no credentials, full payload capture.
final class RecordingGa4Transport implements Ga4Transport {
  final List<({String name, Map<String, Object?> parameters})> events =
      <({String name, Map<String, Object?> parameters})>[];
  final List<Map<String, Object?>> userProperties = <Map<String, Object?>>[];
  bool flushed = false;

  @override
  Future<void> sendEvent(
    String eventName,
    Map<String, Object?> parameters,
  ) async {
    events.add((name: eventName, parameters: parameters));
  }

  @override
  Future<void> sendUserProperties(Map<String, Object?> properties) async {
    userProperties.add(properties);
  }

  @override
  Future<void> flush() async {
    flushed = true;
  }
}

Ga4AnalyticsAdapter _adapter(
  RecordingGa4Transport transport, {
  String apiSecret = 'server-secret',
}) =>
    Ga4AnalyticsAdapter(
      transport: transport,
      environment: 'staging',
      measurementId: 'G-TEST',
      apiSecret: apiSecret,
    );

void main() {
  group('Ga4AnalyticsAdapter emission', () {
    test('forwards the governed event name and parameters', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await adapter.trackEvent(
        AnalyticsEvent(
          name: 'product_view',
          parameters: <String, Object?>{'product_id': 'p-1'},
        ),
      );

      final event = transport.events.single;
      expect(event.name, 'product_view');
      expect(event.parameters['product_id'], 'p-1');
    });

    test('attaches the environment to every event', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await adapter.trackEvent(AnalyticsEvent(name: 'sign_in'));

      expect(transport.events.single.parameters['environment'], 'staging');
    });

    test('attaches release context to every event', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await adapter.setReleaseContext(<String, String>{
        'releaseCandidateId': 'candidate-1',
      });
      await adapter.trackEvent(AnalyticsEvent(name: 'sign_in'));

      expect(
        transport.events.single.parameters['releaseCandidateId'],
        'candidate-1',
      );
    });

    test('setUserProperties forwards properties with the environment', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await adapter.setUserProperties(<String, Object?>{'plan': 'pro'});

      expect(transport.userProperties.single['plan'], 'pro');
      expect(transport.userProperties.single['environment'], 'staging');
    });

    test('flush delegates to the transport', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await adapter.flush();

      expect(transport.flushed, isTrue);
    });
  });

  group('Ga4AnalyticsAdapter consent', () {
    test('consent=false suppresses all emission until re-enabled', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await adapter.setConsent(analyticsStorage: false);
      await adapter.trackEvent(AnalyticsEvent(name: 'sign_in'));
      await adapter.setUserProperties(<String, Object?>{'plan': 'pro'});
      expect(transport.events, isEmpty);
      expect(transport.userProperties, isEmpty);

      await adapter.setConsent(analyticsStorage: true);
      await adapter.trackEvent(AnalyticsEvent(name: 'sign_in'));
      expect(transport.events, hasLength(1));
    });
  });

  group('Ga4AnalyticsAdapter parameter governance', () {
    for (final key in sensitiveGa4ParameterFragments) {
      test('rejects the secret-like parameter "$key" before emission',
          () async {
        final transport = RecordingGa4Transport();
        final adapter = _adapter(transport);

        await expectLater(
          adapter.trackEvent(
            AnalyticsEvent(
              name: 'product_view',
              parameters: <String, Object?>{key: 'value'},
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(transport.events, isEmpty);
      });
    }

    test('rejects secret-like names nested in maps and lists', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.trackEvent(
          AnalyticsEvent(
            name: 'product_view',
            parameters: <String, Object?>{
              'items': <Object?>[
                <String, Object?>{'access_token': 'abc'},
              ],
            },
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.events, isEmpty);
    });

    test('rejects sensitive keys supplied via setReleaseContext', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.setReleaseContext(<String, String>{'access_token': 'abc'}),
        throwsA(isA<ArgumentError>()),
      );

      // The rejected context must not have been retained on the adapter.
      await adapter.trackEvent(AnalyticsEvent(name: 'sign_in'));
      expect(
        jsonEncode(transport.events.single.parameters),
        isNot(contains('access_token')),
      );
    });

    test('rejects sensitive names nested in lists inside lists', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport);

      await expectLater(
        adapter.trackEvent(
          AnalyticsEvent(
            name: 'product_view',
            parameters: <String, Object?>{
              'groups': <Object?>[
                <Object?>[
                  <String, Object?>{'secret_key': 'abc'},
                ],
              ],
            },
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.events, isEmpty);
    });
  });

  group('Ga4AnalyticsAdapter credential handling', () {
    const secret = 'ga4-api-secret-xyz';

    test('the secret never appears in emitted payloads or safe renderings',
        () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport, apiSecret: secret);

      await adapter.setUserProperties(<String, Object?>{'plan': 'pro'});
      await adapter.trackEvent(
        AnalyticsEvent(
          name: 'product_view',
          parameters: <String, Object?>{'product_id': 'p-1'},
        ),
      );

      expect(
        jsonEncode(transport.events.single.parameters),
        isNot(contains(secret)),
      );
      expect(
        jsonEncode(transport.userProperties.single),
        isNot(contains(secret)),
      );
      expect(adapter.toJson().toString(), isNot(contains(secret)));
      expect(adapter.toString(), isNot(contains(secret)));
      expect(adapter.toJson().keys, contains('environment'));
      expect(adapter.toJson().keys, contains('measurementId'));
    });

    test('the secret never appears in a governance exception', () async {
      final transport = RecordingGa4Transport();
      final adapter = _adapter(transport, apiSecret: secret);

      try {
        await adapter.trackEvent(
          AnalyticsEvent(
            name: 'product_view',
            parameters: <String, Object?>{'password': 'x'},
          ),
        );
        fail('Expected an ArgumentError');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains(secret)));
      }
    });

    test('an empty api secret is rejected without echoing it', () {
      final transport = RecordingGa4Transport();
      expect(
        () => Ga4AnalyticsAdapter(
          transport: transport,
          environment: 'staging',
          apiSecret: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Ga4Credentials.toString never renders the secret', () {
      const credentials = Ga4Credentials(apiSecret: secret, clientId: 'c-1');
      expect(credentials.toString(), isNot(contains(secret)));
    });
  });

  group('HttpGa4Transport', () {
    test('posts the event body and keeps the secret in the query only',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final transport = HttpGa4Transport(
        credentials: const Ga4Credentials(
          apiSecret: 'server-secret',
          clientId: 'client-1',
        ),
        measurementId: 'G-TEST',
        client: client,
      );

      await transport.sendEvent(
        'product_view',
        <String, Object?>{'environment': 'staging'},
      );

      final body = jsonDecode(captured.body) as Map<String, Object?>;
      expect(captured.url.queryParameters['measurement_id'], 'G-TEST');
      expect(captured.url.queryParameters['api_secret'], 'server-secret');
      expect(captured.body, isNot(contains('server-secret')));
      expect(body['client_id'], 'client-1');
    });

    test('throws a provider-neutral error on a non-success status', () async {
      final client = MockClient((request) async => http.Response('nope', 500));
      final transport = HttpGa4Transport(
        credentials: const Ga4Credentials(apiSecret: 'server-secret'),
        measurementId: 'G-TEST',
        client: client,
      );

      await expectLater(
        transport.sendEvent('sign_in', const <String, Object?>{}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
