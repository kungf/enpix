import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Enpix semantic color scheme — brightness-aware theme extension.
///
/// Widgets access these via `context.colors` (see `context_ext.dart`)
/// instead of referencing raw [AppColors] constants, so every screen
/// adapts automatically to light/dark mode.
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  // Brand
  final Color brandBlue;
  final Color brandPurple;
  final Color brandGreen;
  final Color brandOrange;
  final Color brandRed;
  final Color brandYellow;
  final Color brandTeal;
  final Color brandPink;
  final Color brandIndigo;
  final Color brandGray;

  // Backgrounds
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color backgroundTertiary;

  // Labels
  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color labelQuaternary;

  // Fills
  final Color fillPrimary;
  final Color fillSecondary;
  final Color fillTertiary;

  // Separators
  final Color separator;
  final Color separatorOpaque;

  const AppColorScheme({
    required this.brandBlue,
    required this.brandPurple,
    required this.brandGreen,
    required this.brandOrange,
    required this.brandRed,
    required this.brandYellow,
    required this.brandTeal,
    required this.brandPink,
    required this.brandIndigo,
    required this.brandGray,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.backgroundTertiary,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.labelQuaternary,
    required this.fillPrimary,
    required this.fillSecondary,
    required this.fillTertiary,
    required this.separator,
    required this.separatorOpaque,
  });

  // ── Status colors (derived from brand) ──
  Color get statusLocal => brandGray;
  Color get statusPending => brandOrange;
  Color get statusSynced => brandGreen;
  Color get statusFailed => brandRed;
  Color get statusEncrypted => brandPurple;

  static const light = AppColorScheme(
    brandBlue: AppColors.brandBlue,
    brandPurple: AppColors.brandPurple,
    brandGreen: AppColors.brandGreen,
    brandOrange: AppColors.brandOrange,
    brandRed: AppColors.brandRed,
    brandYellow: AppColors.brandYellow,
    brandTeal: AppColors.brandTeal,
    brandPink: AppColors.brandPink,
    brandIndigo: AppColors.brandIndigo,
    brandGray: AppColors.brandGray,
    backgroundPrimary: AppColors.backgroundPrimary,
    backgroundSecondary: AppColors.backgroundSecondary,
    backgroundTertiary: AppColors.backgroundTertiary,
    labelPrimary: AppColors.labelPrimary,
    labelSecondary: AppColors.labelSecondary,
    labelTertiary: AppColors.labelTertiary,
    labelQuaternary: AppColors.labelQuaternary,
    fillPrimary: AppColors.fillPrimary,
    fillSecondary: AppColors.fillSecondary,
    fillTertiary: AppColors.fillTertiary,
    separator: AppColors.separator,
    separatorOpaque: AppColors.separatorOpaque,
  );

  static const dark = AppColorScheme(
    brandBlue: AppColors.brandBlueDark,
    brandPurple: AppColors.brandPurpleDark,
    brandGreen: AppColors.brandGreenDark,
    brandOrange: AppColors.brandOrangeDark,
    brandRed: AppColors.brandRedDark,
    brandYellow: AppColors.brandYellowDark,
    brandTeal: AppColors.brandTealDark,
    brandPink: AppColors.brandPinkDark,
    brandIndigo: AppColors.brandIndigoDark,
    brandGray: AppColors.brandGrayDark,
    backgroundPrimary: AppColors.backgroundPrimaryDark,
    backgroundSecondary: AppColors.backgroundSecondaryDark,
    backgroundTertiary: AppColors.backgroundTertiaryDark,
    labelPrimary: AppColors.labelPrimaryDark,
    labelSecondary: AppColors.labelSecondaryDark,
    labelTertiary: AppColors.labelTertiaryDark,
    labelQuaternary: AppColors.labelQuaternaryDark,
    fillPrimary: AppColors.fillPrimaryDark,
    fillSecondary: AppColors.fillSecondaryDark,
    fillTertiary: AppColors.fillTertiaryDark,
    separator: AppColors.separatorDark,
    separatorOpaque: AppColors.separatorOpaqueDark,
  );

  @override
  AppColorScheme copyWith({
    Color? brandBlue,
    Color? brandPurple,
    Color? brandGreen,
    Color? brandOrange,
    Color? brandRed,
    Color? brandYellow,
    Color? brandTeal,
    Color? brandPink,
    Color? brandIndigo,
    Color? brandGray,
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? backgroundTertiary,
    Color? labelPrimary,
    Color? labelSecondary,
    Color? labelTertiary,
    Color? labelQuaternary,
    Color? fillPrimary,
    Color? fillSecondary,
    Color? fillTertiary,
    Color? separator,
    Color? separatorOpaque,
  }) {
    return AppColorScheme(
      brandBlue: brandBlue ?? this.brandBlue,
      brandPurple: brandPurple ?? this.brandPurple,
      brandGreen: brandGreen ?? this.brandGreen,
      brandOrange: brandOrange ?? this.brandOrange,
      brandRed: brandRed ?? this.brandRed,
      brandYellow: brandYellow ?? this.brandYellow,
      brandTeal: brandTeal ?? this.brandTeal,
      brandPink: brandPink ?? this.brandPink,
      brandIndigo: brandIndigo ?? this.brandIndigo,
      brandGray: brandGray ?? this.brandGray,
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      backgroundTertiary: backgroundTertiary ?? this.backgroundTertiary,
      labelPrimary: labelPrimary ?? this.labelPrimary,
      labelSecondary: labelSecondary ?? this.labelSecondary,
      labelTertiary: labelTertiary ?? this.labelTertiary,
      labelQuaternary: labelQuaternary ?? this.labelQuaternary,
      fillPrimary: fillPrimary ?? this.fillPrimary,
      fillSecondary: fillSecondary ?? this.fillSecondary,
      fillTertiary: fillTertiary ?? this.fillTertiary,
      separator: separator ?? this.separator,
      separatorOpaque: separatorOpaque ?? this.separatorOpaque,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorScheme(
      brandBlue: l(brandBlue, other.brandBlue),
      brandPurple: l(brandPurple, other.brandPurple),
      brandGreen: l(brandGreen, other.brandGreen),
      brandOrange: l(brandOrange, other.brandOrange),
      brandRed: l(brandRed, other.brandRed),
      brandYellow: l(brandYellow, other.brandYellow),
      brandTeal: l(brandTeal, other.brandTeal),
      brandPink: l(brandPink, other.brandPink),
      brandIndigo: l(brandIndigo, other.brandIndigo),
      brandGray: l(brandGray, other.brandGray),
      backgroundPrimary: l(backgroundPrimary, other.backgroundPrimary),
      backgroundSecondary: l(backgroundSecondary, other.backgroundSecondary),
      backgroundTertiary: l(backgroundTertiary, other.backgroundTertiary),
      labelPrimary: l(labelPrimary, other.labelPrimary),
      labelSecondary: l(labelSecondary, other.labelSecondary),
      labelTertiary: l(labelTertiary, other.labelTertiary),
      labelQuaternary: l(labelQuaternary, other.labelQuaternary),
      fillPrimary: l(fillPrimary, other.fillPrimary),
      fillSecondary: l(fillSecondary, other.fillSecondary),
      fillTertiary: l(fillTertiary, other.fillTertiary),
      separator: l(separator, other.separator),
      separatorOpaque: l(separatorOpaque, other.separatorOpaque),
    );
  }
}
