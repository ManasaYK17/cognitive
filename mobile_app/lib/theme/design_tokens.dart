import 'package:flutter/material.dart';

class DesignTokens {
  // Radii
  static const double patientCardRadius = 26.0;
  static const double caregiverCardRadius = 12.0;

  // Colors (semantic roles)
  static const Color accent = Color(0xFF6C63FF);
  static const Color success = Color(0xFF2ECC71);
  static const Color warning = Color(0xFFFFB84D);
  static const Color info = Color(0xFF4DB6FF);

  // Neutral surfaces
  static const Color lightSurface = Color(0xFFF7F7F9);
  static const Color surface = Color(0xFFF0F0F3);
  static const Color pageBackground = Color(0xFFEDEDED);

  // Text
  static const Color textPrimary = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF555555);
  static const Color textMuted = Color(0xFF888888);

  // Border
  static const Color subtleBorder = Color(0xFFDDDDDF);

  static ThemeData lightTheme() {
    final base = ThemeData.light();
    const TextStyle displayStyle = TextStyle(fontSize: 20, color: textPrimary, fontWeight: FontWeight.w700);
    const TextStyle bodyStyle = TextStyle(fontSize: 16, color: textPrimary);
    const TextStyle secondaryStyle = TextStyle(fontSize: 14, color: textSecondary);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: accent),
      scaffoldBackgroundColor: pageBackground,
      textTheme: const TextTheme(
        titleLarge: displayStyle,
        titleMedium: secondaryStyle,
        bodyLarge: bodyStyle,
        bodyMedium: secondaryStyle,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: displayStyle.copyWith(fontSize: 18, color: textPrimary),
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(patientCardRadius), side: const BorderSide(width: 0.5, color: subtleBorder)),
        margin: const EdgeInsets.all(12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  static ThemeData darkTheme() {
    final base = ThemeData.dark();
    const TextStyle displayStyle = TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w700);
    const TextStyle bodyStyle = TextStyle(fontSize: 16, color: Colors.white);
    const TextStyle secondaryStyle = TextStyle(fontSize: 14, color: Colors.white70);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: accent),
      scaffoldBackgroundColor: const Color(0xFF121212),
      textTheme: const TextTheme(
        titleLarge: displayStyle,
        titleMedium: secondaryStyle,
        bodyLarge: bodyStyle,
        bodyMedium: secondaryStyle,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: displayStyle.copyWith(fontSize: 18, color: Colors.white),
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1B1B1B),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(patientCardRadius), side: const BorderSide(width: 0.5, color: Color(0xFF2A2A2A))),
        margin: const EdgeInsets.all(12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }
}
