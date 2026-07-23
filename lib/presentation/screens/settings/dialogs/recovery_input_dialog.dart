import 'package:flutter/material.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Dialog to input the 24-word recovery mnemonic for password recovery.
/// Returns the entered mnemonic, or null if cancelled.
Future<String?> showRecoveryInputDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _RecoveryInputDialog(),
  );
}

class _RecoveryInputDialog extends StatefulWidget {
  const _RecoveryInputDialog();
  @override
  State<_RecoveryInputDialog> createState() => _RecoveryInputDialogState();
}

class _RecoveryInputDialogState extends State<_RecoveryInputDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _wordCount =>
      _ctrl.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('找回密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '输入备份的 24 个恢复密钥单词（空格分隔）。恢复后可重新设置密码，云端照片将保持可解密。',
            style: TextStyle(
              fontSize: 13,
              color: context.colors.labelSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '恢复密钥',
              hintText: 'word1 word2 ... word24',
              border: const OutlineInputBorder(),
              helperText: '已输入 $_wordCount / 24 个单词',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _wordCount == 24
              ? () => Navigator.pop(context, _ctrl.text)
              : null,
          child: const Text('恢复'),
        ),
      ],
    );
  }
}
