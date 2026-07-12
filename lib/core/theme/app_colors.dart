import 'package:flutter/material.dart';

/// Enpix Design System — iOS 18-inspired light color palette.
///
/// All colors accessible and meet WCAG AA contrast requirements.
/// Use these constants everywhere — never raw [Color] literals.
class AppColors {
  AppColors._();

  // ── Brand ──
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

  // ── System Backgrounds (iOS 18 grouped style) ──
  /// Root view background — light gray.
  static const Color backgroundPrimary = Color(0xFFF2F2F7);
  /// Card / grouped cell background — white.
  static const Color backgroundSecondary = Color(0xFFFFFFFF);
  /// Tertiary fill for nested grouped rows.
  static const Color backgroundTertiary = Color(0xFFF2F2F7);

  // ── Labels ──
  static const Color labelPrimary = Color(0xFF1C1C1E);
  static const Color labelSecondary = Color(0xFF6C6C70);
  static const Color labelTertiary = Color(0xFFAEAEB2);
  static const Color labelQuaternary = Color(0xFFD1D1D6);

  // ── Fill Colors ──
  static const Color fillPrimary = Color(0xFFE5E5EA);
  static const Color fillSecondary = Color(0xFFF2F2F7);
  static const Color fillTertiary = Color(0x44FFFFFF);

  // ── Separators ──
  static const Color separator = Color(0x3C3C3C43);
  static const Color separatorOpaque = Color(0xFFC6C6C8);

  // ── Status Colors (app-specific) ──
  static const Color statusLocal = Color(0xFF8E8E93);
  static const Color statusPending = brandOrange;
  static const Color statusSynced = brandGreen;
  static const Color statusFailed = brandRed;
  static const Color statusEncrypted = brandPurple;

  /// Map archive status string to color.
  static Color forArchiveStatus(String status) {
    return switch (status) {
      'local' => statusLocal,
      'pending_upload' || 'archiving' => statusPending,
      'archived' => statusSynced,
      'failed' => statusFailed,
      'missing' => brandTeal,
      _ => statusLocal,
    };
  }

  // ── Chart Colors ──
  static const List<Color> chartColors = [
    brandBlue,
    brandGreen,
    brandOrange,
    brandPurple,
    brandPink,
    brandTeal,
    brandIndigo,
    brandYellow,
  ];
}
