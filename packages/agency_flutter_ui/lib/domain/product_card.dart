import 'package:flutter/material.dart';
import '../foundation/agency_tokens.dart';
import '../primitives/agency_surface.dart';
import 'price_display.dart';
import 'product_models.dart';

enum ProductCardVariant { standard, b2b, compact }

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.variant = ProductCardVariant.standard,
    this.density = AgencyDensity.balanced,
    this.onTap,
  });

  final AgencyProduct product;
  final ProductCardVariant variant;
  final AgencyDensity density;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final gap = AgencyTokens.gapFor(density);
    final imageHeight = variant == ProductCardVariant.compact ? 92.0 : 132.0;
    return Semantics(
      button: onTap != null,
      label: product.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AgencyTokens.radiusMd),
        child: AgencySurface(
          padding: EdgeInsets.all(gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: imageHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AgencyTokens.radiusSm),
                ),
                child: Icon(Icons.inventory_2_outlined,
                    size: 42, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: gap),
              Text(product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              if (variant == ProductCardVariant.b2b && product.sku != null) ...[
                const SizedBox(height: 4),
                Text(product.sku!, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              PriceDisplay(price: product.price, compact: variant == ProductCardVariant.compact),
              if (variant == ProductCardVariant.b2b && product.stock != null) ...[
                const SizedBox(height: 6),
                Text('${product.stock} in stock', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
