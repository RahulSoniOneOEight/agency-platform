import 'dart:convert';

import 'package:agency_sentry_adapter/agency_sentry_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Recording transport: no network, no credentials, full payload capture.
final class RecordingSentryTransport implements SentryTransport {
  final List<Map<String, Object?>> captures = <Map<String, Object?>>[];
  bool flushed = false;

  @override
  Future<void> capture(Map<String, Object?> payload) async {
    captures.add(payload);
  }

  @override
  Future<void> flush() async {
    flushed = true;
  }
}

SentryObservabilityAdapter _adapter(RecordingSentryTransport transport) =>
    SentryObservabilityAdapter(
      transport: transport,
      clientId: 'client-1',
      environment: 'staging',
      sourceSha: 'sha-abc',
      buildVersion: '1.2.3',
      releaseCandidateId: 'candidate-1',
    );

void main() {
  group('SentryObservabilityAdapter release context', () {
    test('forwards client, environment, source, build, and candidate context '
        'on every capture', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.captureMessage('hello');

      final payload = transport.captures.single;
      expect(payload['type'], 'message');
      expect(payload['clientId'], 'client-1');
      expect(payload['environment'], 'staging');
      expect(payload['sourceSha'], 'sha-abc');
      expect(payload['buildVersion'], '1.2.3');
      expect(payload['releaseCandidateId'], 'candidate-1');
    });

    test('setReleaseContext is forwarded on subsequent captures', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.setReleaseContext(<String, String>{
        'releaseRecordId': 'record-9',
      });
      await adapter.captureMessage('hello');

      expect(transport.captures.single['releaseRecordId'], 'record-9');
    });

    test('redacts a sensitive release context value', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);
      const secret = 'secret-value';

      await adapter.setReleaseContext(<String, String>{'token': secret});
      await adapter.captureMessage('hello');

      final payload = transport.captures.single;
      expect(payload['token'], redactedValue);
      expect(jsonEncode(payload), isNot(contains(secret)));
    });

    test('release context cannot override constructor identity', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.setReleaseContext(<String, String>{
        'environment': 'production',
        'clientId': 'attacker-client',
        'sourceSha': 'attacker-sha',
        'buildVersion': '9.9.9',
        'releaseCandidateId': 'attacker-candidate',
      });
      await adapter.captureMessage('hello');

      final payload = transport.captures.single;
      expect(payload['environment'], 'staging');
      expect(payload['clientId'], 'client-1');
      expect(payload['sourceSha'], 'sha-abc');
      expect(payload['buildVersion'], '1.2.3');
      expect(payload['releaseCandidateId'], 'candidate-1');
    });

    test('propagates a correlation id supplied in capture context', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.captureException(
        StateError('boom'),
        StackTrace.current,
        context: <String, Object?>{'correlationId': 'corr-123'},
      );

      expect(transport.captures.single['correlationId'], 'corr-123');
    });

    test('propagates a request id alias supplied in capture context', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.addBreadcrumb(
        'step',
        data: <String, Object?>{'requestId': 'req-456'},
      );

      expect(transport.captures.single['correlationId'], 'req-456');
    });
  });

  group('SentryObservabilityAdapter redaction', () {
    for (final key in sensitiveKeyFragments) {
      test('redacts the sensitive key "$key"', () async {
        final transport = RecordingSentryTransport();
        final adapter = _adapter(transport);
        const secret = 'super-secret-value';

        await adapter.captureMessage(
          'hello',
          context: <String, Object?>{key: secret},
        );

        final payload = transport.captures.single;
        final context = payload['context']! as Map<String, Object?>;
        expect(context[key], redactedValue);
        expect(jsonEncode(payload), isNot(contains(secret)));
      });
    }

    test('redacts case-insensitively', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.captureMessage(
        'hello',
        context: <String, Object?>{'Authorization': 'Bearer abc'},
      );

      final context =
          transport.captures.single['context']! as Map<String, Object?>;
      expect(context['Authorization'], redactedValue);
    });

    test('redacts sensitive keys in nested maps and lists', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);
      const secret = 'nested-secret-value';

      await adapter.captureException(
        StateError('boom'),
        StackTrace.current,
        context: <String, Object?>{
          'outer': <String, Object?>{
            'inner': <String, Object?>{
              'service_role_key': secret,
            },
          },
          'items': <Object?>[
            <String, Object?>{'token': secret},
          ],
        },
      );

      final payload = transport.captures.single;
      expect(jsonEncode(payload), isNot(contains(secret)));
      final context = payload['context']! as Map<String, Object?>;
      final outer = context['outer']! as Map<String, Object?>;
      final inner = outer['inner']! as Map<String, Object?>;
      expect(inner['service_role_key'], redactedValue);
      final items = context['items']! as List<Object?>;
      final item = items.single as Map<String, Object?>;
      expect(item['token'], redactedValue);
    });

    test('leaves non-sensitive values untouched', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      await adapter.captureMessage(
        'hello',
        context: <String, Object?>{'orderId': 'order-1', 'count': 3},
      );

      final context =
          transport.captures.single['context']! as Map<String, Object?>;
      expect(context['orderId'], 'order-1');
      expect(context['count'], 3);
    });
  });

  group('SentryObservabilityAdapter startOperation', () {
    test('returns the value on success without capturing', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);

      final result = await adapter.startOperation<int>(
        'work',
        () async => 7,
      );

      expect(result, 7);
      expect(transport.captures, isEmpty);
    });

    test('captures the failure and rethrows the original error', () async {
      final transport = RecordingSentryTransport();
      final adapter = _adapter(transport);
      final error = StateError('operation failed');

      await expectLater(
        adapter.startOperation<void>('work', () async => throw error),
        throwsA(same(error)),
      );

      final payload = transport.captures.single;
      expect(payload['type'], 'exception');
      expect(payload['message'], error.toString());
      final context = payload['context']! as Map<String, Object?>;
      expect(context['operation'], 'work');
    });
  });

  test('flush delegates to the transport', () async {
    final transport = RecordingSentryTransport();
    final adapter = _adapter(transport);

    await adapter.flush();

    expect(transport.flushed, isTrue);
  });

  group('HttpSentryTransport', () {
    test('posts the JSON payload to the store endpoint', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      });
      final transport = HttpSentryTransport(
        storeEndpoint: Uri.parse('https://sentry.example.com/api/1/store/'),
        authHeader: 'Sentry sentry_key=public',
        client: client,
      );

      await transport.capture(<String, Object?>{'type': 'message'});

      expect(captured.method, 'POST');
      expect(
        captured.headers['content-type'],
        'application/json',
      );
      expect(
        jsonDecode(captured.body),
        <String, Object?>{'type': 'message'},
      );
    });

    test('throws a provider-neutral error on a non-success status', () async {
      final client = MockClient((request) async => http.Response('nope', 500));
      final transport = HttpSentryTransport(
        storeEndpoint: Uri.parse('https://sentry.example.com/api/1/store/'),
        client: client,
      );

      await expectLater(
        transport.capture(<String, Object?>{'type': 'message'}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
