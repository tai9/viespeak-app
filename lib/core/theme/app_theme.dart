import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// ElevenLabs-inspired design system
// Near-white canvas, warm undertones, whisper-thin display type,
// multi-layer sub-0.1 opacity shadows, pill buttons.
// ---------------------------------------------------------------------------

// --- Colors ----------------------------------------------------------------

class AppColors {
  AppColors._();

  // Primary
  static const white = Color(0xFFFFFFFF);
  static const lightGray = Color(0xFFF5F5F5);
  static const warmStone = Color(0xFFF5F2EF);
  static const black = Color(0xFF000000);

  // Neutral
  static const darkGray = Color(0xFF4E4E4E);
  static const warmGray = Color(0xFF777169);
  static const nearWhite = Color(0xFFF6F6F6);

  // Interactive
  static const borderLight = Color(0xFFE5E5E5);
  static const borderSubtle = Color(0x0D000000); // rgba(0,0,0,0.05)

  // Warm stone at 80% opacity (signature)
  static const warmStoneSurface = Color(0xCCF5F2EF);
}

// --- Shadows ---------------------------------------------------------------

class AppShadows {
  AppShadows._();

  // Level 0.5 — inset edge (simulated with outer shadow in Flutter)
  static const insetEdge = [
    BoxShadow(
      color: Color(0x13000000), // rgba(0,0,0,0.075)
      blurRadius: 0,
      spreadRadius: 0.5,
    ),
  ];

  // Level 1 — outline ring (shadow-as-border for cards)
  static const outlineRing = [
    BoxShadow(
      color: Color(0x0F000000), // rgba(0,0,0,0.06)
      blurRadius: 0,
      spreadRadius: 1,
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  // Level 2 — card / button elevation
  static const card = [
    BoxShadow(
      color: Color(0x66000000), // rgba(0,0,0,0.4)
      blurRadius: 1,
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      blurRadius: 4,
      offset: Offset(0, 4),
    ),
  ];

  // Level 3 — warm lift (featured CTA)
  static const warmLift = [
    BoxShadow(
      color: Color(0x0A4E3217), // rgba(78,50,23,0.04)
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  // Edge shadow — subtle edge definition
  static const edge = [
    BoxShadow(
      color: Color(0x14000000), // rgba(0,0,0,0.08)
      blurRadius: 0,
      spreadRadius: 0.5,
    ),
  ];
}

// --- Border Radius ---------------------------------------------------------

class AppRadius {
  AppRadius._();

  static const subtle = 4.0;
  static const standard = 8.0;
  static const comfortable = 12.0;
  static const card = 16.0;
  static const large = 20.0;
  static const section = 24.0;
  static const warmButton = 30.0;
  static const pill = 9999.0;
}

// --- Typography ------------------------------------------------------------

// Waldenburg is not available on Google Fonts. We use DM Sans weight 300
// as the display substitute — similarly geometric, clean, and elegant at
// light weights. Swap for Waldenburg when custom fonts are bundled.

TextStyle _display(double size, {double? height, double? letterSpacing}) {
  return GoogleFonts.dmSans(
    fontSize: size,
    fontWeight: FontWeight.w300,
    height: height,
    letterSpacing: letterSpacing,
    color: AppColors.black,
  );
}

TextStyle _body(double size, {FontWeight? weight, double? height, double? letterSpacing}) {
  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight ?? FontWeight.w400,
    height: height,
    letterSpacing: letterSpacing,
    color: AppColors.black,
  );
}

class AppTypography {
  AppTypography._();

  // Display — light weight, tight line-height
  static final displayHero = _display(48, height: 1.08, letterSpacing: -0.96);
  static final sectionHeading = _display(36, height: 1.17);
  static final cardHeading = _display(32, height: 1.13);

  // Body — Inter with positive letter-spacing
  static final bodyLarge = _body(20, height: 1.35);
  static final body = _body(18, height: 1.50, letterSpacing: 0.18);
  static final bodyStandard = _body(16, height: 1.50, letterSpacing: 0.16);
  static final bodyMedium = _body(16, weight: FontWeight.w500, height: 1.50, letterSpacing: 0.16);

  // UI
  static final nav = _body(15, weight: FontWeight.w500, height: 1.40, letterSpacing: 0.15);
  static final button = _body(15, weight: FontWeight.w500, height: 1.47);
  static final caption = _body(14, height: 1.43, letterSpacing: 0.14);
  static final small = _body(13, weight: FontWeight.w500, height: 1.38);
  static final micro = _body(12, weight: FontWeight.w500, height: 1.33);

  // Bold uppercase CTA (WaldenburgFH substitute)
  static final buttonUppercase = GoogleFonts.dmSans(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.10,
    letterSpacing: 0.7,
    color: AppColors.black,
  );
}

// --- Theme -----------------------------------------------------------------

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.white,
    colorScheme: const ColorScheme.light(
      primary: AppColors.black,
      onPrimary: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.black,
      secondary: AppColors.warmStone,
      onSecondary: AppColors.black,
      outline: AppColors.borderLight,
    ),
    textTheme: TextTheme(
      displayLarge: AppTypography.displayHero,
      displayMedium: AppTypography.sectionHeading,
      displaySmall: AppTypography.cardHeading,
      headlineLarge: AppTypography.sectionHeading,
      headlineMedium: AppTypography.cardHeading,
      headlineSmall: _display(24, height: 1.20),
      titleLarge: AppTypography.bodyLarge,
      titleMedium: AppTypography.bodyMedium,
      titleSmall: AppTypography.nav,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.bodyStandard,
      bodySmall: AppTypography.caption,
      labelLarge: AppTypography.button,
      labelMedium: AppTypography.small,
      labelSmall: AppTypography.micro,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: AppTypography.nav.copyWith(color: AppColors.black),
    ),
    cardTheme: CardThemeData(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.comfortable),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSubtle,
      thickness: 1,
    ),
  );
}
