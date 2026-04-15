import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Sonic Editorial color palette ─────────────────────────────────────────────
const kPrimary               = Color(0xFFFFB4A8); // salmon
const kPrimaryContainer      = Color(0xFFFF5540); // coral-red
const kOnPrimary             = Color(0xFF690100);
const kOnPrimaryContainer    = Color(0xFF5C0000);

const kSecondaryContainer    = Color(0xFF970100);
const kOnSecondary           = Color(0xFF690100);

const kTertiary              = Color(0xFFACC7FF);
const kTertiaryContainer     = Color(0xFF488FFF);

const kSurface               = Color(0xFF131313);
const kSurfaceVariant        = Color(0xFF353535);
const kSurfaceContainer      = Color(0xFF1F1F1F);
const kSurfaceContainerLow   = Color(0xFF1B1B1B);
const kSurfaceContainerHigh  = Color(0xFF2A2A2A);
const kSurfaceContainerHighest = Color(0xFF353535);
const kSurfaceContainerLowest  = Color(0xFF0E0E0E);

const kOnSurface             = Color(0xFFE2E2E2);
const kOnSurfaceVariant      = Color(0xFFEBBBB4);
const kOutline               = Color(0xFFB18780);
const kOutlineVariant        = Color(0xFF603E39);

// ── Text styles ───────────────────────────────────────────────────────────────

TextStyle headline(double size, {FontWeight weight = FontWeight.w800, Color? color}) =>
    GoogleFonts.epilogue(
      fontSize: size,
      fontWeight: weight,
      color: color ?? kOnSurface,
      letterSpacing: size > 24 ? -1.0 : -0.5,
      height: 1.0,
    );

TextStyle body(double size, {FontWeight weight = FontWeight.w500, Color? color}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color ?? kOnSurface,
    );

TextStyle label(double size, {Color? color}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: color ?? kOnSurfaceVariant,
      letterSpacing: 1.5,
    );

// ── Theme ─────────────────────────────────────────────────────────────────────

final oyeTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kSurface,
  colorScheme: const ColorScheme.dark(
    primary: kPrimary,
    onPrimary: kOnPrimary,
    primaryContainer: kPrimaryContainer,
    onPrimaryContainer: kOnPrimaryContainer,
    secondary: kPrimary,
    tertiary: kTertiary,
    surface: kSurface,
    onSurface: kOnSurface,
    surfaceContainerHighest: kSurfaceContainerHighest,
    outline: kOutline,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: kSurface,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: GoogleFonts.epilogue(
      color: kOnSurface,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    iconTheme: const IconThemeData(color: kOnSurface),
  ),
  textTheme: TextTheme(
    displayLarge:  headline(57),
    displayMedium: headline(45),
    displaySmall:  headline(36),
    headlineLarge: headline(32),
    headlineMedium: headline(28),
    headlineSmall: headline(24),
    titleLarge:    body(22, weight: FontWeight.w700),
    titleMedium:   body(16, weight: FontWeight.w700),
    titleSmall:    body(14, weight: FontWeight.w700),
    bodyLarge:     body(16),
    bodyMedium:    body(14),
    bodySmall:     body(12, color: kOnSurfaceVariant),
    labelLarge:    label(14),
    labelMedium:   label(12),
    labelSmall:    label(10),
  ),
  sliderTheme: const SliderThemeData(
    activeTrackColor: kPrimary,
    inactiveTrackColor: kSurfaceContainerHighest,
    thumbColor: kOnSurface,
    overlayColor: Color(0x29FFB4A8),
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
    trackHeight: 3,
  ),
  iconTheme: const IconThemeData(color: kOnSurface),
  useMaterial3: true,
);

// ── Shared decorations ────────────────────────────────────────────────────────

BoxDecoration glassDecoration({double radius = 12}) => BoxDecoration(
  color: kSurfaceVariant.withValues(alpha: 0.6),
  borderRadius: BorderRadius.circular(radius),
);

LinearGradient get primaryGradient => const LinearGradient(
  colors: [kPrimary, kPrimaryContainer],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
