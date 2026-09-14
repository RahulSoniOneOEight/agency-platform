import 'package:flutter/material.dart';
import '../foundation/agency_tokens.dart';

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AgencyTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AgencyTokens.spaceLg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AgencyTokens.radiusLg),
        ),
        child: Row(
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 16),
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
