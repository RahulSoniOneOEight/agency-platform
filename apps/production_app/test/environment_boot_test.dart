import 'dart:convert';

import 'package:agency_integration_adapters/agency_integration_adapters.dart';
import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_app/app/environment_config_loader.dart';
import 'package:production_app/app/production_composition_root.dart';

/// Deterministic asset bundle used to inject malformed config bytes without
/// touching the declared assets.
class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.values);

  final Map<String, String> values;

  @override
  Future<ByteData> load(String key) async {
    final value = values[key];
    if (value == null) {
      throw Exception('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('declared environment config assets', () {
    for (final environment in const ['dev', 'staging', 'production']) {
      test('$environment asset parses through the asset bundle', () async {
        final config = await EnvironmentConfigLoader.load(environment);
        expect(config.environment.name, environment);
      });
    }

    test('dev asset is client-safe and deterministic', () async {
      final config = await EnvironmentConfigLoader.load('dev');
      expect(config.analyticsEnabled, isFalse);
      expect(
        config.integrationModes.values.every((mode) => mode == 'fake'),
        isTrue,
      );
    });
  });

  group('reference environment composition', () {
    test('dev boots deterministic boundaries', () async {
      final config = await EnvironmentConfigLoader.load('dev');
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

    test('dev boot exposes deterministic fake integration adapters', () async {
      final runtime = ProductionCompositionRoot.referenceCommerce(
        await EnvironmentConfigLoader.load('dev'),
      );
      expect(runtime.payment, isA<FakePaymentAdapter>());
      expect(runtime.shipping, isA<FakeShippingAdapter>());
      expect(runtime.erp, isA<FakeErpAdapter>());
      expect(runtime.crm, isA<FakeCrmAdapter>());
      expect(runtime.whatsapp, isA<FakeWhatsAppAdapter>());
    });

    test('staging composes Supabase adapters', () async {
      final config = await EnvironmentConfigLoader.load('staging');
      expect(config.environment, ProductionEnvironment.staging);
      final runtime = ProductionCompositionRoot.referenceCommerce(config);
      expect(runtime.isSupabaseBacked, isTrue);
    });

    test('production composes Supabase adapters', () async {
      final config = await EnvironmentConfigLoader.load('production');
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
        await EnvironmentConfigLoader.load('dev'),
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
        await EnvironmentConfigLoader.load('dev'),
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
    test('malformed asset bytes fail deterministically', () async {
      final bundle = _FakeAssetBundle({
        'assets/config/dev.json': '{ not json',
      });
      await expectLater(
        EnvironmentConfigLoader.load('dev', bundle: bundle),
        throwsFormatException,
      );
    });

    test('missing asset fails deterministically', () async {
      await expectLater(
        EnvironmentConfigLoader.load('dev', bundle: _FakeAssetBundle({})),
        throwsFormatException,
      );
    });

    test('unsupported environment fails deterministically', () async {
      await expectLater(
        EnvironmentConfigLoader.load('prod'),
        throwsFormatException,
      );
    });

    test('environment/asset mismatch fails deterministically', () async {
      final bundle = _FakeAssetBundle({
        'assets/config/dev.json': json.encode({
          'environment': 'staging',
          'api_base_url': 'https://api.example.test',
        }),
      });
      await expectLater(
        EnvironmentConfigLoader.load('dev', bundle: bundle),
        throwsFormatException,
      );
    });

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
