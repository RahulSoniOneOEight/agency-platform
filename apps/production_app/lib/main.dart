import 'dart:convert';

import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter/material.dart';

import 'app/production_app.dart';
import 'app/production_composition_root.dart';

/// Compile-time, client-safe configuration.
///
/// Deployment passes the selected environment file as JSON, e.g.
/// `--dart-define=REFERENCE_COMMERCE_CONFIG=$(cat .../dev.json)`. When absent
/// (local runs, `flutter build web`) the app boots on a deterministic dev
/// configuration. No privileged value is ever embedded here.
const String _configJson = String.fromEnvironment('REFERENCE_COMMERCE_CONFIG');

EnvironmentConfig bootstrapConfig() {
  if (_configJson.trim().isNotEmpty) {
    final decoded = json.decode(_configJson);
    if (decoded is! Map) {
      throw const FormatException(
        'REFERENCE_COMMERCE_CONFIG must be a JSON object',
      );
    }
    return EnvironmentConfig.fromJson(Map<String, Object?>.from(decoded));
  }
  return EnvironmentConfig(
    environment: ProductionEnvironment.dev,
    apiBaseUrl: 'https://api.dev.agency-platform.example',
    analyticsEnabled: false,
    featureFlags: const {'b2b_rfq': true, 'whatsapp_notifications': false},
    integrationModes: const {
      'payment': 'fake',
      'shipping': 'fake',
      'erp': 'fake',
      'crm': 'fake',
      'whatsapp': 'fake',
    },
    appVersion: '0.1.0',
  );
}

void main() {
  final config = bootstrapConfig();
  runApp(
    ProductionApp(runtime: ProductionCompositionRoot.referenceCommerce(config)),
  );
}
