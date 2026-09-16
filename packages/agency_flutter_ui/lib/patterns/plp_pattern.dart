import 'package:flutter/material.dart';

import '../domain/product_models.dart';
import '../foundation/agency_tokens.dart';
import '../sections/commerce_sections.dart';
import '../sections/pattern_section.dart';

class PlpPattern extends StatelessWidget {
  const PlpPattern({
    super.key,
    required this.products,
    this.title = 'Products',
    this.density = AgencyDensity.balanced,
    this.b2b = false,
  });

  final List<AgencyProduct> products;
  final String title;
  final AgencyDensity density;
  final bool b2b;

  @override
  Widget build(BuildContext context) {
    return buildPatternComposition(
      plpComposition(
        products: products,
        title: title,
        density: density,
        b2b: b2b,
      ),
    );
  }
}
