import 'package:flutter/material.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Enpix list tile — icon badge + title + subtitle + optional trailing widget.
class EnpixListTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const EnpixListTile({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: (iconColor ?? context.colors.brandBlue).withAlpha(30),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Icon(
                icon,
                size: 17,
                color: iconColor ?? context.colors.brandBlue,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: context.colors.labelPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.labelSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Trailing widget
            if (trailing != null) trailing!,
            // Chevron (if no trailing and has onTap)
            if (trailing == null && onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.colors.labelTertiary,
              ),
          ],
        ),
      ),
    );
  }
}
