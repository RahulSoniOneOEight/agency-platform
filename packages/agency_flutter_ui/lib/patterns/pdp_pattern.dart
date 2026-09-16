import 'package:flutter/material.dart';

import '../domain/product_models.dart';
import '../sections/commerce_sections.dart';
import '../sections/pattern_section.dart';

class PdpPattern extends StatelessWidget {
  const PdpPattern({super.key, required this.product, this.tradeMode = false});

  final AgencyProduct product;
  final bool tradeMode;

  @override
  Widget build(BuildContext context) {
    return buildPatternComposition(
      pdpComposition(product: product, tradeMode: tradeMode),
    );
  }
}
