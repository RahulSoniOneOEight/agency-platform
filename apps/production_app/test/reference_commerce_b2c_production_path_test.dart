import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_app/app/environment_config_loader.dart';
import 'package:production_app/app/production_composition_root.dart';

import 'support/reference_commerce_harness.dart';

/// B2C production-path E2E for reference-commerce.
///
/// The journey drives the same application services as production composition
/// (`CommerceService`, `OrderService`, `QuoteService`); the harness only
/// substitutes deterministic in-memory boundaries for setup and failure
/// injection. It never reimplements a service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scenarios = loadIntegrationScenarios();

  group('reference-commerce B2C production path', () {
    late ReferenceCommerceHarness harness;

    setUp(() {
      harness = ReferenceCommerceHarness();
    });

    test(
      'sign in -> catalog/inventory -> persist cart -> idempotent order',
      () async {
        // The executed journey is recorded by fixture step id so the fixture's
        // ordered step list is the single source of truth (no restatement).
        final executedSteps = <String>[];

        // 1. Sign in as a consumer.
        final identity = await harness.runtime.auth.signIn(
          email: 'consumer@reference-commerce.example',
          password: 'reference-password',
        );
        expect(identity.role, UserRole.consumer);
        expect(await harness.runtime.auth.currentIdentity(), isNotNull);
        executedSteps.add('sign_in');

        // 2. Load catalog + inventory through CommerceService.
        final catalog = await harness.runtime.commerce.loadCatalog();
        expect(catalog, isNotEmpty);
        final product = catalog.first;
        expect(product.variants, isNotEmpty);
        final variant = product.variants.first;
        expect(variant.available, isNotNull);
        expect(variant.available, greaterThan(0));
        executedSteps.add('load_catalog_inventory');

        // 3. Create and persist a cart (setup boundary; the journey mutation
        //    still goes through OrderService below).
        final cart = Cart(
          id: 'cart-b2c-1',
          items: [
            CartItem(
              productId: product.product.id,
              variantId: variant.variant.id,
              quantity: 2,
              unitPriceMinor: variant.variant.priceMinor,
            ),
          ],
        );
        await harness.cartRepository.saveCart(cart);
        final persisted = await harness.cartRepository.getCart(cart.id);
        expect(persisted, isNotNull);
        expect(persisted!.itemCount, 2);
        executedSteps.add('create_persist_cart');

        // 4. Place the order through OrderService with an idempotency key.
        final key = IdempotencyKey('b2c-order-key-1');
        final first = await harness.runtime.orders.placeOrder(
          cartId: cart.id,
          idempotencyKey: key,
        );
        expect(first.items, hasLength(1));
        expect(first.totalMinor, cart.subtotalMinor);
        executedSteps.add('place_order');

        // 5. Repeat the submission with the same key.
        final second = await harness.runtime.orders.placeOrder(
          cartId: cart.id,
          idempotencyKey: key,
        );
        executedSteps.add('repeat_submission');

        // 6. Exactly one order identity.
        expect(second.id, first.id);
        expect(harness.orderRepository.distinctOrderCount, 1);
        executedSteps.add('assert_single_order_identity');

        expect(executedSteps, scenarios.b2cPath.steps);
      },
    );

    test('catalog carries inventory availability for every variant', () async {
      final catalog = await harness.runtime.commerce.loadCatalog();

      final variants = [
        for (final product in catalog) ...product.variants,
      ];
      expect(variants, isNotEmpty);
      expect(
        variants.every((variant) => variant.available != null),
        isTrue,
        reason: 'CommerceService composes inventory availability per variant',
      );
    });

    test('production composition root drives the same B2C boundary', () async {
      final config = await EnvironmentConfigLoader.load('dev');
      final runtime = ProductionCompositionRoot.referenceCommerce(config);

      final identity = await runtime.auth.signIn(
        email: 'consumer@reference-commerce.example',
        password: 'reference-password',
      );
      expect(identity.role, UserRole.consumer);

      final catalog = await runtime.commerce.loadCatalog();
      expect(catalog, isNotEmpty);

      final key = IdempotencyKey('b2c-composed-key-1');
      final first = await runtime.orders.placeOrder(
        cartId: 'cart-consumer',
        idempotencyKey: key,
      );
      final second = await runtime.orders.placeOrder(
        cartId: 'cart-consumer',
        idempotencyKey: key,
      );

      expect(second.id, first.id);
    });
  });
}
