import 'package:agency_production_core/agency_production_core.dart';
import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase_clients.dart';

/// Proves the reference write adapters attribute ownership the way the shipped
/// schema CHECK and RLS policies require, and that the fake query seam rejects
/// payloads the real reference backend would reject.
void main() {
  late FakeSupabaseQueryClient query;

  setUp(() {
    query = FakeSupabaseQueryClient();
  });

  Cart cart() => Cart(
        id: 'cart-1',
        items: [
          CartItem(
            productId: 'prd-1',
            variantId: 'var-1',
            quantity: 1,
            unitPriceMinor: 1000,
          ),
        ],
      );

  group('ownership columns are written explicitly', () {
    test('a B2C cart persists with identity_id set', () async {
      query.currentUserId = 'user-1';
      final repository = SupabaseCartRepository(query: query);

      await repository.saveCart(cart());

      final row = query.tables['carts']!.single;
      expect(row['identity_id'], 'user-1');
      expect(row['account_id'], isNull);
    });

    test('a B2C order persists with identity_id set', () async {
      query.currentUserId = 'user-1';
      final repository = SupabaseOrderRepository(
        query: query,
        newId: () => 'order-1',
      );

      final order = await repository.createOrder(
        cart: cart(),
        idempotencyKey: IdempotencyKey('order-key-1'),
      );

      expect(order.id, 'order-1');
      final row = query.tables['orders']!.single;
      expect(row['identity_id'], 'user-1');
      expect(row['account_id'], isNull);
    });

    test('a B2B order conversion persists with account_id set', () async {
      query.currentUserId = 'user-1';
      final repository = SupabaseOrderRepository(
        query: query,
        newId: () => 'order-1',
      );

      await repository.createOrder(
        cart: cart(),
        idempotencyKey: IdempotencyKey('order-key-b2b'),
        accountId: 'acct-1',
      );

      final row = query.tables['orders']!.single;
      expect(row['account_id'], 'acct-1');
      expect(row['identity_id'], 'user-1');
    });

    test('an RFQ persists with identity_id and account_id set', () async {
      query.currentUserId = 'user-1';
      final repository = SupabaseQuoteRepository(
        query: query,
        newId: () => 'rfq-1',
      );

      await repository.createRfq(
        accountId: 'acct-1',
        items: cart().items,
        idempotencyKey: IdempotencyKey('rfq-key-1'),
      );

      final row = query.tables['rfqs']!.single;
      expect(row['identity_id'], 'user-1');
      expect(row['account_id'], 'acct-1');
    });
  });

  group('unattributable writes fail before reaching the database', () {
    test('a cart write with neither owner is rejected', () async {
      query.currentUserId = null;
      final repository = SupabaseCartRepository(query: query);

      expect(
        () => repository.saveCart(cart()),
        throwsA(
          isA<DomainFailure>()
              .having((f) => f.code, 'code', DomainFailureCode.unauthorized)
              .having((f) => f.operation, 'operation', 'saveCart'),
        ),
      );
      expect(query.calls.where((call) => call.operation == 'insert'), isEmpty);
    });

    test('an order write with neither owner is rejected', () async {
      query.currentUserId = null;
      final repository = SupabaseOrderRepository(query: query);

      expect(
        () => repository.createOrder(
          cart: cart(),
          idempotencyKey: IdempotencyKey('order-key-orphan'),
        ),
        throwsA(
          isA<DomainFailure>()
              .having((f) => f.code, 'code', DomainFailureCode.unauthorized)
              .having((f) => f.operation, 'operation', 'createOrder'),
        ),
      );
      expect(query.calls.where((call) => call.operation == 'insert'), isEmpty);
    });
  });

  group('the fake seam enforces the shipped constraints', () {
    test('rejects a row with neither owner (schema CHECK, 23514)', () {
      query.currentUserId = 'user-1';

      expect(
        () => query.insert(table: 'carts', rows: [{'id': 'cart-x'}]),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '23514'),
        ),
      );
    });

    test('rejects a mismatched identity (RLS rule, 42501)', () {
      query.currentUserId = 'user-1';

      expect(
        () => query.insert(
          table: 'orders',
          rows: [{'id': 'order-x', 'identity_id': 'user-2'}],
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    });
  });
}
