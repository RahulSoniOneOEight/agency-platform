import 'package:agency_production_core/agency_production_core.dart';

import 'supabase_error_mapper.dart';
import 'supabase_query_client.dart';
import 'supabase_row_mapping.dart';

/// Supabase-backed [OrderRepository].
///
/// Idempotency is enforced by the `orders.idempotency_key` unique constraint
/// and a pre-read, so re-submitting the same key returns the persisted order
/// instead of creating a duplicate. A concurrent duplicate that trips the
/// unique constraint is caught, re-read, and returned.
final class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository({
    required SupabaseQueryClient query,
    String Function()? newId,
  }) : _query = query,
       _newId = newId ?? generateSupabaseId;

  final SupabaseQueryClient _query;
  final String Function() _newId;

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
    int? totalMinor,
  }) async {
    final existing = await _loadByIdempotencyKey(idempotencyKey.value);
    if (existing != null) {
      return existing;
    }

    final id = _newId();
    final total = totalMinor ?? cart.subtotalMinor;
    try {
      await _query.insert(
        table: 'orders',
        rows: [
          {
            'id': id,
            'status': OrderStatus.pending.name,
            'total_minor': total,
            'idempotency_key': idempotencyKey.value,
          },
        ],
      );
      if (cart.items.isNotEmpty) {
        await _query.insert(
          table: 'order_items',
          rows: [
            for (final item in cart.items)
              {
                'order_id': id,
                'product_id': item.productId,
                'variant_id': item.variantId,
                'quantity': item.quantity,
                'unit_price_minor': item.unitPriceMinor,
              },
          ],
        );
      }
    } on DomainFailure catch (failure) {
      if (failure.code == DomainFailureCode.conflict) {
        final replayed = await _loadByIdempotencyKey(idempotencyKey.value);
        if (replayed != null) {
          return replayed;
        }
      }
      rethrow;
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'createOrder');
    }

    return Order(
      id: id,
      items: [
        for (final item in cart.items)
          OrderItem(
            productId: item.productId,
            variantId: item.variantId,
            quantity: item.quantity,
            unitPriceMinor: item.unitPriceMinor,
          ),
      ],
      totalMinor: total,
    );
  }

  Future<Order?> _loadByIdempotencyKey(String idempotencyKey) async {
    try {
      final orders = await _query.select(
        table: 'orders',
        equals: {'idempotency_key': idempotencyKey},
        limit: 1,
      );
      if (orders.isEmpty) {
        return null;
      }
      final orderId = stringValue(orders.first, 'id');
      final items = await _query.select(
        table: 'order_items',
        equals: {'order_id': orderId},
        orderBy: 'id',
      );
      return orderFromRow(orders.first, items);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'createOrder');
    }
  }
}
