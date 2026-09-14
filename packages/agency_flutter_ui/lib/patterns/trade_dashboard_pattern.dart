import 'package:flutter/material.dart';
import '../domain/credit_summary.dart';
import '../domain/quote_card.dart';
import '../primitives/agency_button.dart';
import 'pattern_shell.dart';

class TradeDashboardPattern extends StatelessWidget {
  const TradeDashboardPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return AgencyPatternShell(
      title: 'Trade dashboard',
      subtitle: 'Orders, quotes and credit in one place.',
      children: [
        const CreditSummary(limit: 250000, used: 92000),
        const QuoteCard(quoteId: 'QT-24017', status: 'Awaiting approval', total: 78600),
        const QuoteCard(quoteId: 'QT-24012', status: 'Approved', total: 42500),
        Wrap(
          spacing: 12,
          children: [
            AgencyButton(label: 'Quick order', onPressed: () {}),
            AgencyButton(
              label: 'New RFQ',
              variant: AgencyButtonVariant.secondary,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}
