import 'package:flutter/material.dart';

import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/presentation/screens/cloud_gallery/widgets/cloud_thumb_tile.dart';
import 'package:enpix/services/cloud/cloud_media.dart';

/// A day header plus its 3-column thumbnail grid.
class CloudDaySection extends StatelessWidget {
  const CloudDaySection({
    super.key,
    required this.day,
    required this.isSelectionMode,
    required this.selectedKeys,
    required this.onTap,
    required this.onLongPress,
  });

  final CloudMediaDay day;
  final bool isSelectionMode;
  final Set<String> selectedKeys;
  final ValueChanged<CloudMedia> onTap;
  final ValueChanged<CloudMedia> onLongPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: AppSpacing.xxs,
            mainAxisSpacing: AppSpacing.xxs,
          ),
          itemCount: day.items.length,
          itemBuilder: (context, index) {
            final media = day.items[index];
            return CloudThumbTile(
              media: media,
              isSelected: selectedKeys.contains(media.thumbnailKey),
              isSelectionMode: isSelectionMode,
              onTap: () => onTap(media),
              onLongPress: () => onLongPress(media),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            day.label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.colors.labelPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: context.colors.fillSecondary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_rounded,
                  size: 12,
                  color: context.colors.labelSecondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  '${day.items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
