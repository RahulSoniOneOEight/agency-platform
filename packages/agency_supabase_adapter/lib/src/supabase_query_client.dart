import 'package:supabase_flutter/supabase_flutter.dart';

/// Narrow query seam over Supabase/PostgREST.
///
/// Repository adapters depend on this abstraction rather than on
/// [SupabaseClient] directly, so tests can inject a deterministic in-memory
/// fake and normal CI never needs a live Supabase project. This is the only
/// place where the package couples repositories to PostgREST wire mechanics.
abstract interface class SupabaseQueryClient {
  /// Selects rows from [table] applying equality filters in [equals], an
  /// optional `in` filter, ordering and a limit.
  Future<List<Map<String, dynamic>>> select({
    required String table,
    String columns = '*',
    Map<String, Object?> equals = const {},
    String? inColumn,
    List<Object?>? inValues,
    String? orderBy,
    bool ascending = true,
    int? limit,
  });

  /// Inserts [rows] into [table]. When [onConflict] is supplied the operation
  /// upserts on those columns. Returns the persisted rows.
  Future<List<Map<String, dynamic>>> insert({
    required String table,
    required List<Map<String, Object?>> rows,
    String? onConflict,
  });

  /// Deletes rows from [table] matching every entry in [equals].
  Future<void> delete({
    required String table,
    required Map<String, Object?> equals,
  });
}

/// Builds the production [SupabaseQueryClient] from a live [SupabaseClient].
///
/// This is the public composition-root entry point: the concrete
/// [SupabasePostgrestQueryClient] class stays internal to `src/` so its raw
/// PostgREST exception surface is not exported.
SupabaseQueryClient createSupabaseQueryClient(SupabaseClient client) =>
    SupabasePostgrestQueryClient(client);

/// Production [SupabaseQueryClient] backed by a live [SupabaseClient].
final class SupabasePostgrestQueryClient implements SupabaseQueryClient {
  SupabasePostgrestQueryClient(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> select({
    required String table,
    String columns = '*',
    Map<String, Object?> equals = const {},
    String? inColumn,
    List<Object?>? inValues,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    var query = _client.from(table).select(columns);
    for (final entry in equals.entries) {
      final value = entry.value;
      if (value != null) {
        query = query.eq(entry.key, value);
      }
    }
    if (inColumn != null && inValues != null) {
      query = query.inFilter(inColumn, inValues);
    }
    PostgrestTransformBuilder<List<Map<String, dynamic>>> transform = query;
    if (orderBy != null) {
      transform = transform.order(orderBy, ascending: ascending);
    }
    if (limit != null) {
      transform = transform.limit(limit);
    }
    final data = await transform;
    return data.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> insert({
    required String table,
    required List<Map<String, Object?>> rows,
    String? onConflict,
  }) async {
    final Object values = rows.length == 1 ? rows.first : rows;
    final builder = onConflict == null
        ? _client.from(table).insert(values)
        : _client.from(table).upsert(values, onConflict: onConflict);
    final data = await builder.select();
    return data.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> delete({
    required String table,
    required Map<String, Object?> equals,
  }) async {
    var query = _client.from(table).delete();
    for (final entry in equals.entries) {
      final value = entry.value;
      if (value != null) {
        query = query.eq(entry.key, value);
      }
    }
    await query;
  }
}
