import 'package:flutter/material.dart';
import '../foundation/agency_tokens.dart';

class AgencySurface extends StatelessWidget {
  const AgencySurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AgencyTokens.spaceMd),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: padding, child: child),
    );
  }
}
