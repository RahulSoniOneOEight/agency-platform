import 'package:flutter/material.dart';

enum AgencyButtonVariant { primary, secondary, text }

class AgencyButton extends StatelessWidget {
  const AgencyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AgencyButtonVariant.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final AgencyButtonVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
          );
    return switch (variant) {
      AgencyButtonVariant.primary => FilledButton(onPressed: onPressed, child: child),
      AgencyButtonVariant.secondary => OutlinedButton(onPressed: onPressed, child: child),
      AgencyButtonVariant.text => TextButton(onPressed: onPressed, child: child),
    };
  }
}
