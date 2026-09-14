import 'package:flutter/material.dart';

abstract final class AgencyTheme {
  static ThemeData light({Color? seedColor}) {
    final seed = seedColor ?? const Color(0xFF6750A4);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      scaffoldBackgroundColor: const Color(0xFFF9F9FB),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
