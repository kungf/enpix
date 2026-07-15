import 'package:flutter/material.dart';
import 'package:enpix/core/theme/app_colors.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Loading state with optional message and shimmer effect.
class EnpixLoadingState extends StatelessWidget {
  final String? message;

  const EnpixLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              style: const TextStyle(
                color: AppColors.labelSecondary,
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
