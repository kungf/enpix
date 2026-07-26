import 'package:flutter/material.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Shown immediately after the user sets up their encryption passphrase for
/// the first time.
///
/// Explains what the recovery key is, why it is critical to back it up, and
/// the irreversible consequences of losing both the password and the key.
/// Lets the user choose to back up now or defer to later.
Future<bool?> showBackupReminderDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('备份恢复密钥'),
      content: const _BackupReminderContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('稍后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('立即备份'),
        ),
      ],
    ),
  );
}

class _BackupReminderContent extends StatelessWidget {
  const _BackupReminderContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.brandPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.key_rounded,
                size: 32,
                color: colors.brandPurple,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Explanation
          Text(
            '恢复密钥是一组 24 个英文单词，'
            '它是你忘记密码时唯一能找回加密数据的方式。',
            style: TextStyle(
              fontSize: 15,
              color: colors.labelPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Warning box
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.brandOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: colors.brandOrange.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: colors.brandOrange,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Enpix 采用端到端加密，我们无法帮你重置密码。'
                    '如果丢失密码和恢复密钥，加密数据将永久无法恢复。'
                    '请妥善保管在安全位置（如密码管理器），'
                    '与手机分开存放，避免同时丢失。',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.labelSecondary,
                      height: 1.5,
                    ),
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
