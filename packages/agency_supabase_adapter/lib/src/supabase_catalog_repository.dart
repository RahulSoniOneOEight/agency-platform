import 'package:agency_production_core/agency_production_core.dart';

import 'supabase_error_mapper.dart';
import 'supabase_query_client.dart';
import 'supabase_row_mapping.dart';

/// Supabase-backed [CatalogRepository] and [InventoryRepository].
final class SupabaseCatalogRepository
    implements CatalogRepository, InventoryRepository {
  SupabaseCatalogRepository({required SupabaseQueryClient query})
    : _query = query;

  final SupabaseQueryClient _query;

  @override
  Future<List<Product>> listProducts({String? categoryId}) async {
    try {
      final rows = await _query.select(
        table: 'products',
        equals: categoryId == null ? const {} : {'category_id': categoryId},
        orderBy: 'id',
      );
      return rows.map(productFromRow).toList();
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'listProducts');
    }
  }

  @override
  Future<Product?> getProduct(String productId) async {
    try {
      final rows = await _query.select(
        table: 'products',
        equals: {'id': productId},
        limit: 1,
      );
      return rows.isEmpty ? null : productFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getProduct');
    }
  }

  @override
  Future<List<Variant>> listVariants(String productId) async {
    try {
      final rows = await _query.select(
        table: 'variants',
        equals: {'product_id': productId},
        orderBy: 'id',
      );
      return rows.map(variantFromRow).toList();
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'listVariants');
    }
  }

  @override
  Future<InventoryAvailability?> getAvailability(String variantId) async {
    try {
      final rows = await _query.select(
        table: 'inventory',
        equals: {'variant_id': variantId},
        limit: 1,
      );
      return rows.isEmpty ? null : inventoryFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getAvailability');
    }
  }

  @override
  Future<List<InventoryAvailability>> listAvailability(
    Iterable<String> variantIds,
  ) async {
    final ids = variantIds.toList();
    if (ids.isEmpty) {
      return const [];
    }
    try {
      final rows = await _query.select(
        table: 'inventory',
        inColumn: 'variant_id',
        inValues: ids,
      );
      return rows.map(inventoryFromRow).toList();
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'listAvailability');
    }
  }
}
