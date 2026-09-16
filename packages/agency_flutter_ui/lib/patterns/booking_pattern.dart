import 'package:flutter/material.dart';
import '../primitives/agency_button.dart';
import '../primitives/agency_surface.dart';
import '../themes/agency_theme_tokens.dart';
import 'pattern_shell.dart';

class BookingPattern extends StatelessWidget {
  const BookingPattern({super.key, required this.services});

  final List<String> services;

  @override
  Widget build(BuildContext context) {
    final tokens = AgencyThemeTokens.of(context);
    return AgencyPatternShell(
      title: 'Book a service',
      subtitle: 'Choose a service, slot and location.',
      children: [
        ...services.map(
          (service) => AgencySurface(
            child: Row(
              children: [
                const Icon(Icons.event_available_outlined),
                SizedBox(width: tokens.controlSpacing),
                Expanded(child: Text(service)),
                AgencyButton(
                  label: 'Choose',
                  variant: AgencyButtonVariant.secondary,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
