import 'dart:convert';

import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter/services.dart';

/// Loads the validated, client-safe environment config from the app assets.
///
/// The assets are byte-for-byte copies of the canonical files under
/// `client-projects/reference-commerce/production/config/`, kept in sync by
/// `tooling.production.sync_app_config`. There is deliberately no fallback: a
/// missing, malformed, unsupported, or mismatched asset fails deterministically
/// with a [FormatException] so the runtime can never silently boot a different
/// environment.
abstract final class EnvironmentConfigLoader {
  static const Set<String> supportedEnvironments = {
    'dev',
    'staging',
    'production',
  };

  static String assetPathFor(String environment) =>
      'assets/config/$environment.json';

  static Future<EnvironmentConfig> load(
    String environment, {
    AssetBundle? bundle,
  }) async {
    final normalized = environment.trim().toLowerCase();
    if (!supportedEnvironments.contains(normalized)) {
      throw FormatException('Unsupported environment: $environment');
    }

    final path = assetPathFor(normalized);
    final assets = bundle ?? rootBundle;

    final String raw;
    try {
      raw = await assets.loadString(path);
    } catch (_) {
      throw FormatException('Missing environment config asset: $path');
    }

    final dynamic decoded = json.decode(raw);
    if (decoded is! Map) {
      throw FormatException('Environment config $path must be a JSON object');
    }

    final config = EnvironmentConfig.fromJson(
      Map<String, Object?>.from(decoded),
    );
    if (config.environment.name != normalized) {
      throw FormatException(
        'Environment config $path declares '
        '"${config.environment.name}", expected "$normalized"',
      );
    }
    return config;
  }
}
