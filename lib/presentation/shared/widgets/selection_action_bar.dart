import 'package:flutter/material.dart';

import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/core/theme/context_ext.dart';

/// Bottom action bar shown while the user has photos selected in the gallery.
///
/// Extracted as a public widget so the selection flow is unit-testable without
/// pulling in [photo_manager] (the gallery screen owns the AssetEntity list;
/// this bar only owns the count + the upload/cancel callbacks).
class SelectionActionBar extends StatelessWidget {
  final int count;
  final Future<void> Function() onUpload;
  final VoidCallback onCancel;

  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onUpload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.backgroundSecondary,
          border: Border(
            top: BorderSide(color: context.colors.separator, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            TextButton(onPressed: onCancel, child: const Text('取消')),
            const Spacer(),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text('上传所选 ($count)'),
            ),
          ],
        ),
      ),
    );
  }
}
