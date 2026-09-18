import 'dart:async';

import 'package:agency_production_core/agency_production_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Normalizes any error raised by the Supabase client into a provider-neutral
/// [DomainFailure].
///
/// No raw Supabase (or transport) exception may leave an adapter's public
/// method; every adapter wraps its provider calls with this mapper. Auth
/// failures become [DomainFailureCode.unauthorized] or
/// [DomainFailureCode.forbidden]; PostgREST conflicts become
/// [DomainFailureCode.conflict]; timeouts and transport failures become
/// [DomainFailureCode.timeout] / [DomainFailureCode.unavailable]; anything
/// unrecognized becomes [DomainFailureCode.unknown].
DomainFailure mapSupabaseFailure(
  Object error, {
  required String operation,
}) {
  if (error is DomainFailure) {
    return error;
  }
  if (error is TimeoutException) {
    return _failure(
      DomainFailureCode.timeout,
      operation: operation,
      retryable: true,
      message: error.message ?? 'Request timed out',
    );
  }
  if (error is AuthRetryableFetchException) {
    return _failure(
      DomainFailureCode.unavailable,
      operation: operation,
      retryable: true,
      message: error.message,
    );
  }
  if (error is AuthException) {
    return _failure(
      int.tryParse(error.statusCode ?? '') == 403
          ? DomainFailureCode.forbidden
          : DomainFailureCode.unauthorized,
      operation: operation,
      retryable: false,
      message: error.message,
    );
  }
  if (error is PostgrestException) {
    return _fromPostgrest(error, operation);
  }
  if (_isTransportFailure(error)) {
    return _failure(
      DomainFailureCode.unavailable,
      operation: operation,
      retryable: true,
      message: error.toString(),
    );
  }
  return _failure(
    DomainFailureCode.unknown,
    operation: operation,
    retryable: false,
    message: error.toString(),
  );
}

DomainFailure _fromPostgrest(PostgrestException error, String operation) {
  final message = error.message;
  if (message.toLowerCase().contains('jwt')) {
    return _failure(
      DomainFailureCode.unauthorized,
      operation: operation,
      retryable: false,
      message: message,
    );
  }
  final code = switch (error.code) {
    '23505' || '23503' || '23504' || '40001' || '40P01' =>
      DomainFailureCode.conflict,
    '23514' || '23502' || '22P02' || '22003' => DomainFailureCode.validation,
    '42501' => DomainFailureCode.forbidden,
    'PGRST301' => DomainFailureCode.unauthorized,
    _ => DomainFailureCode.unknown,
  };
  return _failure(
    code,
    operation: operation,
    retryable: false,
    message: message,
  );
}

const Set<String> _transportTypes = {
  'SocketException',
  'ClientException',
  'HttpException',
  'HandshakeException',
  'RequestAbortedException',
  'WebSocketChannelException',
};

bool _isTransportFailure(Object error) =>
    _transportTypes.contains(error.runtimeType.toString());

DomainFailure _failure(
  DomainFailureCode code, {
  required String operation,
  required bool retryable,
  required String message,
}) =>
    DomainFailure(
      code: code,
      operation: operation,
      retryable: retryable,
      message: message,
    );
