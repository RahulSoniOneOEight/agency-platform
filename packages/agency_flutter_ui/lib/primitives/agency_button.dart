import 'package:flutter/material.dart';
import '../themes/agency_theme_tokens.dart';

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
    final tokens = AgencyThemeTokens.of(context);
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.controlRadius),
    );
    ButtonStyle styleFor(Size minimumSize) => ButtonStyle(
          minimumSize: WidgetStatePropertyAll(minimumSize),
          shape: WidgetStatePropertyAll(shape),
        );
    // Filled/primary keeps the full-width behavior established by
    // filledButtonTheme; secondary and text controls size to their content so
    // they stay intrinsic inside Wrap layouts.
    final filledStyle = styleFor(Size.fromHeight(tokens.controlHeight));
    final intrinsicStyle = styleFor(Size(0, tokens.controlHeight));
    return switch (variant) {
      AgencyButtonVariant.primary =>
        FilledButton(onPressed: onPressed, style: filledStyle, child: child),
      AgencyButtonVariant.secondary =>
        OutlinedButton(onPressed: onPressed, style: intrinsicStyle, child: child),
      AgencyButtonVariant.text =>
        TextButton(onPressed: onPressed, style: intrinsicStyle, child: child),
    };
  }
}
