import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Apple Music's signature red.
const kAccent = Color(0xFFFA2D48);

/// Semantic colours (iOS system palette) for the current brightness.
class Palette {
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color label;
  final Color secondaryLabel;
  final Color separator;

  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.label,
    required this.secondaryLabel,
    required this.separator,
  });

  static const dark = Palette(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceHigh: Color(0xFF2C2C2E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    separator: Color(0x54545458),
  );

  static const light = Palette(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F2F7),
    surfaceHigh: Color(0xFFE5E5EA),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x993C3C43),
    separator: Color(0x4A3C3C43),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

extension PaletteContext on BuildContext {
  Palette get pal => Palette.of(this);
}

ThemeData buildTheme(Brightness brightness) {
  final pal = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: pal.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kAccent,
      brightness: brightness,
    ).copyWith(primary: kAccent, surface: pal.background),
    textTheme: base.textTheme
        .apply(bodyColor: pal.label, displayColor: pal.label),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: pal.separator,
    appBarTheme: AppBarTheme(
      backgroundColor: pal.background,
      foregroundColor: pal.label,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: kAccent,
      scaffoldBackgroundColor: pal.background,
    ),
  );
}

/// Shared text styles. System font (SF Pro on iOS) throughout.
class Type {
  static TextStyle largeTitle(Palette p) => TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: p.label);
  static TextStyle title(Palette p) =>
      TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.label);
  static TextStyle row(Palette p) =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: p.label);
  static TextStyle sub(Palette p) =>
      TextStyle(fontSize: 14, color: p.secondaryLabel);
  static TextStyle caption(Palette p) =>
      TextStyle(fontSize: 12, color: p.secondaryLabel);
}
