import 'dart:async';
import 'dart:io';

import 'package:agency_production_core/agency_production_core.dart';
import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapSupabaseFailure auth failures', () {
    test('maps a 401 auth failure to unauthorized and is not retryable', () {
      final failure = mapSupabaseFailure(
        const AuthException('Invalid credentials', statusCode: '401'),
        operation: 'signIn',
      );

      expect(failure.code, DomainFailureCode.unauthorized);
      expect(failure.operation, 'signIn');
      expect(failure.retryable, isFalse);
      expect(failure.message, isNotEmpty);
    });

    test('maps a 403 auth failure to forbidden', () {
      final failure = mapSupabaseFailure(
        const AuthException('Forbidden', statusCode: '403'),
        operation: 'signIn',
      );

      expect(failure.code, DomainFailureCode.forbidden);
      expect(failure.retryable, isFalse);
    });

    test('maps a retryable fetch auth failure to unavailable', () {
      final failure = mapSupabaseFailure(
        AuthRetryableFetchException(),
        operation: 'refreshSession',
      );

      expect(failure.code, DomainFailureCode.unavailable);
      expect(failure.retryable, isTrue);
    });

    test('maps a status-less auth failure to unauthorized', () {
      final failure = mapSupabaseFailure(
        const AuthException('Something went wrong'),
        operation: 'signIn',
      );

      expect(failure.code, DomainFailureCode.unauthorized);
    });
  });

  group('mapSupabaseFailure PostgREST failures', () {
    test('maps a unique violation to conflict', () {
      final failure = mapSupabaseFailure(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        ),
        operation: 'createOrder',
      );

      expect(failure.code, DomainFailureCode.conflict);
      expect(failure.retryable, isFalse);
    });

    test('maps a foreign key violation to conflict', () {
      final failure = mapSupabaseFailure(
        const PostgrestException(message: 'fk violation', code: '23503'),
        operation: 'saveCart',
      );

      expect(failure.code, DomainFailureCode.conflict);
    });

    test('maps an insufficient privilege error to forbidden', () {
      final failure = mapSupabaseFailure(
        const PostgrestException(message: 'permission denied', code: '42501'),
        operation: 'getProduct',
      );

      expect(failure.code, DomainFailureCode.forbidden);
    });

    test('maps a check violation to validation', () {
      final failure = mapSupabaseFailure(
        const PostgrestException(message: 'check failed', code: '23514'),
        operation: 'createOrder',
      );

      expect(failure.code, DomainFailureCode.validation);
      expect(failure.retryable, isFalse);
    });

    test('maps an unrecognized PostgREST error to unknown', () {
      final failure = mapSupabaseFailure(
        const PostgrestException(message: 'unexpected', code: 'XX000'),
        operation: 'createOrder',
      );

      expect(failure.code, DomainFailureCode.unknown);
    });
  });

  group('mapSupabaseFailure transport failures', () {
    test('maps a timeout to timeout and is retryable', () {
      final failure = mapSupabaseFailure(
        TimeoutException('timed out'),
        operation: 'listProducts',
      );

      expect(failure.code, DomainFailureCode.timeout);
      expect(failure.retryable, isTrue);
    });

    test('maps a socket failure to unavailable and is retryable', () {
      final failure = mapSupabaseFailure(
        const SocketException('no route to host'),
        operation: 'listProducts',
      );

      expect(failure.code, DomainFailureCode.unavailable);
      expect(failure.retryable, isTrue);
    });
  });

  group('mapSupabaseFailure unknown failures', () {
    test('maps an unrecognized exception to unknown', () {
      final failure = mapSupabaseFailure(
        Exception('boom'),
        operation: 'listProducts',
      );

      expect(failure.code, DomainFailureCode.unknown);
      expect(failure.retryable, isFalse);
    });

    test('passes an existing DomainFailure through unchanged', () {
      const original = DomainFailure(
        code: DomainFailureCode.validation,
        operation: 'createOrder',
        retryable: false,
        message: 'empty cart',
      );

      final failure = mapSupabaseFailure(original, operation: 'other');

      expect(identical(failure, original), isTrue);
      expect(failure.operation, 'createOrder');
    });
  });
}
