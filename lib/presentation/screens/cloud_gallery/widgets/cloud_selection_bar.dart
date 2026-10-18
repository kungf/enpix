import 'package:flutter/material.dart';

import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/presentation/shared/widgets/enpix_progress.dart';

/// Bottom action bar shown while cloud items are selected.
class CloudSelectionBar extends StatelessWidget {
  const CloudSelectionBar({
    super.key,
    required this.count,
    required this.isWorking,
    required this.onDownload,
    required this.onDelete,
    required this.onCancel,
    this.workingLabel,
  });

  final int count;
  final bool isWorking;
  final String? workingLabel;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: context.colors.backgroundSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWorking && workingLabel != null) ...[
              Row(
                children: [
                  const EnpixCircularProgress(size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      workingLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.labelSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Row(
              children: [
                IconButton(
                  onPressed: isWorking ? null : onCancel,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '取消选择',
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: isWorking ? null : onDownload,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text('保存到相册 ($count)'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: isWorking ? null : onDelete,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.brandRed,
                  ),
                  icon: const Icon(Icons.delete_rounded, size: 18),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
