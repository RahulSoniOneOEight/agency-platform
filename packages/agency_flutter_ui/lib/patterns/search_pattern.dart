import 'package:flutter/material.dart';

import '../domain/product_models.dart';
import '../sections/commerce_sections.dart';
import '../sections/pattern_section.dart';

class SearchPattern extends StatelessWidget {
  const SearchPattern({super.key, required this.products, this.hintText = 'Search products'});

  final List<AgencyProduct> products;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return buildPatternComposition(
      searchComposition(products: products, hintText: hintText),
    );
  }
}
