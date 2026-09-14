import 'package:flutter/material.dart';
import '../domain/cart_item_card.dart';
import '../domain/product_models.dart';
import '../primitives/agency_button.dart';
import 'pattern_shell.dart';

class CartPattern extends StatelessWidget {
  const CartPattern({super.key, required this.products, this.tradeMode = false});

  final List<AgencyProduct> products;
  final bool tradeMode;

  @override
  Widget build(BuildContext context) {
    final total = products.fold<int>(0, (sum, item) => sum + item.price.current);
    return AgencyPatternShell(
      title: tradeMode ? 'Order basket' : 'Cart',
      children: [
        ...products.map((product) => CartItemCard(product: product)),
        Row(
          children: [
            Expanded(child: Text('Total', style: Theme.of(context).textTheme.titleMedium)),
            Text('₹$total', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        AgencyButton(label: tradeMode ? 'Continue order' : 'Checkout', onPressed: () {}),
      ],
    );
  }
}
