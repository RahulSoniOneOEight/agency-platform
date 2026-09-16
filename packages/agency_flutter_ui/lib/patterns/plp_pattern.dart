import 'package:flutter/material.dart';
import '../domain/product_card.dart';
import '../domain/product_models.dart';
import '../foundation/agency_tokens.dart';
import '../themes/agency_theme_tokens.dart';
import '../primitives/agency_chip.dart';
import 'pattern_shell.dart';

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
    final tokens = AgencyThemeTokens.of(context);
    return AgencyPatternShell(
      title: title,
      density: density,
      children: [
        const Wrap(spacing: 8, children: [
          AgencyChip(label: 'In stock'),
          AgencyChip(label: 'Popular'),
          AgencyChip(label: 'Price'),
        ]),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisExtent: 290,
            crossAxisSpacing: tokens.tileGap,
            mainAxisSpacing: tokens.tileGap,
          ),
          itemBuilder: (context, index) => ProductCard(
            product: products[index],
            variant: b2b ? ProductCardVariant.b2b : ProductCardVariant.standard,
            density: density,
          ),
        ),
      ],
    );
  }
}
