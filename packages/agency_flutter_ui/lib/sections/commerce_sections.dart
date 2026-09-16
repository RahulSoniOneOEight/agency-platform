import 'package:flutter/material.dart';

import '../domain/price_display.dart';
import '../domain/product_card.dart';
import '../domain/product_models.dart';
import '../foundation/agency_tokens.dart';
import '../primitives/agency_button.dart';
import '../primitives/agency_chip.dart';
import '../primitives/agency_search_field.dart';
import '../themes/agency_theme_tokens.dart';
import 'pattern_section.dart';

/// Governed, reusable section bodies for the commerce patterns.
///
/// These widgets are the single implementation of each pattern's composition
/// slot. The prototype patterns and the review mixed preview both compose the
/// same widgets, so Review Mode never duplicates a screen implementation.

/// Product grid used by the home and product-listing patterns.
class ProductGridSection extends StatelessWidget {
  const ProductGridSection({
    super.key,
    required this.products,
    this.density = AgencyDensity.balanced,
    this.variant = ProductCardVariant.standard,
    this.mainAxisExtent = 270,
  });

  final List<AgencyProduct> products;
  final AgencyDensity density;
  final ProductCardVariant variant;
  final double mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: tokens.tileGap,
        mainAxisSpacing: tokens.tileGap,
      ),
      itemBuilder: (context, index) => ProductCard(
        product: products[index],
        variant: variant,
        density: density,
      ),
    );
  }
}

/// Filter chip strip used by the product-listing pattern.
class FilterChipStripSection extends StatelessWidget {
  const FilterChipStripSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      children: [
        AgencyChip(label: 'In stock'),
        AgencyChip(label: 'Popular'),
        AgencyChip(label: 'Price'),
      ],
    );
  }
}

/// Compact product row used by the search pattern.
class CompactProductRowSection extends StatelessWidget {
  const CompactProductRowSection({super.key, required this.products});

  final List<AgencyProduct> products;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return Wrap(
      spacing: tokens.tileGap,
      runSpacing: tokens.tileGap,
      children: products
          .take(6)
          .map((product) => SizedBox(
                width: 220,
                child: ProductCard(product: product, variant: ProductCardVariant.compact),
              ))
          .toList(),
    );
  }
}

/// Search field used by the search pattern.
class SearchFieldSection extends StatelessWidget {
  const SearchFieldSection({super.key, this.hintText = 'Search products'});

  final String hintText;

  @override
  Widget build(BuildContext context) {
    return AgencySearchField(hintText: hintText);
  }
}

/// Product image placeholder used by the product-detail pattern.
class ProductImageSection extends StatelessWidget {
  const ProductImageSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      child: const Center(child: Icon(Icons.inventory_2_outlined, size: 72)),
    );
  }
}

/// Price block used by the product-detail pattern.
class PriceSection extends StatelessWidget {
  const PriceSection({super.key, required this.product});

  final AgencyProduct product;

  @override
  Widget build(BuildContext context) {
    return PriceDisplay(price: product.price);
  }
}

/// Primary/secondary actions used by the product-detail pattern.
class PdpActionsSection extends StatelessWidget {
  const PdpActionsSection({super.key, this.tradeMode = false});

  final bool tradeMode;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return Wrap(
      spacing: tokens.tileGap,
      runSpacing: tokens.inlineSpacing,
      children: [
        AgencyButton(
          label: tradeMode ? 'Add to order' : 'Add to cart',
          onPressed: () {},
        ),
        if (tradeMode)
          AgencyButton(
            label: 'Request quote',
            variant: AgencyButtonVariant.secondary,
            onPressed: () {},
          ),
      ],
    );
  }
}

/// Home pattern composition (`commerce.home`).
PatternComposition homeComposition({
  required List<AgencyProduct> products,
  required String title,
  String? subtitle,
  AgencyDensity density = AgencyDensity.balanced,
}) {
  return PatternComposition(
    title: title,
    subtitle: subtitle,
    density: density,
    sections: [
      PatternSection(
        id: 'home.product-grid',
        child: ProductGridSection(products: products, density: density),
      ),
    ],
  );
}

/// Product-listing pattern composition (`commerce.plp`).
PatternComposition plpComposition({
  required List<AgencyProduct> products,
  required String title,
  AgencyDensity density = AgencyDensity.balanced,
  bool b2b = false,
}) {
  return PatternComposition(
    title: title,
    density: density,
    sections: [
      const PatternSection(
        id: 'plp.filter-strip',
        child: FilterChipStripSection(),
      ),
      PatternSection(
        id: 'plp.product-grid',
        child: ProductGridSection(
          products: products,
          density: density,
          variant: b2b ? ProductCardVariant.b2b : ProductCardVariant.standard,
          mainAxisExtent: 290,
        ),
      ),
    ],
  );
}

/// Search pattern composition (`commerce.search`).
PatternComposition searchComposition({
  required List<AgencyProduct> products,
  String hintText = 'Search products',
}) {
  return PatternComposition(
    title: 'Search',
    density: AgencyDensity.balanced,
    sections: [
      PatternSection(
        id: 'search.search-field',
        child: SearchFieldSection(hintText: hintText),
      ),
      PatternSection(
        id: 'search.results-grid',
        child: CompactProductRowSection(products: products),
      ),
    ],
  );
}

/// Product-detail pattern composition (`commerce.pdp`).
PatternComposition pdpComposition({
  required AgencyProduct product,
  bool tradeMode = false,
}) {
  return PatternComposition(
    title: product.name,
    subtitle: tradeMode && product.sku != null ? product.sku : product.subtitle,
    density: AgencyDensity.balanced,
    sections: [
      const PatternSection(id: 'pdp.product-image', child: ProductImageSection()),
      PatternSection(id: 'pdp.price', child: PriceSection(product: product)),
      if (product.rating != null)
        PatternSection(
          id: 'pdp.rating',
          child: Text('★ ${product.rating!.toStringAsFixed(1)}'),
        ),
      if (tradeMode && product.stock != null)
        PatternSection(
          id: 'pdp.stock',
          child: Text('${product.stock} units available'),
        ),
      PatternSection(id: 'pdp.actions', child: PdpActionsSection(tradeMode: tradeMode)),
    ],
  );
}
