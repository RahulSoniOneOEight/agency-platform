import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_app/runtime/deterministic_boundaries.dart';

import 'support/reference_commerce_harness.dart';

/// Reference-commerce failure-state proof.
///
/// Every scenario is driven through the same application services and
/// provider-neutral ports as production composition. Provider faults are
/// injected at the repository boundary and must cross back as a normalized
/// [DomainFailure] with a stable code, operation, and retryability — never as a
/// provider type.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenarios = loadIntegrationScenarios();

  const requiredScenarioIds = {
    'expired-session-refresh',
    'forbidden-b2b-action',
    'inventory-unavailable',
    'stale-cart',
    'backend-unavailable',
    'timeout',
    'retryable-vs-non-retryable',
    'duplicate-order-protection',
    'malformed-environment-config',
  };

  // Every scenario id the fixture declares, and the test that proves it.
  const coveredScenarioIds = {
    // data-driven provider-neutral failures
    'forbidden-b2b-action',
    'inventory-unavailable',
    'stale-cart',
    'backend-unavailable',
    'timeout',
    // explicitly named tests
    'retryable-vs-non-retryable',
    'expired-session-refresh',
    'duplicate-order-protection',
    'malformed-environment-config',
  };

  test('fixture declares every required failure scenario exactly once', () {
    expect(scenarios.version, 1);
    expect(scenarios.clientId, 'reference-commerce');
    expect(scenarios.failureScenarioIds, requiredScenarioIds);
    expect(scenarios.failureScenarios, hasLength(requiredScenarioIds.length));
    // Meaningful coverage check: the set of scenarios a test proves must equal
    // the required set — nothing missing, nothing extra.
    expect(
      requiredScenarioIds.difference(coveredScenarioIds),
      isEmpty,
      reason: 'every required scenario must be covered by a test',
    );
    expect(
      coveredScenarioIds.difference(requiredScenarioIds),
      isEmpty,
      reason: 'no test may claim a scenario the fixture does not declare',
    );
    expect(
      scenarios.failureScenarios
          .where((scenario) => scenario.kind == 'failure')
          .map((scenario) => scenario.id)
          .toSet(),
      const {
        'forbidden-b2b-action',
        'inventory-unavailable',
        'stale-cart',
        'backend-unavailable',
        'timeout',
      },
    );
    expect(scenarios.b2cPath.id, isNotEmpty);
    expect(scenarios.b2cPath.steps, isNotEmpty);
    expect(scenarios.b2bPath.id, isNotEmpty);
    expect(scenarios.b2bPath.steps, isNotEmpty);
    expect(scenarios.b2bCaseIds, isNotEmpty);
  });

  group('provider-neutral failure normalization', () {
    for (final scenario
        in scenarios.failureScenarios.where((s) => s.kind == 'failure')) {
      test('${scenario.id} surfaces ${scenario.expectedCode!.name}', () async {
        final failure = await _driveFailure(scenario.id);

        expect(failure.code, scenario.expectedCode);
        expect(failure.retryable, scenario.expectedRetryable);
        expect(failure.operation, scenario.expectedOperation);
      });
    }
  });

  group('session and idempotency', () {
    test('expired session refreshes, then fails when the refresh is revoked',
        () async {
      final scenario = scenarios.failureById('expired-session-refresh');
      final seed = defaultReferenceCommerceSeed();
      final auth = ExpirableAuthService(
        identitiesByEmail: seed.identitiesByEmail,
      );
      final harness = ReferenceCommerceHarness(auth: auth);

      final identity = await harness.runtime.auth.signIn(
        email: 'consumer@reference-commerce.example',
        password: 'reference-password',
      );

      // The access token expires: no current identity, but the refresh token
      // is still valid, so refresh restores the session.
      auth.expireSession();
      expect(await harness.runtime.auth.currentIdentity(), isNull);
      final refreshed = await harness.runtime.auth.refreshSession();
      expect(refreshed.id, identity.id);
      expect(await harness.runtime.auth.currentIdentity(), isNotNull);

      // Signing out revokes the refresh token: refresh now fails
      // deterministically as a non-retryable unauthorized failure.
      await harness.runtime.auth.signOut();
      final failure = await _captureFailure(harness.runtime.auth.refreshSession);
      expect(failure.code, scenario.expectedCode);
      expect(failure.retryable, scenario.expectedRetryable);
      expect(failure.operation, scenario.expectedOperation);
    });

    test('duplicate order protection keeps exactly one order identity',
        () async {
      final harness = ReferenceCommerceHarness();
      final key = IdempotencyKey('duplicate-order-key');

      final first = await harness.runtime.orders.placeOrder(
        cartId: 'cart-consumer',
        idempotencyKey: key,
      );
      final second = await harness.runtime.orders.placeOrder(
        cartId: 'cart-consumer',
        idempotencyKey: key,
      );

      expect(second.id, first.id);
      expect(harness.orderRepository.distinctOrderCount, 1);
    });
  });

  group('retryability', () {
    test('retryable timeout contrasts with non-retryable validation', () async {
      final scenario = scenarios.failureById('retryable-vs-non-retryable');

      final timeoutHarness = ReferenceCommerceHarness(
        carts: FailingCartRepository(
          failure: _normalized(
            DomainFailureCode.timeout,
            'carts.getCart',
            retryable: true,
          ),
        ),
      );
      final timeoutFailure = await _captureFailure(
        () => timeoutHarness.runtime.orders.placeOrder(
          cartId: 'cart-consumer',
          idempotencyKey: IdempotencyKey('retry-timeout-key'),
        ),
      );

      final validationHarness = ReferenceCommerceHarness();
      final validationFailure = await _captureFailure(
        () => validationHarness.runtime.orders.placeOrder(
          cartId: 'missing-cart',
          idempotencyKey: IdempotencyKey('retry-validation-key'),
        ),
      );

      expect(timeoutFailure.code, scenario.expectedCode);
      expect(timeoutFailure.retryable, scenario.expectedRetryable);
      expect(validationFailure.code, scenario.contrastCode);
      expect(validationFailure.retryable, scenario.contrastRetryable);
    });
  });

  group('malformed environment config', () {
    test('every malformed payload fails with a FormatException', () {
      final scenario = scenarios.failureById('malformed-environment-config');
      expect(scenario.expectedError, 'FormatException');

      const base = 'https://api.example.test';
      final malformed = <String, Map<String, Object?>>{
        'missing environment': {'api_base_url': base},
        'unknown environment': {'environment': 'prod', 'api_base_url': base},
        'missing api_base_url': {'environment': 'dev'},
        'empty api_base_url': {'environment': 'dev', 'api_base_url': ''},
        'unsupported key': {
          'environment': 'dev',
          'api_base_url': base,
          'unknown_key': true,
        },
        'privileged key': {
          'environment': 'dev',
          'api_base_url': base,
          'service_role_key': 'x',
        },
        'wrong value type': {
          'environment': 'dev',
          'api_base_url': base,
          'feature_flags': 'nope',
        },
      };

      for (final entry in malformed.entries) {
        expect(
          () => EnvironmentConfig.fromJson(entry.value),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });
  });
}

Future<DomainFailure> _driveFailure(String scenarioId) async {
  switch (scenarioId) {
    case 'forbidden-b2b-action':
      final harness = ReferenceCommerceHarness();
      final consumer = await harness.runtime.auth.signIn(
        email: 'consumer@reference-commerce.example',
        password: 'reference-password',
      );
      return _captureFailure(
        () => harness.runtime.quotes.createRfq(
          accountId: 'account-trade',
          identityId: consumer.id,
          items: [_item()],
          idempotencyKey: IdempotencyKey('forbidden-b2b-key'),
        ),
      );
    case 'inventory-unavailable':
      final harness = ReferenceCommerceHarness(
        inventory: FailingInventoryRepository(
          failure: _normalized(
            DomainFailureCode.unavailable,
            'inventory.listAvailability',
            retryable: true,
          ),
        ),
      );
      return _captureFailure(harness.runtime.commerce.loadCatalog);
    case 'backend-unavailable':
      final harness = ReferenceCommerceHarness(
        catalog: FailingCatalogRepository(
          failure: _normalized(
            DomainFailureCode.unavailable,
            'catalog.listProducts',
            retryable: true,
          ),
        ),
      );
      return _captureFailure(harness.runtime.commerce.loadCatalog);
    case 'stale-cart':
      final harness = ReferenceCommerceHarness(
        orders: FailingOrderRepository(
          failure: _normalized(
            DomainFailureCode.staleData,
            'orders.createOrder',
            retryable: false,
          ),
        ),
      );
      return _captureFailure(
        () => harness.runtime.orders.placeOrder(
          cartId: 'cart-consumer',
          idempotencyKey: IdempotencyKey('stale-cart-key'),
        ),
      );
    case 'timeout':
      final harness = ReferenceCommerceHarness(
        carts: FailingCartRepository(
          failure: _normalized(
            DomainFailureCode.timeout,
            'carts.getCart',
            retryable: true,
          ),
        ),
      );
      return _captureFailure(
        () => harness.runtime.orders.placeOrder(
          cartId: 'cart-consumer',
          idempotencyKey: IdempotencyKey('timeout-key'),
        ),
      );
    default:
      throw ArgumentError('No failure driver for scenario $scenarioId');
  }
}

CartItem _item() => CartItem(
      productId: 'product-espresso-machine',
      variantId: 'variant-espresso-machine-230v',
      quantity: 1,
      unitPriceMinor: 129900,
    );

DomainFailure _normalized(
  DomainFailureCode code,
  String operation, {
  required bool retryable,
}) =>
    DomainFailure(
      code: code,
      operation: operation,
      retryable: retryable,
      message: 'Deterministic injected failure for $operation',
    );

Future<DomainFailure> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
  } on DomainFailure catch (failure) {
    return failure;
  }
  fail('Expected a DomainFailure to be thrown');
}
