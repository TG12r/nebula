import 'package:flutter/material.dart';

class AppTheme {
  static const Color nebulaPurple = Color(0xFF8A2BE2);
  static const Color cmfBlack = Color(0xFF000000);
  static const Color cmfDarkGrey = Color(0xFF1A1A1A);
  static const Color cmfLightGrey = Color(0xFFE0E0E0);
  static const Color cmfWhite = Color(0xFFFFFFFF);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: nebulaPurple,
        onPrimary: cmfWhite,
        surface: cmfLightGrey,
        onSurface: cmfBlack,
      ),
      scaffoldBackgroundColor: cmfWhite,
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(Colors.black),
      inputDecorationTheme: _buildInputTheme(Colors.black),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: nebulaPurple,
        onPrimary: cmfWhite,
        surface: cmfDarkGrey,
        onSurface: cmfWhite,
      ),
      scaffoldBackgroundColor: cmfBlack,
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(Colors.white),
      inputDecorationTheme: _buildInputTheme(Colors.white),
    );
  }

  static TextTheme _buildTextTheme(Color color) {
    return TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.bold,
        letterSpacing: -1.0,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.bold,
        color: color,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.w600,
        color: color,
      ),

      bodyLarge: TextStyle(color: color, fontWeight: FontWeight.normal),
      bodyMedium: TextStyle(color: color, fontWeight: FontWeight.normal),

      labelLarge: TextStyle(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: color,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.bold,
        color: color,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Courier New',
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: color,
      ),
    );
  }

  static InputDecorationTheme _buildInputTheme(Color color) {
    return InputDecorationTheme(
      filled: true,
      fillColor: color.withOpacity(0.05),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: color.withOpacity(0.2)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: nebulaPurple, width: 2.0),
      ),
      labelStyle: TextStyle(
        fontFamily: 'Courier New',
        color: color.withOpacity(0.6),
        fontSize: 12,
      ),
      floatingLabelStyle: const TextStyle(
        color: nebulaPurple,
        fontFamily: 'Courier New',
        fontWeight: FontWeight.bold,
      ),
      hintStyle: TextStyle(
        fontFamily: 'Courier New',
        color: color.withOpacity(0.4),
      ),
    );
  }
}
