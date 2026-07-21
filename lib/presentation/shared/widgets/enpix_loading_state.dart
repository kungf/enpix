import 'package:flutter/material.dart';
import 'package:enpix/core/theme/context_ext.dart';
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
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(context.colors.brandBlue),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              style: TextStyle(
                color: context.colors.labelSecondary,
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
