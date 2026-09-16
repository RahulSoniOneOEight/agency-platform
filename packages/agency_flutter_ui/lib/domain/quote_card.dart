import 'package:flutter/material.dart';
import '../primitives/agency_surface.dart';
import '../themes/agency_theme_tokens.dart';

class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quoteId,
    required this.status,
    required this.total,
    this.onOpen,
  });

  final String quoteId;
  final String status;
  final int total;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return AgencySurface(
      child: Row(
        children: [
          const Icon(Icons.request_quote_outlined),
          SizedBox(width: tokens.controlSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quoteId, style: Theme.of(context).textTheme.titleMedium),
                Text(status),
              ],
            ),
          ),
          Text('₹$total'),
          if (onOpen != null)
            IconButton(onPressed: onOpen, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}
