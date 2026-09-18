import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvironmentConfig', () {
    test('rejects privileged keys', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'environment': 'production',
          'api_base_url': 'https://api.example.test',
          'supabase_url': 'https://project.supabase.co',
          'supabase_anon_key': 'public-safe-key',
          'service_role_key': 'must-not-be-here',
        }),
        throwsFormatException,
      );
    });

    test('rejects every named privileged key', () {
      const privilegedKeys = <String>[
        'service_role_key',
        'payment_secret',
        'webhook_secret',
        'whatsapp_token',
        'erp_password',
        'private_key',
      ];

      for (final privilegedKey in privilegedKeys) {
        expect(
          () => EnvironmentConfig.fromJson({
            'environment': 'production',
            'api_base_url': 'https://api.example.test',
            privilegedKey: 'must-not-be-here',
          }),
          throwsFormatException,
          reason: 'expected "$privilegedKey" to be rejected',
        );
      }
    });

    test('rejects unknown keys outside the allowlist', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'environment': 'dev',
          'api_base_url': 'https://api.dev.example.test',
          'unexpected_key': 'value',
        }),
        throwsFormatException,
      );
    });

    test('exposes exactly dev, staging and production', () {
      expect(
        ProductionEnvironment.values.map((env) => env.name).toList(),
        <String>['dev', 'staging', 'production'],
      );
    });

    test('parses a valid production config', () {
      final config = EnvironmentConfig.fromJson({
        'environment': 'production',
        'api_base_url': 'https://api.example.test',
        'supabase_url': 'https://project.supabase.co',
        'supabase_anon_key': 'public-safe-key',
        'analytics_enabled': true,
        'feature_flags': {'checkout_v2': true},
        'integration_modes': {'payment': 'fake'},
        'app_version': '1.2.3',
      });

      expect(config.environment, ProductionEnvironment.production);
      expect(config.apiBaseUrl, 'https://api.example.test');
      expect(config.supabaseUrl, 'https://project.supabase.co');
      expect(config.supabaseAnonKey, 'public-safe-key');
      expect(config.analyticsEnabled, isTrue);
      expect(config.featureFlags, {'checkout_v2': true});
      expect(config.integrationModes, {'payment': 'fake'});
      expect(config.appVersion, '1.2.3');
    });

    test('rejects an unsupported environment value', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'environment': 'qa',
          'api_base_url': 'https://api.example.test',
        }),
        throwsFormatException,
      );
    });

    test('rejects a missing environment value', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'api_base_url': 'https://api.example.test',
        }),
        throwsFormatException,
      );
    });

    test('rejects a missing api_base_url', () {
      expect(
        () => EnvironmentConfig.fromJson({'environment': 'dev'}),
        throwsFormatException,
      );
    });

    test('rejects a wrongly typed optional value', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'environment': 'dev',
          'api_base_url': 'https://api.dev.example.test',
          'analytics_enabled': 'yes',
        }),
        throwsFormatException,
      );
    });

    test('keeps feature flags and integration modes immutable', () {
      final config = EnvironmentConfig.fromJson({
        'environment': 'dev',
        'api_base_url': 'https://api.dev.example.test',
        'feature_flags': {'checkout_v2': true},
        'integration_modes': {'payment': 'fake'},
      });

      expect(
        () => config.featureFlags['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => config.integrationModes['payment'] = 'live',
        throwsUnsupportedError,
      );
    });
  });
}
