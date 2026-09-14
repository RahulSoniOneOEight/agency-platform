import 'package:flutter/material.dart';
import '../domain/product_card.dart';
import '../domain/product_models.dart';
import '../primitives/agency_search_field.dart';
import 'pattern_shell.dart';

class SearchPattern extends StatelessWidget {
  const SearchPattern({super.key, required this.products, this.hintText = 'Search products'});

  final List<AgencyProduct> products;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return AgencyPatternShell(
      title: 'Search',
      children: [
        AgencySearchField(hintText: hintText),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: products
              .take(6)
              .map((p) => SizedBox(width: 220, child: ProductCard(product: p, variant: ProductCardVariant.compact)))
              .toList(),
        ),
      ],
    );
  }
}
