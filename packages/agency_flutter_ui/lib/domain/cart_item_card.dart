import 'package:flutter/material.dart';
import '../primitives/agency_surface.dart';
import 'price_display.dart';
import 'product_models.dart';

class CartItemCard extends StatelessWidget {
  const CartItemCard({super.key, required this.product, this.quantity = 1});

  final AgencyProduct product;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return AgencySurface(
      child: Row(
        children: [
          const SizedBox(width: 56, height: 56, child: Icon(Icons.shopping_bag_outlined)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: Theme.of(context).textTheme.titleSmall),
                Text('Qty $quantity'),
              ],
            ),
          ),
          PriceDisplay(price: product.price, compact: true),
        ],
      ),
    );
  }
}
