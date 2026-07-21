import 'package:flutter/material.dart';

import 'app_color_scheme.dart';

/// Convenience accessors so widgets read semantic colors/typography
/// from the active theme instead of hardcoding values.
extension AppContextExt on BuildContext {
  /// Brightness-aware semantic colors (light/dark).
  AppColorScheme get colors =>
      Theme.of(this).extension<AppColorScheme>() ?? AppColorScheme.light;

  /// Theme typography.
  TextTheme get textTheme => Theme.of(this).textTheme;
}
