import 'package:flutter/material.dart';
import '../foundation/agency_tokens.dart';

class AgencyPatternShell extends StatelessWidget {
  const AgencyPatternShell({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.density = AgencyDensity.balanced,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final AgencyDensity density;

  @override
  Widget build(BuildContext context) {
    final gap = AgencyTokens.gapFor(density);
    return ListView(
      padding: EdgeInsets.all(gap),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        SizedBox(height: gap),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) SizedBox(height: gap),
        ],
      ],
    );
  }
}
