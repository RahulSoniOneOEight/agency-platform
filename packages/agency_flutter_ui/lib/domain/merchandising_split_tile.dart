import 'package:flutter/material.dart';
import '../foundation/agency_tokens.dart';
import 'price_display.dart';
import 'product_models.dart';

class MerchandisingSplitTile extends StatelessWidget {
  const MerchandisingSplitTile({
    super.key,
    required this.title,
    required this.left,
    required this.right,
  });

  final String title;
  final AgencyProduct left;
  final AgencyProduct right;

  Widget _slot(BuildContext context, AgencyProduct product) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AgencyTokens.spaceMd),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AgencyTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            PriceDisplay(price: product.price, compact: true),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(children: [_slot(context, left), const SizedBox(width: 12), _slot(context, right)]),
      ],
    );
  }
}
