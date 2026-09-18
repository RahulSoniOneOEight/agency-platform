import 'package:agency_production_core/agency_production_core.dart';

import 'supabase_error_mapper.dart';
import 'supabase_query_client.dart';
import 'supabase_row_mapping.dart';

/// Supabase-backed [AccountRepository] and [CustomerRepository].
final class SupabaseAccountRepository
    implements AccountRepository, CustomerRepository {
  SupabaseAccountRepository({required SupabaseQueryClient query})
    : _query = query;

  final SupabaseQueryClient _query;

  @override
  Future<List<BusinessAccount>> listAccountsForIdentity(
    String identityId,
  ) async {
    try {
      final memberships = await _query.select(
        table: 'account_memberships',
        equals: {'identity_id': identityId},
        orderBy: 'account_id',
      );
      final accountIds = memberships
          .map((row) => stringValue(row, 'account_id'))
          .toSet()
          .toList();
      if (accountIds.isEmpty) {
        return const [];
      }
      final rows = await _query.select(
        table: 'business_accounts',
        inColumn: 'id',
        inValues: accountIds,
        orderBy: 'id',
      );
      return rows.map(businessAccountFromRow).toList();
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'listAccountsForIdentity');
    }
  }

  @override
  Future<AccountMembership?> getMembership({
    required String accountId,
    required String identityId,
  }) async {
    try {
      final rows = await _query.select(
        table: 'account_memberships',
        equals: {'account_id': accountId, 'identity_id': identityId},
        limit: 1,
      );
      return rows.isEmpty ? null : accountMembershipFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getMembership');
    }
  }

  @override
  Future<CreditSnapshot?> getCreditSnapshot(String accountId) async {
    try {
      final rows = await _query.select(
        table: 'credit_snapshots',
        equals: {'account_id': accountId},
        orderBy: 'captured_at',
        ascending: false,
        limit: 1,
      );
      return rows.isEmpty ? null : creditSnapshotFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getCreditSnapshot');
    }
  }

  @override
  Future<CustomerProfile?> getProfile(String identityId) async {
    try {
      final rows = await _query.select(
        table: 'profiles',
        equals: {'identity_id': identityId},
        limit: 1,
      );
      return rows.isEmpty ? null : customerProfileFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getProfile');
    }
  }

  @override
  Future<CustomerProfile> saveProfile(CustomerProfile profile) async {
    try {
      final rows = await _query.insert(
        table: 'profiles',
        rows: [customerProfileToRow(profile)],
        onConflict: 'identity_id',
      );
      return customerProfileFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'saveProfile');
    }
  }
}
