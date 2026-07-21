import 'package:flutter/material.dart';

/// Enpix Design System — raw iOS-inspired color palettes (light + dark).
///
/// These are the CONSTANT color values only. Widgets must NOT reference
/// them directly — use `context.colors` (see [AppColorScheme] and
/// `context_ext.dart`) so colors adapt to the active brightness.
class AppColors {
  AppColors._();

  // ── Brand (light variants) ──
  static const Color brandBlue = Color(0xFF007AFF);
  static const Color brandPurple = Color(0xFFAF52DE);
  static const Color brandGreen = Color(0xFF34C759);
  static const Color brandOrange = Color(0xFFFF9500);
  static const Color brandRed = Color(0xFFFF3B30);
  static const Color brandYellow = Color(0xFFFFCC00);
  static const Color brandTeal = Color(0xFF5AC8FA);
  static const Color brandPink = Color(0xFFFF2D55);
  static const Color brandIndigo = Color(0xFF5856D6);
  static const Color brandGray = Color(0xFF8E8E93);

  // ── Brand (dark variants, iOS dark system colors) ──
  static const Color brandBlueDark = Color(0xFF0A84FF);
  static const Color brandPurpleDark = Color(0xFFBF5AF2);
  static const Color brandGreenDark = Color(0xFF30D158);
  static const Color brandOrangeDark = Color(0xFFFF9F0A);
  static const Color brandRedDark = Color(0xFFFF453A);
  static const Color brandYellowDark = Color(0xFFFFD60A);
  static const Color brandTealDark = Color(0xFF64D2FF);
  static const Color brandPinkDark = Color(0xFFFF375F);
  static const Color brandIndigoDark = Color(0xFF5E5CE6);
  static const Color brandGrayDark = Color(0xFF98989F);

  // ── System Backgrounds (light, iOS grouped style) ──
  static const Color backgroundPrimary = Color(0xFFF2F2F7);
  static const Color backgroundSecondary = Color(0xFFFFFFFF);
  static const Color backgroundTertiary = Color(0xFFF2F2F7);

  // ── System Backgrounds (dark, iOS grouped style) ──
  static const Color backgroundPrimaryDark = Color(0xFF000000);
  static const Color backgroundSecondaryDark = Color(0xFF1C1C1E);
  static const Color backgroundTertiaryDark = Color(0xFF2C2C2E);

  // ── Labels (light) ──
  static const Color labelPrimary = Color(0xFF1C1C1E);
  static const Color labelSecondary = Color(0xFF6C6C70);
  static const Color labelTertiary = Color(0xFFAEAEB2);
  static const Color labelQuaternary = Color(0xFFD1D1D6);

  // ── Labels (dark) ──
  static const Color labelPrimaryDark = Color(0xFFFFFFFF);
  static const Color labelSecondaryDark = Color(0xFF98989F);
  static const Color labelTertiaryDark = Color(0xFF6C6C70);
  static const Color labelQuaternaryDark = Color(0xFF48484A);

  // ── Fills (light) ──
  static const Color fillPrimary = Color(0xFFE5E5EA);
  static const Color fillSecondary = Color(0xFFF2F2F7);
  static const Color fillTertiary = Color(0x44FFFFFF);

  // ── Fills (dark) ──
  static const Color fillPrimaryDark = Color(0xFF2C2C2E);
  static const Color fillSecondaryDark = Color(0xFF3A3A3C);
  static const Color fillTertiaryDark = Color(0x33000000);

  // ── Separators (light) ──
  static const Color separator = Color(0x3C3C3C43);
  static const Color separatorOpaque = Color(0xFFC6C6C8);

  // ── Separators (dark) ──
  static const Color separatorDark = Color(0x3CEBEBF5);
  static const Color separatorOpaqueDark = Color(0xFF38383A);
}
