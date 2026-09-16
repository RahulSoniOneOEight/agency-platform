import 'package:flutter/material.dart';
import '../themes/agency_theme_tokens.dart';
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

  Widget _slot(BuildContext context, AgencyProduct product, AgencyThemeTokens tokens) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(tokens.cardSpacing),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(tokens.controlRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            SizedBox(height: tokens.tileGap),
            PriceDisplay(price: product.price, compact: true),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: tokens.tileGap),
        Row(children: [
          _slot(context, left, tokens),
          SizedBox(width: tokens.tileGap),
          _slot(context, right, tokens),
        ]),
      ],
    );
  }
}
