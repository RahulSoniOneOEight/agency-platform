import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeObservabilityPort implements ObservabilityPort {
  final List<Map<String, Object?>> exceptions = [];
  final List<String> messages = [];
  final List<String> breadcrumbs = [];
  final List<String> operations = [];
  String? userId;
  Map<String, String> releaseContext = {};
  int flushCount = 0;

  @override
  Future<void> captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> context = const {},
  }) async {
    exceptions.add({'error': error, 'context': context});
  }

  @override
  Future<void> captureMessage(
    String message, {
    Map<String, Object?> context = const {},
  }) async {
    messages.add(message);
  }

  @override
  Future<void> addBreadcrumb(
    String message, {
    Map<String, Object?> data = const {},
  }) async {
    breadcrumbs.add(message);
  }

  @override
  Future<void> setUserContext(String? userId) async {
    this.userId = userId;
  }

  @override
  Future<void> setReleaseContext(Map<String, String> context) async {
    releaseContext = Map.of(context);
  }

  @override
  Future<T> startOperation<T>(String name, Future<T> Function() operation) async {
    operations.add(name);
    await addBreadcrumb('start:$name');
    return operation();
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }
}

void main() {
  test('a fake observability port is provider neutral and compiles', () {
    final port = FakeObservabilityPort();
    expect(port, isA<ObservabilityPort>());
  });

  test('setReleaseContext carries environment, source sha, build version, '
      'and release candidate id', () async {
    final port = FakeObservabilityPort();

    await port.setReleaseContext({
      'client_id': 'reference-commerce',
      'environment': 'staging',
      'source_sha': 'abc123def',
      'build_version': '1.0.0+1',
      'release_candidate_id': 'candidate-1',
    });

    expect(port.releaseContext['environment'], 'staging');
    expect(port.releaseContext['source_sha'], 'abc123def');
    expect(port.releaseContext['build_version'], '1.0.0+1');
    expect(port.releaseContext['release_candidate_id'], 'candidate-1');
  });

  test('startOperation returns the operation result and records the operation',
      () async {
    final port = FakeObservabilityPort();

    final result = await port.startOperation('load-catalog', () async => 42);

    expect(result, 42);
    expect(port.operations, ['load-catalog']);
    expect(port.breadcrumbs, ['start:load-catalog']);
  });

  test('startOperation propagates operation errors', () async {
    final port = FakeObservabilityPort();

    expect(
      () => port.startOperation<void>(
        'boom',
        () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(port.operations, ['boom']);
  });

  test('capture, message, breadcrumb, user, and flush are recorded', () async {
    final port = FakeObservabilityPort();

    await port.captureException(
      ArgumentError('x'),
      StackTrace.empty,
      context: const {'k': 'v'},
    );
    await port.captureMessage('hello');
    await port.addBreadcrumb('nav', data: const {'to': '/cart'});
    await port.setUserContext('user-1');
    await port.flush();

    expect(port.exceptions.single['error'], isA<ArgumentError>());
    expect(port.messages, ['hello']);
    expect(port.breadcrumbs, ['nav']);
    expect(port.userId, 'user-1');
    expect(port.flushCount, 1);
  });
}
