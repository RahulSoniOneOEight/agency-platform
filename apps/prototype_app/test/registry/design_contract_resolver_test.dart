import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/registry/design_contract_resolver.dart';

void main() {
  group('DesignContractResolver patterns', () {
    test('resolves canonical pattern ids explicitly', () {
      expect(DesignContractResolver.patternKey('commerce.home'), 'home');
      expect(DesignContractResolver.patternKey('commerce.search'), 'search');
      expect(DesignContractResolver.patternKey('commerce.plp'), 'plp');
      expect(DesignContractResolver.patternKey('commerce.pdp'), 'pdp');
      expect(DesignContractResolver.patternKey('commerce.cart'), 'cart');
      expect(DesignContractResolver.patternKey('commerce.rfq'), 'rfq');
      expect(DesignContractResolver.patternKey('commerce.reorder'), 'reorder');
      expect(
        DesignContractResolver.patternKey('commerce.trade-dashboard'),
        'trade-dashboard',
      );
    });

    test('unknown canonical pattern ids are rejected', () {
      expect(
        () => DesignContractResolver.patternKey('commerce.missing'),
        throwsArgumentError,
      );
      expect(() => DesignContractResolver.patternKey('cart'), throwsArgumentError);
    });

    test('component ids are not resolvable as patterns', () {
      expect(
        () => DesignContractResolver.patternKey('commerce.product-card'),
        throwsArgumentError,
      );
    });
  });

  group('DesignContractResolver components', () {
    test('resolves canonical component bindings', () {
      final binding = DesignContractResolver.component('commerce.product-card');

      expect(binding.kind, 'component');
      expect(binding.registryKey, 'product-card');
      expect(binding.symbol, 'ProductCard');
    });

    test('unknown canonical component ids are rejected', () {
      expect(
        () => DesignContractResolver.component('commerce.missing'),
        throwsArgumentError,
      );
    });

    test('pattern ids are not resolvable as components', () {
      expect(
        () => DesignContractResolver.component('commerce.cart'),
        throwsArgumentError,
      );
    });
  });

  group('DesignContractResolver variants', () {
    test('resolves supported component variants', () {
      expect(
        DesignContractResolver.componentVariant('commerce.product-card', 'standard'),
        'standard',
      );
      expect(
        DesignContractResolver.componentVariant('commerce.product-card', 'b2b'),
        'b2b',
      );
    });

    test('unsupported variants are rejected', () {
      expect(
        () => DesignContractResolver.componentVariant('commerce.product-card', 'not-real'),
        throwsArgumentError,
      );
      expect(
        () => DesignContractResolver.componentVariant('commerce.product-card', 'premium'),
        throwsArgumentError,
      );
    });
  });

  group('DesignContractResolver density', () {
    test('resolves every canonical density for product-card', () {
      expect(DesignContractResolver.density('commerce.product-card', 'compact'), 'dense');
      expect(DesignContractResolver.density('commerce.product-card', 'normal'), 'balanced');
      expect(DesignContractResolver.density('commerce.product-card', 'spacious'), 'airy');
    });

    test('resolves declared densities for current components', () {
      expect(DesignContractResolver.density('commerce.price-display', 'compact'), 'dense');
      expect(DesignContractResolver.density('commerce.price-display', 'normal'), 'balanced');
      expect(DesignContractResolver.density('commerce.search-field', 'compact'), 'dense');
      expect(DesignContractResolver.density('commerce.quote-card', 'normal'), 'balanced');
      expect(DesignContractResolver.density('commerce.credit-summary', 'normal'), 'balanced');
    });

    test('unsupported densities are rejected', () {
      expect(
        () => DesignContractResolver.density('commerce.product-card', 'not-real'),
        throwsArgumentError,
      );
      expect(
        () => DesignContractResolver.density('commerce.price-display', 'spacious'),
        throwsArgumentError,
      );
    });
  });
}
