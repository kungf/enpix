import 'package:flutter/material.dart';

/// App color palette.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF4A90D9);

  // Archive status colors
  static const Color statusLocal = Color(0xFF9E9E9E); // grey
  static const Color statusArchiving = Color(0xFFFFA726); // orange
  static const Color statusArchived = Color(0xFF66BB6A); // green
  static const Color statusFailed = Color(0xFFEF5350); // red
  static const Color statusMissing = Color(0xFF78909C); // blue-grey

  /// Get the color for an archive status.
  static Color forArchiveStatus(String status) {
    return switch (status) {
      'local' => statusLocal,
      'pending_upload' || 'archiving' => statusArchiving,
      'archived' => statusArchived,
      'failed' => statusFailed,
      'missing' => statusMissing,
      _ => statusLocal,
    };
  }
}
