import 'package:flutter/material.dart';
import '../domain/product_models.dart';
import '../domain/quote_card.dart';
import '../primitives/agency_button.dart';
import '../primitives/agency_surface.dart';
import 'pattern_shell.dart';

class RfqPattern extends StatelessWidget {
  const RfqPattern({super.key, required this.products});

  final List<AgencyProduct> products;

  @override
  Widget build(BuildContext context) {
    return AgencyPatternShell(
      title: 'Request a quote',
      subtitle: 'Build a trade request and send it for negotiated pricing.',
      children: [
        ...products.take(4).map(
              (product) => AgencySurface(
                child: Row(
                  children: [
                    Expanded(child: Text(product.name)),
                    Text(product.sku ?? product.id),
                    const SizedBox(width: 12),
                    const Text('Qty 10'),
                  ],
                ),
              ),
            ),
        AgencyButton(label: 'Send RFQ', onPressed: () {}),
        const QuoteCard(quoteId: 'QT-24018', status: 'Draft', total: 48600),
      ],
    );
  }
}
