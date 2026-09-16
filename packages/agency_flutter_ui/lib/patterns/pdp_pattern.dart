import 'package:flutter/material.dart';
import '../domain/price_display.dart';
import '../domain/product_models.dart';
import '../primitives/agency_button.dart';
import '../themes/agency_theme_tokens.dart';
import 'pattern_shell.dart';

class PdpPattern extends StatelessWidget {
  const PdpPattern({super.key, required this.product, this.tradeMode = false});

  final AgencyProduct product;
  final bool tradeMode;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return AgencyPatternShell(
      title: product.name,
      subtitle: tradeMode && product.sku != null ? product.sku : product.subtitle,
      children: [
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
          ),
          child: const Center(child: Icon(Icons.inventory_2_outlined, size: 72)),
        ),
        PriceDisplay(price: product.price),
        if (product.rating != null) Text('★ ${product.rating!.toStringAsFixed(1)}'),
        if (tradeMode && product.stock != null) Text('${product.stock} units available'),
        Wrap(
          spacing: tokens.tileGap,
          runSpacing: tokens.inlineSpacing,
          children: [
            AgencyButton(label: tradeMode ? 'Add to order' : 'Add to cart', onPressed: () {}),
            if (tradeMode)
              AgencyButton(
                label: 'Request quote',
                variant: AgencyButtonVariant.secondary,
                onPressed: () {},
              ),
          ],
        ),
      ],
    );
  }
}
