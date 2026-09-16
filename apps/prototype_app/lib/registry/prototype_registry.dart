import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import '../direction/prototype_direction.dart';
import '../fixtures/fixture_repository.dart';
import 'design_contract_resolver.dart';

abstract final class PrototypeRegistry {
  static String labelFor(String canonicalPatternId) =>
      PatternRegistry.resolve(DesignContractResolver.patternKey(canonicalPatternId)).label;

  /// The governed section composition for [canonicalPatternId] under
  /// [direction], or `null` when the pattern is not composed from sections.
  ///
  /// This mirrors the parameters [buildPattern] passes to the pattern widgets;
  /// the review mixed preview composes the same sections so the base screen and
  /// any mixed preview share one implementation.
  static PatternComposition? compositionFor(
    String canonicalPatternId,
    PrototypeDirection direction,
    FixtureRepository fixtures,
  ) {
    final id = DesignContractResolver.patternKey(canonicalPatternId);
    final products = fixtures.products;
    final trade = direction.isTrade;
    return switch (id) {
      'home' => homeComposition(
          products: products,
          title: direction.name,
          subtitle: direction.strategicGoal,
          density: direction.density,
        ),
      'search' => searchComposition(products: products),
      'plp' => plpComposition(
          products: products,
          title: trade ? 'Trade catalogue' : 'Products',
          density: direction.density,
          b2b: trade,
        ),
      'pdp' => products.isEmpty
          ? null
          : pdpComposition(product: products.first, tradeMode: trade),
      _ => null,
    };
  }

  static Widget buildPattern(
    String canonicalPatternId,
    PrototypeDirection direction,
    FixtureRepository fixtures,
  ) {
    final id = DesignContractResolver.patternKey(canonicalPatternId);
    final products = fixtures.products;
    final trade = direction.isTrade;
    return switch (id) {
      'home' => HomePattern(
          products: products,
          title: direction.name,
          subtitle: direction.strategicGoal,
          density: direction.density,
        ),
      'search' => SearchPattern(products: products),
      'plp' => PlpPattern(
          products: products,
          title: trade ? 'Trade catalogue' : 'Products',
          density: direction.density,
          b2b: trade,
        ),
      'pdp' => products.isEmpty
          ? const Center(child: Text('No products available for this client fixture pack.'))
          : PdpPattern(product: products.first, tradeMode: trade),
      'cart' => CartPattern(products: products.take(3).toList(), tradeMode: trade),
      'rfq' => RfqPattern(products: products),
      'trade-dashboard' => const TradeDashboardPattern(),
      'reorder' => const TradeDashboardPattern(),
      _ => throw ArgumentError.value(
          canonicalPatternId,
          'canonicalPatternId',
          'Unsupported prototype pattern',
        ),
    };
  }
}
