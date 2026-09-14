import 'package:flutter/material.dart';
import '../foundation/agency_tokens.dart';

class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.label, this.icon = Icons.category_outlined, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AgencyTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AgencyTokens.spaceMd),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AgencyTokens.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center)],
        ),
      ),
    );
  }
}
