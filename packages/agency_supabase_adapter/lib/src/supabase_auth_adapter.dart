import 'package:agency_production_core/agency_production_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_error_mapper.dart';
import 'supabase_query_client.dart';
import 'supabase_row_mapping.dart';

/// Provider-neutral view of an authenticated Supabase session.
final class SupabaseAuthSession {
  const SupabaseAuthSession({
    required this.userId,
    this.email,
    this.displayName,
    this.role,
  });

  final String userId;
  final String? email;
  final String? displayName;
  final String? role;
}

/// Narrow auth seam over Supabase Auth (GoTrue).
///
/// Adapters depend on this rather than on `GoTrueClient` directly so tests can
/// inject a deterministic fake with no network. Implementations must translate
/// provider failures to [DomainFailure] before crossing adapter boundaries.
abstract interface class SupabaseAuthClient {
  Stream<SupabaseAuthSession?> authStateChanges();

  Future<SupabaseAuthSession> signInWithPassword({
    required String email,
    required String password,
  });

  Future<SupabaseAuthSession?> currentSession();

  Future<SupabaseAuthSession?> refreshSession();

  Future<void> signOut();
}

/// Maps a provider [Session] to the provider-neutral [SupabaseAuthSession].
///
/// The global role is read from `app_metadata`, which is server-controlled.
/// `user_metadata` is client-writable, so it is deliberately never consulted
/// for the role — otherwise a user could self-escalate to `admin`. Display
/// name is cosmetic and may come from `user_metadata`.
SupabaseAuthSession? supabaseAuthSessionFromSession(Session? session) {
  if (session == null) {
    return null;
  }
  final user = session.user;
  final metadata = user.userMetadata ?? const <String, dynamic>{};
  final displayName =
      metadata['display_name'] ?? metadata['full_name'] ?? metadata['name'];
  final role = user.appMetadata['role'];
  return SupabaseAuthSession(
    userId: user.id,
    email: user.email,
    displayName: displayName is String ? displayName : null,
    role: role is String ? role : null,
  );
}

/// Builds the production [SupabaseAuthClient] from a live [GoTrueClient].
///
/// This is the public composition-root entry point: the concrete
/// [SupabaseGoTrueAuthClient] class stays internal to `src/` so its raw auth
/// exception surface is not exported.
SupabaseAuthClient createSupabaseAuthClient(GoTrueClient auth) =>
    SupabaseGoTrueAuthClient(auth);

/// Production [SupabaseAuthClient] backed by a live `GoTrueClient`.
///
/// Internal to the package: this is the only class that touches a provider
/// client directly, so it is intentionally not part of the public barrel.
final class SupabaseGoTrueAuthClient implements SupabaseAuthClient {
  SupabaseGoTrueAuthClient(this._auth);

  final GoTrueClient _auth;

  @override
  Stream<SupabaseAuthSession?> authStateChanges() =>
      _auth.onAuthStateChange.map(
        (state) => supabaseAuthSessionFromSession(state.session),
      );

  @override
  Future<SupabaseAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    final session = supabaseAuthSessionFromSession(response.session);
    if (session == null) {
      throw const AuthException('Sign-in did not return a session');
    }
    return session;
  }

  @override
  Future<SupabaseAuthSession?> currentSession() async =>
      supabaseAuthSessionFromSession(_auth.currentSession);

  @override
  Future<SupabaseAuthSession?> refreshSession() async =>
      supabaseAuthSessionFromSession((await _auth.refreshSession()).session);

  @override
  Future<void> signOut() => _auth.signOut();
}

/// [AuthService] implementation backed by Supabase Auth.
///
/// Membership roles are resolved per account from `account_memberships`, never
/// from a single global user role. No Supabase exception leaves these methods.
final class SupabaseAuthAdapter implements AuthService {
  SupabaseAuthAdapter({
    required SupabaseAuthClient auth,
    required SupabaseQueryClient query,
    this.profileTable = 'profiles',
    this.membershipTable = 'account_memberships',
  }) : _auth = auth,
       _query = query;

  final SupabaseAuthClient _auth;
  final SupabaseQueryClient _query;
  final String profileTable;
  final String membershipTable;

  @override
  Stream<AppIdentity?> authStateChanges() async* {
    try {
      await for (final session in _auth.authStateChanges()) {
        yield session == null ? null : await _resolveIdentity(session);
      }
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'authStateChanges');
    }
  }

  @override
  Future<AppIdentity> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final session = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      return await _resolveIdentity(session);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'signIn');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'signOut');
    }
  }

  @override
  Future<AppIdentity?> currentIdentity() async {
    try {
      final session = await _auth.currentSession();
      if (session == null) {
        return null;
      }
      return await _resolveIdentity(session);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'currentIdentity');
    }
  }

  @override
  Future<AppIdentity> refreshSession() async {
    try {
      final session = await _auth.refreshSession();
      if (session == null) {
        throw const DomainFailure(
          code: DomainFailureCode.unauthorized,
          operation: 'refreshSession',
          retryable: false,
          message: 'No active session to refresh',
        );
      }
      return await _resolveIdentity(session);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'refreshSession');
    }
  }

  Future<AppIdentity> _resolveIdentity(SupabaseAuthSession session) async {
    final profiles = await _query.select(
      table: profileTable,
      equals: {'identity_id': session.userId},
      limit: 1,
    );
    final memberships = await _query.select(
      table: membershipTable,
      equals: {'identity_id': session.userId},
      orderBy: 'account_id',
    );
    final profile = profiles.isEmpty ? null : profiles.first;
    final email = nullableString(profile ?? const {}, 'email') ??
        session.email ??
        '';
    final displayName =
        nullableString(profile ?? const {}, 'display_name') ??
        session.displayName ??
        email;
    return AppIdentity(
      id: session.userId,
      email: email,
      displayName: displayName,
      role: parseUserRole(session.role),
      memberships: memberships.map(accountMembershipFromRow).toList(),
    );
  }
}
