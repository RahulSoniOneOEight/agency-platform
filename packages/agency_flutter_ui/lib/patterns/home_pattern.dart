import 'package:flutter/material.dart';

import '../domain/product_models.dart';
import '../foundation/agency_tokens.dart';
import '../sections/commerce_sections.dart';
import '../sections/pattern_section.dart';

class HomePattern extends StatelessWidget {
  const HomePattern({
    super.key,
    required this.products,
    this.title = 'Explore',
    this.subtitle,
    this.density = AgencyDensity.balanced,
  });

  final List<AgencyProduct> products;
  final String title;
  final String? subtitle;
  final AgencyDensity density;

  @override
  Widget build(BuildContext context) {
    return buildPatternComposition(
      homeComposition(
        products: products,
        title: title,
        subtitle: subtitle,
        density: density,
      ),
    );
  }
}
