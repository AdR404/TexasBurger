import 'package:flutter/material.dart';

/// Paleta de Texas Burger: ámbar y crema con acentos vino y azul.
class AppTheme {
  // ---------------------------------------------------------------------------
  // Colores base de la marca (los del logo)
  // ---------------------------------------------------------------------------
  static const Color alabamaCrimson = Color(0xFFA91314);
  static const Color intenseFire = Color(0xFFFFB607);
  static const Color bananaMania = Color(0xFFFCECCB);
  static const Color lapisLazuli = Color(0xFF236092);
  static const Color navyBlue = lapisLazuli;
  static const Color navyBlueLight = Color(0xFF3477A8);
  static const Color burgundy = Color(0xFF5B0008);
  static const Color gold = intenseFire;
  static const Color goldLight = Color(0xFFFFF3D1);
  static const Color texasYellow = intenseFire;
  static const Color creamBg = bananaMania;
  static const Color cardBg = Colors.white;
  static const Color textDark = burgundy;
  static const Color textMuted = Color(0xFF6A7280);
  static const Color borderLight = Color(0xFFE8D8B5);
  static const Color successGreen = Color(0xFF10B981);
  static const Color infoBlue = lapisLazuli;

  // ---------------------------------------------------------------------------
  // Roles de color: usa estos nombres en las pantallas, no el color directo.
  // ---------------------------------------------------------------------------

  /// Acciones generales, elementos seleccionados, totales e íconos.
  static const Color primary = navyBlue;

  /// Fondo suave del color principal (círculos de ícono, chips, filas).
  static const Color primarySoft = Color(0xFFE5F0F7);

  /// Promociones y descuentos. Es el único uso de rojo "de contenido".
  static const Color promo = alabamaCrimson;
  static const Color promoSoft = Color(0xFFFBE8E7);

  /// Eliminar, gastos, diferencias negativas y errores.
  static const Color danger = alabamaCrimson;
  static const Color dangerSoft = Color(0xFFFBE8E7);

  /// Marca: logo y eslogan.
  static const Color brand = alabamaCrimson;

  /// Fondos suaves de apoyo (confirmaciones, información y destacados).
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color infoSoft = Color(0xFFDDEFFB);
  static const Color goldSoft = Color(0xFFFFE6A3);
  static const Color goldDark = Color(0xFF7A4B00);

  // ---------------------------------------------------------------------------
  // Nombres anteriores. Siguen existiendo para no romper ramas ya empezadas,
  // pero ya no deben usarse: el analizador avisará.
  // ---------------------------------------------------------------------------
  @Deprecated('Usa AppTheme.primary, promo, danger o brand según el caso.')
  static const Color primaryRed = Color(0xFFD31A24);
  @Deprecated('Usa AppTheme.promo, danger o brand según el caso.')
  static const Color darkRed = Color(0xFFA8121B);
  @Deprecated('Usa AppTheme.primarySoft, promoSoft o dangerSoft según el caso.')
  static const Color lightRed = Color(0xFFFFECEE);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: creamBg,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: navyBlueLight,
        onSecondary: Colors.white,
        tertiary: gold,
        onTertiary: Colors.black,
        surface: cardBg,
        onSurface: textDark,
        error: danger,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: texasYellow,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: textDark,
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
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderLight),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: burgundy,
        indicatorColor: primary,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: goldLight, fontWeight: FontWeight.w700),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      dividerTheme: const DividerThemeData(
        color: borderLight,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
