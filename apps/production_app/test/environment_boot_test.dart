import 'dart:convert';
import 'dart:io';

import 'package:agency_integration_adapters/agency_integration_adapters.dart';
import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_app/app/production_composition_root.dart';

/// Tests run on the VM from `apps/production_app`, so the committed reference
/// configs are reachable relative to the package root.
const String _configDir =
    '../../client-projects/reference-commerce/production/config';

EnvironmentConfig _loadReferenceConfig(String environment) {
  final raw = File('$_configDir/$environment.json').readAsStringSync();
  return EnvironmentConfig.fromJson(
    Map<String, Object?>.from(json.decode(raw) as Map),
  );
}

void main() {
  group('reference environment config parsing', () {
    test('dev config parses and boots deterministic boundaries', () async {
      final config = _loadReferenceConfig('dev');
      expect(config.environment, ProductionEnvironment.dev);
      expect(config.analyticsEnabled, isFalse);

      final runtime = ProductionCompositionRoot.referenceCommerce(config);
      expect(runtime.environment, ProductionEnvironment.dev);
      expect(runtime.isSupabaseBacked, isFalse);

      final catalog = await runtime.commerce.loadCatalog();
      expect(catalog, isNotEmpty);
      expect(
        catalog.first.variants.first.available,
        isNotNull,
        reason: 'inventory is composed from the deterministic boundary',
      );
    });

    test('dev boot exposes deterministic fake integration adapters', () {
      final runtime = ProductionCompositionRoot.referenceCommerce(
        _loadReferenceConfig('dev'),
      );
      expect(runtime.payment, isA<FakePaymentAdapter>());
      expect(runtime.shipping, isA<FakeShippingAdapter>());
      expect(runtime.erp, isA<FakeErpAdapter>());
      expect(runtime.crm, isA<FakeCrmAdapter>());
      expect(runtime.whatsapp, isA<FakeWhatsAppAdapter>());
    });

    test('staging config parses and composes Supabase adapters', () {
      final config = _loadReferenceConfig('staging');
      expect(config.environment, ProductionEnvironment.staging);
      expect(config.analyticsEnabled, isTrue);

      final runtime = ProductionCompositionRoot.referenceCommerce(config);
      expect(runtime.isSupabaseBacked, isTrue);
    });

    test('production config parses and composes Supabase adapters', () {
      final config = _loadReferenceConfig('production');
      expect(config.environment, ProductionEnvironment.production);

      final runtime = ProductionCompositionRoot.referenceCommerce(config);
      expect(runtime.isSupabaseBacked, isTrue);
    });

    test(
      'staging without client-safe supabase config falls back to deterministic',
      () {
        final config = EnvironmentConfig(
          environment: ProductionEnvironment.staging,
          apiBaseUrl: 'https://api.staging.agency-platform.example',
        );
        final runtime = ProductionCompositionRoot.referenceCommerce(config);
        expect(runtime.isSupabaseBacked, isFalse);
      },
    );
  });

  group('deterministic commerce boundaries', () {
    test('order placement is idempotent per key', () async {
      final runtime = ProductionCompositionRoot.referenceCommerce(
        _loadReferenceConfig('dev'),
      );
      final key = IdempotencyKey('order-submission-1');

      final first = await runtime.orders.placeOrder(
        cartId: 'cart-consumer',
        idempotencyKey: key,
      );
      final second = await runtime.orders.placeOrder(
        cartId: 'cart-consumer',
        idempotencyKey: key,
      );

      expect(second.id, first.id);
    });

    test('B2B membership and credit resolve deterministically', () async {
      final runtime = ProductionCompositionRoot.referenceCommerce(
        _loadReferenceConfig('dev'),
      );
      final identity = await runtime.auth.signIn(
        email: 'buyer@reference-commerce.example',
        password: 'reference-password',
      );
      expect(identity.role, UserRole.b2bBuyer);

      final context = await runtime.quotes.loadAccountContext(
        accountId: 'account-trade',
        identityId: identity.id,
      );
      expect(context.membership.role, UserRole.b2bBuyer);
      expect(context.credit?.availableCreditMinor, 750000);
    });
  });

  group('malformed environment config', () {
    test('missing environment is rejected', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'api_base_url': 'https://api.example.test',
        }),
        throwsFormatException,
      );
    });

    test('unknown environment name is rejected', () {
      expect(
        () => EnvironmentConfig.fromJson({
          'environment': 'prod',
          'api_base_url': 'https://api.example.test',
        }),
        throwsFormatException,
      );
    });

    test('missing api_base_url is rejected', () {
      expect(
        () => EnvironmentConfig.fromJson({'environment': 'dev'}),
        throwsFormatException,
      );
    });

    test('privileged keys are rejected', () {
      for (final fragment in const [
        'service_role',
        'secret',
        'private_key',
        'webhook_secret',
        'erp_password',
        'payment_secret',
        'whatsapp_token',
      ]) {
        expect(
          () => EnvironmentConfig.fromJson({
            'environment': 'production',
            'api_base_url': 'https://api.example.test',
            fragment: true,
          }),
          throwsFormatException,
          reason: 'fragment $fragment must be rejected',
        );
      }
    });
  });
}
