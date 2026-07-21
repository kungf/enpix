import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_color_scheme.dart';
import 'app_spacing.dart';

/// Enpix Design System — iOS-inspired light + dark themes.
///
/// Design decisions:
/// - Rooted in iOS grouped style (light gray/black background, cards)
/// - SF-style typography sizing
/// - Thin separators, subtle shadows, generous corner radii
/// - Semantic colors come from [AppColorScheme] (access via context.colors)
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme =>
      _build(AppColorScheme.light, Brightness.light);
  static ThemeData get darkTheme =>
      _build(AppColorScheme.dark, Brightness.dark);

  static ThemeData _build(AppColorScheme c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.backgroundPrimary,
      extensions: <ThemeExtension<dynamic>>[c],

      // ── Color Scheme ──
      colorScheme: (isDark
          ? ColorScheme.dark(
              primary: c.brandBlue,
              onPrimary: Colors.white,
              secondary: c.brandGreen,
              onSecondary: Colors.white,
              error: c.brandRed,
              onError: Colors.white,
              surface: c.backgroundSecondary,
              onSurface: c.labelPrimary,
              outline: c.separatorOpaque,
            )
          : ColorScheme.light(
              primary: c.brandBlue,
              onPrimary: Colors.white,
              secondary: c.brandGreen,
              onSecondary: Colors.white,
              error: c.brandRed,
              onError: Colors.white,
              surface: c.backgroundSecondary,
              onSurface: c.labelPrimary,
              outline: c.separatorOpaque,
            )),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: c.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: c.labelPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: c.brandBlue, size: 24),
        actionsIconTheme: IconThemeData(color: c.brandBlue, size: 24),
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 56,
        backgroundColor: c.backgroundSecondary,
        indicatorColor: c.brandBlue.withAlpha(25),
        indicatorShape: const StadiumBorder(),
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.brandBlue, size: 20);
          }
          return IconThemeData(color: c.brandGray, size: 20);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: c.brandBlue,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: c.brandGray,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          );
        }),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
      ),

      // ── Text ──
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: c.labelPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: c.labelPrimary,
          letterSpacing: -0.4,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: c.labelPrimary,
          letterSpacing: -0.3,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: c.labelPrimary,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.labelPrimary,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: c.labelPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: c.labelPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: c.labelPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: c.labelSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: c.brandBlue,
        ),
      ),

      // ── Input Fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? c.fillPrimary : c.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.separatorOpaque),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.separatorOpaque),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.brandBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c.brandRed),
        ),
        labelStyle: TextStyle(color: c.labelSecondary, fontSize: 15),
        hintStyle: TextStyle(color: c.labelTertiary, fontSize: 15),
      ),

      // ── Dividers ──
      dividerTheme: DividerThemeData(
        color: c.separator,
        thickness: 0.5,
        space: 0,
        indent: AppSpacing.lg,
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        contentTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brandBlue,
        linearTrackColor: c.fillPrimary,
        circularTrackColor: c.fillPrimary,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return c.brandGreen;
          }
          return c.fillPrimary;
        }),
      ),

      // ── Slider ──
      sliderTheme: SliderThemeData(
        activeTrackColor: c.brandBlue,
        inactiveTrackColor: c.fillPrimary,
        thumbColor: Colors.white,
        overlayColor: c.brandBlue.withAlpha(20),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        labelStyle: const TextStyle(fontSize: 14),
        backgroundColor: c.fillSecondary,
        selectedColor: c.brandBlue.withAlpha(30),
        disabledColor: c.fillPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide.none,
        ),
      ),

      // ── Floating Action Button ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brandBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 8,
        shape: const CircleBorder(),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: c.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      // ── Bottom Sheet ──
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      // ── Icon ──
      iconTheme: IconThemeData(color: c.brandBlue, size: 24),
    );
  }
}
