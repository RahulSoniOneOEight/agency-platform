import 'package:agency_operations_core/agency_operations_core.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAnalyticsPort implements AnalyticsPort {
  final List<AnalyticsEvent> events = [];
  final List<Map<String, Object?>> userProperties = [];
  final List<bool> consentChanges = [];
  Map<String, String> releaseContext = {};
  int flushCount = 0;
  bool _analyticsStorageConsent = false;

  @override
  Future<void> trackEvent(AnalyticsEvent event) async {
    if (!_analyticsStorageConsent) {
      return;
    }
    events.add(event);
  }

  @override
  Future<void> setUserProperties(Map<String, Object?> properties) async {
    userProperties.add(Map.of(properties));
  }

  @override
  Future<void> setConsent({required bool analyticsStorage}) async {
    _analyticsStorageConsent = analyticsStorage;
    consentChanges.add(analyticsStorage);
  }

  @override
  Future<void> setReleaseContext(Map<String, String> context) async {
    releaseContext = Map.of(context);
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }
}

void main() {
  test('operations ports are provider neutral', () {
    final event = AnalyticsEvent(
      name: 'order_created',
      parameters: const {'environment': 'staging'},
    );
    expect(event.name, 'order_created');
    expect(event.parameters['environment'], 'staging');
  });

  test('AnalyticsEvent has value equality and stable hash codes', () {
    final first = AnalyticsEvent(
      name: 'order_created',
      parameters: const {'order_id': 'o-1', 'total': 100},
      environment: 'staging',
    );
    final second = AnalyticsEvent(
      name: 'order_created',
      parameters: const {'total': 100, 'order_id': 'o-1'},
      environment: 'staging',
    );
    final different = AnalyticsEvent(
      name: 'order_created',
      parameters: const {'order_id': 'o-2'},
      environment: 'staging',
    );

    expect(first, equals(second));
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(equals(different)));
  });

  test('AnalyticsEvent rejects an empty name', () {
    expect(
      () => AnalyticsEvent(name: '   '),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('setConsent(analyticsStorage: false) suppresses emission', () async {
    final port = FakeAnalyticsPort();
    final event = AnalyticsEvent(name: 'sign_in');

    await port.setConsent(analyticsStorage: false);
    await port.trackEvent(event);
    expect(port.events, isEmpty);

    await port.setConsent(analyticsStorage: true);
    await port.trackEvent(event);
    expect(port.events, [event]);
  });

  test('a fake analytics port records events, properties, context, and flush',
      () async {
    final port = FakeAnalyticsPort();

    await port.setConsent(analyticsStorage: true);
    await port.setReleaseContext(const {'environment': 'production'});
    await port.setUserProperties(const {'segment': 'b2c'});
    await port.trackEvent(AnalyticsEvent(name: 'purchase'));
    await port.flush();

    expect(port.events.single.name, 'purchase');
    expect(port.userProperties.single['segment'], 'b2c');
    expect(port.releaseContext['environment'], 'production');
    expect(port.flushCount, 1);
  });
}
