import 'package:agency_production_core/agency_production_core.dart';
import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase_clients.dart';

void main() {
  late FakeSupabaseAuthClient auth;
  late FakeSupabaseQueryClient query;
  late SupabaseAuthAdapter adapter;

  const session = SupabaseAuthSession(
    userId: 'user-1',
    email: 'buyer@example.test',
    displayName: 'Buyer',
  );

  setUp(() {
    auth = FakeSupabaseAuthClient();
    query = FakeSupabaseQueryClient();
    query.tables['profiles'] = [
      {
        'id': 'prof-1',
        'identity_id': 'user-1',
        'display_name': 'Buyer Profile',
        'email': 'profile@example.test',
      },
    ];
    query.tables['account_memberships'] = [
      {'account_id': 'acct-1', 'identity_id': 'user-1', 'role': 'b2b_buyer'},
      {'account_id': 'acct-2', 'identity_id': 'user-1', 'role': 'b2b_manager'},
    ];
    adapter = SupabaseAuthAdapter(auth: auth, query: query);
  });

  group('SupabaseAuthAdapter identity resolution', () {
    test('signIn resolves identity, memberships and per-account roles', () async {
      auth.signInResult = session;

      final identity = await adapter.signIn(
        email: 'buyer@example.test',
        password: 'secret',
      );

      expect(auth.signInCalls, 1);
      expect(identity.id, 'user-1');
      expect(identity.email, 'profile@example.test');
      expect(identity.displayName, 'Buyer Profile');
      expect(identity.role, UserRole.consumer);
      expect(identity.memberships, hasLength(2));
      expect(identity.memberships.first.role, UserRole.b2bBuyer);
      expect(identity.memberships.last.role, UserRole.b2bManager);
    });

    test('uses the auth session role when the provider exposes one', () async {
      auth.signInResult = const SupabaseAuthSession(
        userId: 'user-1',
        email: 'admin@example.test',
        role: 'admin',
      );

      final identity = await adapter.signIn(
        email: 'admin@example.test',
        password: 'secret',
      );

      expect(identity.role, UserRole.admin);
    });

    test('falls back to the session when no profile row exists', () async {
      query.tables.remove('profiles');
      auth.signInResult = session;

      final identity = await adapter.signIn(
        email: 'buyer@example.test',
        password: 'secret',
      );

      expect(identity.email, 'buyer@example.test');
      expect(identity.displayName, 'Buyer');
    });

    test('currentIdentity returns null when signed out', () async {
      auth.session = null;

      expect(await adapter.currentIdentity(), isNull);
    });

    test('currentIdentity returns the resolved identity', () async {
      auth.session = session;

      final identity = await adapter.currentIdentity();

      expect(identity!.id, 'user-1');
      expect(identity.memberships, hasLength(2));
    });

    test('refreshSession returns the refreshed identity', () async {
      auth.refreshResult = session;

      final identity = await adapter.refreshSession();

      expect(auth.refreshCalls, 1);
      expect(identity.id, 'user-1');
    });

    test('refreshSession fails with unauthorized when no session exists', () async {
      auth.refreshResult = null;

      await expectLater(
        adapter.refreshSession(),
        throwsA(
          isA<DomainFailure>().having(
            (f) => f.code,
            'code',
            DomainFailureCode.unauthorized,
          ),
        ),
      );
    });

    test('signOut clears the session', () async {
      auth.session = session;

      await adapter.signOut();

      expect(auth.signedOut, isTrue);
    });
  });

  group('SupabaseAuthAdapter stream', () {
    test('authStateChanges emits identity then null', () async {
      final future = adapter.authStateChanges().take(2).toList();

      auth.controller.add(session);
      auth.controller.add(null);

      final emissions = await future;
      expect(emissions, hasLength(2));
      expect(emissions.first!.id, 'user-1');
      expect(emissions.last, isNull);
    });
  });

  group('SupabaseAuthAdapter failure normalization', () {
    test('maps an auth failure to unauthorized without leaking it', () async {
      auth.signInError = const AuthException(
        'Invalid login credentials',
        statusCode: '401',
      );

      await expectLater(
        adapter.signIn(email: 'buyer@example.test', password: 'nope'),
        throwsA(
          isA<DomainFailure>()
              .having((f) => f.code, 'code', DomainFailureCode.unauthorized)
              .having((f) => f.operation, 'operation', 'signIn'),
        ),
      );
    });

    test('maps a retryable auth failure to unavailable', () async {
      auth.signInError = AuthRetryableFetchException();

      await expectLater(
        adapter.signIn(email: 'buyer@example.test', password: 'secret'),
        throwsA(
          isA<DomainFailure>()
              .having((f) => f.code, 'code', DomainFailureCode.unavailable)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('maps a query failure while resolving identity', () async {
      auth.signInResult = session;
      query.error = const PostgrestException(
        message: 'permission denied',
        code: '42501',
      );

      await expectLater(
        adapter.signIn(email: 'buyer@example.test', password: 'secret'),
        throwsA(
          isA<DomainFailure>().having(
            (f) => f.code,
            'code',
            DomainFailureCode.forbidden,
          ),
        ),
      );
    });
  });
}
