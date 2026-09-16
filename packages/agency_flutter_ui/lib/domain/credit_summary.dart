import 'package:flutter/material.dart';
import '../primitives/agency_surface.dart';
import '../themes/agency_theme_tokens.dart';

class CreditSummary extends StatelessWidget {
  const CreditSummary({super.key, required this.limit, required this.used});

  final int limit;
  final int used;

  String _format(int value) {
    final text = value.toString();
    if (text.length <= 3) return text;
    final head = text.substring(0, text.length - 3);
    final tail = text.substring(text.length - 3);
    return '$head,$tail';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    final available = (limit - used).clamp(0, limit);
    return AgencySurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trade credit', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: tokens.inlineSpacing),
          Text('₹${_format(available)} available',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: tokens.inlineSpacing),
          Text('₹${_format(used)} used of ₹${_format(limit)}'),
          SizedBox(height: tokens.tileGap),
          LinearProgressIndicator(value: limit == 0 ? 0 : used / limit),
        ],
      ),
    );
  }
}
