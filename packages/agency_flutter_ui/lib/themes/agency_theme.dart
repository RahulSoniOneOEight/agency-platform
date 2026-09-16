import 'package:flutter/material.dart';

import 'agency_theme_tokens.dart';

/// The explicit agency default resolved theme.
///
/// This mirrors the agency foundation + semantic token defaults resolved by the
/// design-contract compiler. It is **not** a seed fallback: it exists only for
/// tooling surfaces (Widgetbook) and the prototype app's loading/error shell.
/// Valid B.1E runtime bundles must always supply their own resolved theme.
abstract final class AgencyThemeDefaults {
  static const Map<String, Object?> _resolvedJson = <String, Object?>{
    'version': 1,
    'color': <String, Object?>{
      'primary': '#2454FF',
      'on_primary': '#FFFFFF',
      'secondary': '#EF8A23',
      'on_secondary': '#FFFFFF',
      'surface': '#FFFFFF',
      'surface_muted': '#F7F8FA',
      'text_primary': '#16181D',
      'text_secondary': '#626874',
      'border': '#E4E6EB',
      'error': '#D32F2F',
      'on_error': '#FFFFFF',
    },
    'typography': <String, Object?>{
      'font_family': 'Inter',
      'font_fallback': 'Roboto',
      'display': 40,
      'headline': 32,
      'title': 22,
      'body': 15,
      'label': 13,
      'line_height_body': 1.5,
      'weight_regular': 400,
      'weight_emphasis': 700,
      'heading_emphasis': 'normal',
    },
    'spacing': <String, Object?>{
      'inline': 8,
      'control': 12,
      'card': 16,
      'tile': 12,
      'section': 32,
    },
    'radius': <String, Object?>{'control': 12, 'card': 20},
    'elevation': <String, Object?>{'card': 1, 'overlay': 4},
    'size': <String, Object?>{
      'control_height': 44,
      'control_height_compact': 36,
      'icon': 20,
    },
    'density': <String, Object?>{'default': 'normal'},
    'motion': <String, Object?>{
      'fast_ms': 150,
      'normal_ms': 250,
      'slow_ms': 400,
      'easing': 'ease-out',
    },
    'breakpoints': <String, Object?>{'mobile': 0, 'tablet': 768, 'desktop': 1200},
  };

  static final AgencyResolvedTheme resolved =
      AgencyResolvedTheme.fromJson(_resolvedJson);
}

/// Builds Material 3 [ThemeData] from a resolved agency theme.
abstract final class AgencyTheme {
  /// The explicit agency default resolved theme (never a seed fallback).
  static AgencyResolvedTheme get defaultResolved => AgencyThemeDefaults.resolved;

  /// Theme for tooling surfaces and the loading/error shell.
  static ThemeData lightDefault() => light(AgencyThemeDefaults.resolved);

  /// Theme built strictly from resolved semantic values.
  static ThemeData light(AgencyResolvedTheme theme) {
    final colors = theme.colors;
    final typography = theme.typography;
    final headingWeight = _fontWeight(
      typography.hasStrongHeadings
          ? typography.weightEmphasis
          : typography.weightRegular,
    );
    final regularWeight = _fontWeight(typography.weightRegular);

    TextStyle text(double size, FontWeight weight, {double? height}) => TextStyle(
          fontFamily: typography.fontFallback,
          fontSize: size,
          fontWeight: weight,
          height: height,
        );

    final textTheme = TextTheme(
      displayLarge: text(typography.display, headingWeight),
      displayMedium: text(typography.display, headingWeight),
      displaySmall: text(typography.display, headingWeight),
      headlineLarge: text(typography.headline, headingWeight),
      headlineMedium: text(typography.headline, headingWeight),
      headlineSmall: text(typography.headline, headingWeight),
      titleLarge: text(typography.title, headingWeight),
      titleMedium: text(typography.title, headingWeight),
      titleSmall: text(typography.title, headingWeight),
      bodyLarge: text(typography.body, regularWeight, height: typography.lineHeightBody),
      bodyMedium: text(typography.body, regularWeight, height: typography.lineHeightBody),
      bodySmall: text(typography.body, regularWeight, height: typography.lineHeightBody),
      labelLarge: text(typography.label, regularWeight, height: typography.lineHeightBody),
      labelMedium: text(typography.label, regularWeight, height: typography.lineHeightBody),
      labelSmall: text(typography.label, regularWeight, height: typography.lineHeightBody),
    );

    final scheme = ColorScheme.fromSeed(seedColor: colors['primary']!).copyWith(
      primary: colors['primary'],
      onPrimary: colors['on_primary'],
      secondary: colors['secondary'],
      onSecondary: colors['on_secondary'],
      surface: colors['surface'],
      onSurface: colors['text_primary'],
      onSurfaceVariant: colors['text_secondary'],
      outline: colors['border'],
      error: colors['error'],
      onError: colors['on_error'],
    );

    final controlRadius = BorderRadius.circular(theme.radius['control']!);
    final cardRadius = BorderRadius.circular(theme.radius['card']!);
    final controlHeight = theme.size['control_height']!;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: typography.fontFallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: colors['surface'],
      cardTheme: CardThemeData(
        elevation: theme.elevation['card'],
        margin: EdgeInsets.zero,
        color: colors['surface'],
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors['surface_muted'],
        border: OutlineInputBorder(borderRadius: controlRadius),
        enabledBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: colors['border']!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: colors['primary']!, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: Size.fromHeight(controlHeight),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(controlHeight),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        AgencyThemeTokens.fromResolved(theme),
      ],
    );
  }
}

FontWeight _fontWeight(int weight) {
  final index = (weight ~/ 100) - 1;
  return FontWeight.values[index.clamp(0, FontWeight.values.length - 1).toInt()];
}
