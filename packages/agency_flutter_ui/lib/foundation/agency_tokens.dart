import 'package:flutter/animation.dart';

enum AgencyDensity { airy, balanced, dense }

abstract final class AgencyTokens {
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  static const double radiusSm = 8;
  static const double radiusMd = 14;
  static const double radiusLg = 22;

  static const Duration motionFast = Duration(milliseconds: 140);
  static const Duration motionNormal = Duration(milliseconds: 240);
  static const Curve motionCurve = Curves.easeOutCubic;

  static double gapFor(AgencyDensity density) => switch (density) {
        AgencyDensity.airy => spaceLg,
        AgencyDensity.balanced => spaceMd,
        AgencyDensity.dense => spaceSm,
      };
}
