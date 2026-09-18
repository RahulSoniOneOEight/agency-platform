import 'package:agency_production_core/agency_production_core.dart';
import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase_clients.dart';

void main() {
  late FakeSupabaseQueryClient query;

  setUp(() {
    query = FakeSupabaseQueryClient();
  });

  group('SupabaseCatalogRepository', () {
    late SupabaseCatalogRepository repository;

    setUp(() {
      query.tables['products'] = [
        {
          'id': 'prd-1',
          'name': 'Hub',
          'sku': 'SKU-1',
          'retail_price_minor': 1000,
          'category_id': 'cat-1',
          'description': 'A hub',
        },
        {
          'id': 'prd-2',
          'name': 'Dock',
          'sku': 'SKU-2',
          'retail_price_minor': 2000,
          'category_id': 'cat-2',
          'description': null,
        },
      ];
      query.tables['variants'] = [
        {
          'id': 'var-1',
          'product_id': 'prd-1',
          'name': 'Default',
          'sku': 'SKU-1-A',
          'price_minor': 1000,
          'attributes': {'color': 'black'},
        },
      ];
      query.tables['inventory'] = [
        {'variant_id': 'var-1', 'available': 7, 'warehouse_id': 'wh-1'},
      ];
      repository = SupabaseCatalogRepository(query: query);
    });

    test('lists products and maps retail_price_minor to priceMinor', () async {
      final products = await repository.listProducts();

      expect(products, hasLength(2));
      expect(products.first.id, 'prd-1');
      expect(products.first.priceMinor, 1000);
      expect(products.first.description, 'A hub');
      expect(products[1].description, isNull);
    });

    test('passes the category filter to the query seam', () async {
      final products = await repository.listProducts(categoryId: 'cat-1');

      expect(products, hasLength(1));
      expect(products.single.id, 'prd-1');
      final call = query.calls.last;
      expect(call.operation, 'select');
      expect(call.table, 'products');
      expect(call.equals['category_id'], 'cat-1');
    });

    test('reads a single product or null', () async {
      expect((await repository.getProduct('prd-1'))!.name, 'Hub');
      expect(await repository.getProduct('missing'), isNull);
    });

    test('lists variants and maps jsonb attributes', () async {
      final variants = await repository.listVariants('prd-1');

      expect(variants, hasLength(1));
      expect(variants.single.id, 'var-1');
      expect(variants.single.productId, 'prd-1');
      expect(variants.single.priceMinor, 1000);
      expect(variants.single.attributes, {'color': 'black'});
    });

    test('maps a single inventory availability', () async {
      final availability = await repository.getAvailability('var-1');

      expect(availability!.variantId, 'var-1');
      expect(availability.available, 7);
      expect(availability.warehouseId, 'wh-1');
      expect(await repository.getAvailability('missing'), isNull);
    });

    test('lists availability for a set of variants', () async {
      final availability = await repository.listAvailability([
        'var-1',
        'missing',
      ]);

      expect(availability, hasLength(1));
      expect(availability.single.variantId, 'var-1');
      expect(query.calls.last.inColumn, 'variant_id');
      expect(query.calls.last.inValues, ['var-1', 'missing']);
    });
  });

  group('SupabaseAccountRepository', () {
    late SupabaseAccountRepository repository;

    setUp(() {
      query.tables['account_memberships'] = [
        {'account_id': 'acct-1', 'identity_id': 'user-1', 'role': 'b2b_buyer'},
        {
          'account_id': 'acct-2',
          'identity_id': 'user-1',
          'role': 'b2b_manager',
        },
        {
          'account_id': 'acct-3',
          'identity_id': 'user-2',
          'role': 'b2b_manager',
        },
      ];
      query.tables['business_accounts'] = [
        {'id': 'acct-1', 'name': 'Acme', 'registration_number': 'REG-1'},
        {'id': 'acct-2', 'name': 'Globex', 'registration_number': null},
      ];
      query.tables['credit_snapshots'] = [
        {
          'account_id': 'acct-1',
          'credit_limit_minor': 500000,
          'available_credit_minor': 120000,
          'captured_at': '2026-01-01T00:00:00Z',
        },
        {
          'account_id': 'acct-1',
          'credit_limit_minor': 500000,
          'available_credit_minor': 90000,
          'captured_at': '2026-02-01T00:00:00Z',
        },
      ];
      query.tables['profiles'] = [
        {
          'id': 'prof-1',
          'identity_id': 'user-1',
          'display_name': 'Buyer',
          'email': 'buyer@example.test',
        },
      ];
      repository = SupabaseAccountRepository(query: query);
    });

    test('lists only the accounts the identity belongs to', () async {
      final accounts = await repository.listAccountsForIdentity('user-1');

      expect(accounts.map((a) => a.id).toList(), ['acct-1', 'acct-2']);
      expect(accounts.first.name, 'Acme');
      expect(accounts.first.registrationNumber, 'REG-1');
      expect(await repository.listAccountsForIdentity('user-9'), isEmpty);
    });

    test('maps a membership role to the domain role', () async {
      final membership = await repository.getMembership(
        accountId: 'acct-2',
        identityId: 'user-1',
      );

      expect(membership!.role, UserRole.b2bManager);
      expect(
        await repository.getMembership(
          accountId: 'acct-3',
          identityId: 'user-1',
        ),
        isNull,
      );
    });

    test('maps the latest credit snapshot', () async {
      final credit = await repository.getCreditSnapshot('acct-1');

      expect(credit!.creditLimitMinor, 500000);
      expect(credit.availableCreditMinor, 90000);
      expect(await repository.getCreditSnapshot('acct-2'), isNull);
    });

    test('maps a customer profile', () async {
      final profile = await repository.getProfile('user-1');

      expect(profile!.id, 'prof-1');
      expect(profile.identityId, 'user-1');
      expect(profile.displayName, 'Buyer');
      expect(profile.email, 'buyer@example.test');
      expect(await repository.getProfile('user-9'), isNull);
    });

    test('saves and reads back a customer profile', () async {
      final saved = await repository.saveProfile(
        CustomerProfile(
          id: 'prof-2',
          identityId: 'user-2',
          displayName: 'New Buyer',
          email: 'new@example.test',
        ),
      );

      expect(saved.displayName, 'New Buyer');
      expect((await repository.getProfile('user-2'))!.id, 'prof-2');
    });
  });

  group('SupabaseCartRepository', () {
    late SupabaseCartRepository repository;

    setUp(() {
      query.tables['carts'] = [
        {'id': 'cart-1'},
      ];
      query.tables['cart_items'] = [
        {
          'cart_id': 'cart-1',
          'product_id': 'prd-1',
          'variant_id': 'var-1',
          'quantity': 2,
          'unit_price_minor': 1000,
        },
      ];
      repository = SupabaseCartRepository(query: query);
    });

    test('reads a cart with its items', () async {
      final cart = await repository.getCart('cart-1');

      expect(cart!.id, 'cart-1');
      expect(cart.items, hasLength(1));
      expect(cart.subtotalMinor, 2000);
      expect(await repository.getCart('missing'), isNull);
    });

    test('saves a cart and replaces its items', () async {
      await repository.saveCart(
        Cart(
          id: 'cart-2',
          items: [
            CartItem(
              productId: 'prd-1',
              variantId: 'var-1',
              quantity: 1,
              unitPriceMinor: 1000,
            ),
          ],
        ),
      );

      expect((await repository.getCart('cart-2'))!.itemCount, 1);

      await repository.saveCart(
        Cart(
          id: 'cart-2',
          items: [
            CartItem(
              productId: 'prd-1',
              variantId: 'var-1',
              quantity: 5,
              unitPriceMinor: 1000,
            ),
          ],
        ),
      );

      final reloaded = await repository.getCart('cart-2');
      expect(reloaded!.items, hasLength(1));
      expect(reloaded.itemCount, 5);
    });
  });

  group('SupabaseOrderRepository', () {
    late SupabaseOrderRepository repository;
    late Cart cart;

    setUp(() {
      var sequence = 0;
      repository = SupabaseOrderRepository(
        query: query,
        newId: () => 'order-${++sequence}',
      );
      cart = Cart(
        id: 'cart-1',
        items: [
          CartItem(
            productId: 'prd-1',
            variantId: 'var-1',
            quantity: 2,
            unitPriceMinor: 1000,
          ),
        ],
      );
    });

    test('maps a cart to an order with the cart subtotal', () async {
      final order = await repository.createOrder(
        cart: cart,
        idempotencyKey: IdempotencyKey('order-key-1'),
      );

      expect(order.id, 'order-1');
      expect(order.items, hasLength(1));
      expect(order.totalMinor, 2000);
      expect(query.tables['orders']!.single['total_minor'], 2000);
      expect(query.tables['order_items']!, hasLength(1));
    });

    test('honors the optional authoritative totalMinor', () async {
      final order = await repository.createOrder(
        cart: cart,
        idempotencyKey: IdempotencyKey('order-key-2'),
        totalMinor: 9999,
      );

      expect(order.totalMinor, 9999);
      expect(query.tables['orders']!.single['total_minor'], 9999);
    });

    test('re-submitting the same key returns the same order', () async {
      final first = await repository.createOrder(
        cart: cart,
        idempotencyKey: IdempotencyKey('order-key-3'),
      );
      final second = await repository.createOrder(
        cart: cart,
        idempotencyKey: IdempotencyKey('order-key-3'),
      );

      expect(second.id, first.id);
      expect(query.tables['orders']!, hasLength(1));
      expect(query.tables['order_items']!, hasLength(1));
    });

    test('normalizes a raw query failure to a DomainFailure', () async {
      query.error = const PostgrestException(
        message: 'duplicate key',
        code: '23505',
      );

      expect(
        () => repository.createOrder(
          cart: cart,
          idempotencyKey: IdempotencyKey('order-key-4'),
        ),
        throwsA(
          isA<DomainFailure>()
              .having((f) => f.operation, 'operation', 'createOrder')
              .having((f) => f.code, 'code', DomainFailureCode.conflict),
        ),
      );
    });
  });

  group('SupabaseQuoteRepository', () {
    late SupabaseQuoteRepository repository;

    setUp(() {
      var sequence = 0;
      repository = SupabaseQuoteRepository(
        query: query,
        newId: () => 'rfq-${++sequence}',
      );
    });

    test('creates an RFQ and is idempotent by key', () async {
      final items = [
        CartItem(
          productId: 'prd-1',
          variantId: 'var-1',
          quantity: 3,
          unitPriceMinor: 2000,
        ),
      ];

      final first = await repository.createRfq(
        accountId: 'acct-1',
        items: items,
        idempotencyKey: IdempotencyKey('rfq-key-1'),
        message: 'Please quote',
      );
      final second = await repository.createRfq(
        accountId: 'acct-1',
        items: items,
        idempotencyKey: IdempotencyKey('rfq-key-1'),
      );

      expect(first.id, 'rfq-1');
      expect(first.message, 'Please quote');
      expect(second.id, first.id);
      expect(query.tables['rfqs']!, hasLength(1));
      expect(query.tables['rfq_items']!, hasLength(1));
    });

    test('reads an RFQ with items and status', () async {
      query.tables['rfqs'] = [
        {
          'id': 'rfq-1',
          'account_id': 'acct-1',
          'status': 'quoted',
          'message': null,
          'idempotency_key': 'rfq-key-1',
        },
      ];
      query.tables['rfq_items'] = [
        {
          'rfq_id': 'rfq-1',
          'product_id': 'prd-1',
          'variant_id': 'var-1',
          'quantity': 3,
          'unit_price_minor': 2000,
        },
      ];

      final rfq = await repository.getRfq('rfq-1');

      expect(rfq!.status, RfqStatus.quoted);
      expect(rfq.items, hasLength(1));
      expect(await repository.getRfq('missing'), isNull);
    });

    test('saves a quotation and is idempotent by key', () async {
      final quotation = Quotation(
        id: 'quote-1',
        rfqId: 'rfq-1',
        totalMinor: 6000,
        status: QuotationStatus.sent,
        validUntil: DateTime.utc(2026, 12, 31),
      );

      final saved = await repository.saveQuotation(
        quotation: quotation,
        idempotencyKey: IdempotencyKey('quote-key-1'),
      );
      final replayed = await repository.saveQuotation(
        quotation: quotation,
        idempotencyKey: IdempotencyKey('quote-key-1'),
      );

      expect(saved.totalMinor, 6000);
      expect(replayed.id, 'quote-1');
      expect(query.tables['quotations']!, hasLength(1));

      final loaded = await repository.getQuotation('quote-1');
      expect(loaded!.status, QuotationStatus.sent);
      expect(loaded.validUntil, DateTime.utc(2026, 12, 31));
      expect(await repository.getQuotation('missing'), isNull);
    });
  });
}
