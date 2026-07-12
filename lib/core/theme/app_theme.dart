import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

/// Enpix Design System — iOS 18-inspired light theme.
///
/// Design decisions:
/// - Rooted in iOS grouped style (light gray background, white cards)
/// - SF-style typography sizing
/// - Thin separators, subtle shadows, generous corner radii
/// - Consistent with iOS Settings / Photos visual language
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.backgroundPrimary,

      // ── Color Scheme ──
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandBlue,
        onPrimary: Colors.white,
        secondary: AppColors.brandGreen,
        onSecondary: Colors.white,
        error: AppColors.brandRed,
        onError: Colors.white,
        surface: AppColors.backgroundSecondary,
        onSurface: AppColors.labelPrimary,
        outline: AppColors.separatorOpaque,
      ),

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: AppColors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: AppColors.labelPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.brandBlue, size: 24),
        actionsIconTheme: IconThemeData(color: AppColors.brandBlue, size: 24),
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 56,
        backgroundColor: AppColors.backgroundSecondary,
        indicatorColor: AppColors.brandBlue.withAlpha(25),
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: AppColors.brandBlue,
              size: 20,
            );
          }
          return const IconThemeData(
            color: AppColors.brandGray,
            size: 20,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.brandBlue,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: AppColors.brandGray,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          );
        }),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.backgroundSecondary,
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
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: AppColors.labelPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.labelPrimary,
          letterSpacing: -0.4,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.labelPrimary,
          letterSpacing: -0.3,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.labelPrimary,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.labelPrimary,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.labelPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: AppColors.labelPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppColors.labelPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.labelSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.brandBlue,
        ),
      ),

      // ── Input Fields ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.separatorOpaque),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.separatorOpaque),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.brandRed),
        ),
        labelStyle: const TextStyle(
          color: AppColors.labelSecondary,
          fontSize: 15,
        ),
        hintStyle: const TextStyle(
          color: AppColors.labelTertiary,
          fontSize: 15,
        ),
      ),

      // ── Dividers ──
      dividerTheme: const DividerThemeData(
        color: AppColors.separator,
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
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandBlue,
        linearTrackColor: AppColors.fillPrimary,
        circularTrackColor: AppColors.fillPrimary,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.brandGreen;
          }
          return AppColors.fillPrimary;
        }),
      ),

      // ── Slider ──
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.brandBlue,
        inactiveTrackColor: AppColors.fillPrimary,
        thumbColor: Colors.white,
        overlayColor: AppColors.brandBlue.withAlpha(20),
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
        backgroundColor: AppColors.fillSecondary,
        selectedColor: AppColors.brandBlue.withAlpha(30),
        disabledColor: AppColors.fillPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide.none,
        ),
      ),

      // ── Floating Action Button ──
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 8,
        shape: CircleBorder(),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      // ── Bottom Sheet ──
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      // ── Icon ──
      iconTheme: const IconThemeData(
        color: AppColors.brandBlue,
        size: 24,
      ),
    );
  }
}
