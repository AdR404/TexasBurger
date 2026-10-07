import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryRed = Color(0xFFD31A24);
  static const Color darkRed = Color(0xFFA8121B);
  static const Color lightRed = Color(0xFFFFECEE);
  
  static const Color navyBlue = Color(0xFF0F2643);
  static const Color navyBlueLight = Color(0xFF1E3A5F);
  
  static const Color gold = Color(0xFFF5A623);
  static const Color goldLight = Color(0xFFFFF7E6);
  static const Color texasYellow = Color(0xFFFFD43B);
  
  static const Color creamBg = Color(0xFFFBF3DE);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF181B1F);
  static const Color textMuted = Color(0xFF6A7280);
  static const Color borderLight = Color(0xFFEDE4CC);
  static const Color successGreen = Color(0xFF10B981);
  static const Color infoBlue = Color(0xFF2563EB);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: creamBg,
      colorScheme: const ColorScheme.light(
        primary: primaryRed,
        onPrimary: Colors.white,
        secondary: navyBlue,
        onSecondary: Colors.white,
        tertiary: gold,
        onTertiary: Colors.black,
        surface: cardBg,
        onSurface: textDark,
        error: Color(0xFFDC2626),
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: texasYellow,
        foregroundColor: navyBlue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: navyBlue,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderLight, width: 0.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navyBlue,
          side: const BorderSide(color: navyBlue, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primaryRed,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderLight),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderLight,
        thickness: 1,
        space: 1,
      ),
    );
  }
}