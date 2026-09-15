import 'dart:convert';

import 'package:flutter/services.dart';

import 'prototype_runtime.dart';
import 'runtime_exception.dart';

final RegExp _safeClientId = RegExp(r'^[A-Za-z0-9._-]+$');

/// Loads generated client runtime bundles from the Flutter asset boundary.
///
/// The loader never falls back to a different client. A missing or malformed
/// bundle produces a [RuntimeException] with a stable code so the app can show a
/// governed error screen.
abstract final class RuntimeLoader {
  static String assetPathFor(String clientId) => 'assets/generated/$clientId.json';

  static Future<PrototypeRuntime> loadClient(
    String clientId, {
    AssetBundle? bundle,
  }) async {
    if (!_safeClientId.hasMatch(clientId)) {
      throw RuntimeException(
        code: RuntimeException.clientNotFound,
        message: 'Invalid client id "$clientId".',
        clientId: clientId,
      );
    }

    final assets = bundle ?? rootBundle;
    final path = assetPathFor(clientId);

    final String raw;
    try {
      raw = await assets.loadString(path);
    } catch (_) {
      throw RuntimeException(
        code: RuntimeException.clientNotFound,
        message: 'No generated runtime bundle for client "$clientId".',
        clientId: clientId,
      );
    }

    final dynamic decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException catch (error) {
      throw RuntimeException(
        code: RuntimeException.invalidBundle,
        message: 'Malformed runtime bundle JSON for client "$clientId": ${error.message}',
        clientId: clientId,
      );
    }

    if (decoded is! Map) {
      throw RuntimeException(
        code: RuntimeException.invalidBundle,
        message: 'Runtime bundle for client "$clientId" must be a JSON object.',
        clientId: clientId,
      );
    }

    final PrototypeRuntime runtime;
    try {
      runtime = PrototypeRuntime.fromMap(decoded.cast<String, dynamic>());
    } on FormatException catch (error) {
      throw RuntimeException(
        code: RuntimeException.invalidBundle,
        message: 'Invalid runtime bundle for client "$clientId": ${error.message}',
        clientId: clientId,
      );
    }

    if (runtime.clientId != clientId) {
      throw RuntimeException(
        code: RuntimeException.invalidBundle,
        message:
            'Runtime bundle client id "${runtime.clientId}" does not match requested "$clientId".',
        clientId: clientId,
      );
    }

    return runtime;
  }
}
