import 'package:flutter/material.dart';
import 'product_models.dart';

class PriceDisplay extends StatelessWidget {
  const PriceDisplay({super.key, required this.price, this.compact = false});

  final AgencyPrice price;
  final bool compact;

  String _format(int value) {
    final text = value.toString();
    if (text.length <= 3) return text;
    final head = text.substring(0, text.length - 3);
    final tail = text.substring(text.length - 3);
    return '$head,$tail';
  }

  @override
  Widget build(BuildContext context) {
    final style = compact
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text('₹${_format(price.current)}', style: style),
        if (price.compareAt != null && price.compareAt! > price.current)
          Text(
            '₹${_format(price.compareAt!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}
