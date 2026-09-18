import 'package:agency_production_core/agency_production_core.dart';

import 'supabase_error_mapper.dart';
import 'supabase_query_client.dart';
import 'supabase_row_mapping.dart';

/// Supabase-backed [CartRepository].
final class SupabaseCartRepository implements CartRepository {
  SupabaseCartRepository({required SupabaseQueryClient query})
    : _query = query;

  final SupabaseQueryClient _query;

  @override
  Future<Cart?> getCart(String cartId) async {
    try {
      final carts = await _query.select(
        table: 'carts',
        equals: {'id': cartId},
        limit: 1,
      );
      if (carts.isEmpty) {
        return null;
      }
      final items = await _query.select(
        table: 'cart_items',
        equals: {'cart_id': cartId},
        orderBy: 'id',
      );
      return cartFromRow(carts.first, items);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getCart');
    }
  }

  @override
  Future<Cart> saveCart(Cart cart, {String? accountId}) async {
    // Ownership is set explicitly here (not by a DB default/trigger) so the
    // reference write path is self-consistent with the shipped RLS policies.
    // A cart must carry an identity (`identity_id = auth.uid()`) and/or an
    // account; a row with neither would be rejected by the schema CHECK.
    final identityId = _query.currentUserId;
    if (identityId == null && accountId == null) {
      throw const DomainFailure(
        code: DomainFailureCode.unauthorized,
        operation: 'saveCart',
        retryable: false,
        message: 'A cart must be attributed to an identity or an account',
      );
    }
    try {
      await _query.insert(
        table: 'carts',
        rows: [
          {
            'id': cart.id,
            'identity_id': identityId,
            'account_id': accountId,
          },
        ],
        onConflict: 'id',
      );
      await _query.delete(table: 'cart_items', equals: {'cart_id': cart.id});
      if (cart.items.isNotEmpty) {
        await _query.insert(
          table: 'cart_items',
          rows: [
            for (final item in cart.items) cartItemToRow(cart.id, item),
          ],
        );
      }
      return cart;
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'saveCart');
    }
  }
}
