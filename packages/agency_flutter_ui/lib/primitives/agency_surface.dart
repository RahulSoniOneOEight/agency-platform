import 'package:flutter/material.dart';
import '../themes/agency_theme_tokens.dart';

class AgencySurface extends StatelessWidget {
  const AgencySurface({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding =
        padding ?? EdgeInsets.all(AgencyThemeTokens.of(context).cardSpacing);
    return Card(
      child: Padding(padding: resolvedPadding, child: child),
    );
  }
}
