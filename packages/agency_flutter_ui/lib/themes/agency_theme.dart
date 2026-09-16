import 'dart:convert';

import 'package:flutter/material.dart';

import 'agency_theme_tokens.dart';
import 'generated_agency_default_theme.dart';

/// The explicit agency default resolved theme.
///
/// This is the design-contract compiler's agency default theme, generated into
/// `generated_agency_default_theme.dart` and freshness-checked in CI. It is
/// **not** a seed fallback: it exists only for tooling surfaces (Widgetbook) and
/// the prototype app's loading/error shell. Valid B.1E runtime bundles must
/// always supply their own resolved theme.
abstract final class AgencyThemeDefaults {
  static final AgencyResolvedTheme resolved = AgencyResolvedTheme.fromJson(
    jsonDecode(agencyDefaultResolvedThemeJson) as Map<String, Object?>,
  );
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
        errorBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: colors['error']!),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: colors['error']!, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: colors['border']!),
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
