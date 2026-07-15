import 'package:flutter/material.dart';
import 'package:enpix/core/theme/app_colors.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Enpix grouped section — iOS 18 style with rounded card and optional header/footer.
class EnpixSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const EnpixSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                header!.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.labelSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _buildChildrenWithDividers(),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                top: AppSpacing.sm,
                right: AppSpacing.lg,
              ),
              child: Text(
                footer!,
                style: const TextStyle(
                  color: AppColors.labelSecondary,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildChildrenWithDividers() {
    final widgets = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      widgets.add(children[i]);
      if (i < children.length - 1) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Container(
              height: 0.5,
              color: AppColors.separator,
            ),
          ),
        );
      }
    }
    return widgets;
  }
}
