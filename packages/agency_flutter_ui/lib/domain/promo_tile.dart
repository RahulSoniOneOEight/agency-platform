import 'package:flutter/material.dart';
import '../themes/agency_theme_tokens.dart';

class PromoTile extends StatelessWidget {
  const PromoTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.local_offer_outlined,
    this.onTap,
  });

  final String title;
  final String subtitle;
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
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
        child: Row(
          children: [
            Icon(icon, size: 36),
            SizedBox(width: tokens.tileGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
