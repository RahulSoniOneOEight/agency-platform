import 'dart:async';

import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records the arguments of a single query-seam invocation.
final class QueryCall {
  QueryCall({
    required this.operation,
    required this.table,
    this.equals = const {},
    this.inColumn,
    this.inValues,
    this.orderBy,
    this.ascending = true,
    this.limit,
    this.rows = const [],
    this.onConflict,
  });

  final String operation;
  final String table;
  final Map<String, Object?> equals;
  final String? inColumn;
  final List<Object?>? inValues;
  final String? orderBy;
  final bool ascending;
  final int? limit;
  final List<Map<String, Object?>> rows;
  final String? onConflict;
}

/// Deterministic in-memory [SupabaseQueryClient] with no network dependency.
///
/// Tables are plain lists of rows. [error], when set, is thrown by every
/// operation so adapter failure normalization can be exercised.
final class FakeSupabaseQueryClient implements SupabaseQueryClient {
  final Map<String, List<Map<String, dynamic>>> tables = {};
  final List<QueryCall> calls = [];

  /// The authenticated user the seam operates as. Ownership writes
  /// (`carts`/`orders`/`rfqs`) are validated against it exactly as the shipped
  /// RLS policies validate `identity_id = auth.uid()`.
  @override
  String? currentUserId;

  Object? error;

  /// Optional failure thrown by [insert] only (e.g. a unique violation).
  Object? insertError;

  /// Invoked before every [insert]; lets a test simulate a concurrent writer.
  void Function(String table)? onInsert;

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
    calls.add(
      QueryCall(
        operation: 'select',
        table: table,
        equals: equals,
        inColumn: inColumn,
        inValues: inValues,
        orderBy: orderBy,
        ascending: ascending,
        limit: limit,
      ),
    );
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    var rows = List<Map<String, dynamic>>.from(tables[table] ?? const []);
    for (final entry in equals.entries) {
      rows = rows.where((row) => row[entry.key] == entry.value).toList();
    }
    if (inColumn != null && inValues != null) {
      rows = rows.where((row) => inValues.contains(row[inColumn])).toList();
    }
    if (orderBy != null) {
      rows.sort((a, b) {
        final left = a[orderBy];
        final right = b[orderBy];
        final comparison = (left is Comparable && right is Comparable)
            ? left.compareTo(right)
            : '$left'.compareTo('$right');
        return ascending ? comparison : -comparison;
      });
    }
    if (limit != null) {
      rows = rows.take(limit).toList();
    }
    return rows.map(Map<String, dynamic>.from).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> insert({
    required String table,
    required List<Map<String, Object?>> rows,
    String? onConflict,
  }) async {
    calls.add(
      QueryCall(
        operation: 'insert',
        table: table,
        rows: rows,
        onConflict: onConflict,
      ),
    );
    onInsert?.call(table);
    final failure = insertError ?? error;
    if (failure != null) {
      throw failure;
    }
    final store = tables.putIfAbsent(table, () => []);
    final inserted = <Map<String, dynamic>>[];
    for (final rawRow in rows) {
      // Split embedded child rows (e.g. `order_items`) from the parent row to
      // model PostgREST's atomic nested insert.
      final row = <String, dynamic>{};
      final nested = <String, List<Map<String, dynamic>>>{};
      rawRow.forEach((key, value) {
        if (value is List && value.every((child) => child is Map)) {
          nested[key] = [
            for (final child in value) Map<String, dynamic>.from(child as Map),
          ];
        } else {
          row[key] = value;
        }
      });

      _enforceOwnershipConstraints(table, row);

      Map<String, dynamic> stored;
      if (onConflict != null) {
        final keys = onConflict.split(',');
        final index = store.indexWhere(
          (existing) => keys.every((key) => existing[key] == row[key]),
        );
        if (index >= 0) {
          stored = <String, dynamic>{...store[index], ...row};
          store[index] = stored;
        } else {
          stored = Map<String, dynamic>.from(row);
          stored.putIfAbsent('id', () => '$table-${store.length + 1}');
          store.add(stored);
        }
      } else {
        stored = Map<String, dynamic>.from(row);
        stored.putIfAbsent('id', () => '$table-${store.length + 1}');
        store.add(stored);
      }

      final foreignKey = table.endsWith('s')
          ? '${table.substring(0, table.length - 1)}_id'
          : '${table}_id';
      nested.forEach((childTable, childRows) {
        final childStore = tables.putIfAbsent(childTable, () => []);
        for (final child in childRows) {
          final childRow = Map<String, dynamic>.from(child);
          childRow[foreignKey] = stored['id'];
          childRow.putIfAbsent(
            'id',
            () => '$childTable-${childStore.length + 1}',
          );
          childStore.add(childRow);
        }
      });

      inserted.add(Map<String, dynamic>.from(stored));
    }
    return inserted;
  }

  /// Tables whose inserts are ownership-scoped by the shipped schema/RLS.
  static const Set<String> _ownedTables = {'carts', 'orders', 'rfqs'};

  /// Enforces the shipped ownership rules on [table]'s parent row:
  ///
  /// - the schema CHECK `account_id is not null or identity_id is not null`
  ///   (Postgres `23514`);
  /// - the RLS identity rule `identity_id = auth.uid()` (Postgres `42501`).
  ///
  /// This keeps adapter tests honest: a payload the real reference schema/RLS
  /// would reject fails here instead of silently passing.
  void _enforceOwnershipConstraints(
    String table,
    Map<String, dynamic> row,
  ) {
    if (!_ownedTables.contains(table)) {
      return;
    }
    final identityId = row['identity_id'];
    final accountId = row['account_id'];
    if (identityId == null && accountId == null) {
      throw PostgrestException(
        message: 'new row for relation "$table" violates check constraint',
        code: '23514',
      );
    }
    if (identityId != currentUserId) {
      throw PostgrestException(
        message: 'new row violates row-level security policy for "$table"',
        code: '42501',
      );
    }
  }

  @override
  Future<void> delete({
    required String table,
    required Map<String, Object?> equals,
  }) async {
    calls.add(
      QueryCall(operation: 'delete', table: table, equals: equals),
    );
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    final store = tables[table];
    if (store == null) {
      return;
    }
    store.removeWhere(
      (row) => equals.entries.every((entry) => row[entry.key] == entry.value),
    );
  }
}

/// Deterministic in-memory [SupabaseAuthClient] with no network dependency.
final class FakeSupabaseAuthClient implements SupabaseAuthClient {
  final StreamController<SupabaseAuthSession?> controller =
      StreamController<SupabaseAuthSession?>();

  SupabaseAuthSession? session;
  SupabaseAuthSession? signInResult;
  SupabaseAuthSession? refreshResult;
  Object? signInError;
  Object? currentSessionError;
  Object? refreshError;
  Object? signOutError;
  bool signedOut = false;
  int signInCalls = 0;
  int refreshCalls = 0;

  @override
  Stream<SupabaseAuthSession?> authStateChanges() => controller.stream;

  @override
  Future<SupabaseAuthSession?> currentSession() async {
    final failure = currentSessionError;
    if (failure != null) {
      throw failure;
    }
    return session;
  }

  @override
  Future<SupabaseAuthSession?> refreshSession() async {
    refreshCalls += 1;
    final failure = refreshError;
    if (failure != null) {
      throw failure;
    }
    return refreshResult;
  }

  @override
  Future<SupabaseAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls += 1;
    final failure = signInError;
    if (failure != null) {
      throw failure;
    }
    final result = signInResult;
    if (result == null) {
      throw StateError('FakeSupabaseAuthClient.signInResult not configured');
    }
    session = result;
    return result;
  }

  @override
  Future<void> signOut() async {
    final failure = signOutError;
    if (failure != null) {
      throw failure;
    }
    signedOut = true;
    session = null;
  }
}
