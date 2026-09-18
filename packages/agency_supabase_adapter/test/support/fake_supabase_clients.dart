import 'dart:async';

import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';

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

  Object? error;

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
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    final store = tables.putIfAbsent(table, () => []);
    final inserted = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (onConflict != null) {
        final keys = onConflict.split(',');
        final index = store.indexWhere(
          (existing) => keys.every((key) => existing[key] == row[key]),
        );
        if (index >= 0) {
          final merged = <String, dynamic>{...store[index], ...row};
          store[index] = merged;
          inserted.add(Map<String, dynamic>.from(merged));
          continue;
        }
      }
      final copy = Map<String, dynamic>.from(row);
      copy.putIfAbsent('id', () => '$table-${store.length + 1}');
      store.add(copy);
      inserted.add(Map<String, dynamic>.from(copy));
    }
    return inserted;
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
