import 'package:flutter/material.dart';
import '../domain/product_card.dart';
import '../domain/product_models.dart';
import '../foundation/agency_tokens.dart';
import '../themes/agency_theme_tokens.dart';
import 'pattern_shell.dart';

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
    final tokens = AgencyThemeTokens.of(context);
    return AgencyPatternShell(
      title: title,
      subtitle: subtitle,
      density: density,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisExtent: 270,
            crossAxisSpacing: tokens.tileGap,
            mainAxisSpacing: tokens.tileGap,
          ),
          itemBuilder: (context, index) => ProductCard(
            product: products[index],
            density: density,
          ),
        ),
      ],
    );
  }
}
