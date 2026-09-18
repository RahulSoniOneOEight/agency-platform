import '../domain/identity.dart';

/// Provider-neutral authentication contract.
///
/// Implementations (Supabase Auth or any other provider) must translate
/// provider-specific errors into `DomainFailure` before they cross this
/// boundary. No provider type may appear in this signature.
abstract interface class AuthService {
  /// Emits the current identity, or `null` when signed out.
  Stream<AppIdentity?> authStateChanges();

  /// Authenticates with email/password and returns the resolved identity.
  Future<AppIdentity> signIn({
    required String email,
    required String password,
  });

  /// Clears the current session.
  Future<void> signOut();

  /// Returns the current identity without forcing a network refresh, or
  /// `null` when there is no active session.
  Future<AppIdentity?> currentIdentity();

  /// Refreshes the session and returns the refreshed identity.
  Future<AppIdentity> refreshSession();
}
