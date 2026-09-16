import 'package:flutter/material.dart';
import '../themes/agency_theme_tokens.dart';

class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.label, this.icon = Icons.category_outlined, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      child: Container(
        padding: EdgeInsets.all(tokens.cardSpacing),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            SizedBox(height: tokens.tileGap),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
