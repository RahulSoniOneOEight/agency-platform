import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import '../direction/prototype_direction.dart';
import '../fixtures/demo_repository.dart';

abstract final class PrototypeRegistry {
  static Widget buildPattern(String id, PrototypeDirection direction) {
    PatternRegistry.resolve(id);
    final trade = direction.isTrade;
    return switch (id) {
      'home' => HomePattern(
          products: DemoRepository.products,
          title: direction.name,
          subtitle: direction.strategicGoal,
          density: direction.density,
        ),
      'search' => SearchPattern(products: DemoRepository.products),
      'plp' => PlpPattern(
          products: DemoRepository.products,
          title: trade ? 'Trade catalogue' : 'Products',
          density: direction.density,
          b2b: trade,
        ),
      'pdp' => PdpPattern(product: DemoRepository.products.first, tradeMode: trade),
      'cart' => CartPattern(products: DemoRepository.products.take(3).toList(), tradeMode: trade),
      'rfq' => RfqPattern(products: DemoRepository.products),
      'trade-dashboard' => const TradeDashboardPattern(),
      'booking' => const BookingPattern(services: DemoRepository.services),
      'quick-order' => SearchPattern(products: DemoRepository.products, hintText: 'Enter SKU or product'),
      'reorder' => const TradeDashboardPattern(),
      'checkout' => CartPattern(products: DemoRepository.products.take(2).toList(), tradeMode: trade),
      _ => throw ArgumentError.value(id, 'id', 'Unsupported prototype pattern'),
    };
  }
}
