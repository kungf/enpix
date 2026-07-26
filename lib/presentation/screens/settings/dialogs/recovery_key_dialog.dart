import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Dialog that displays the 24-word recovery mnemonic and asks the user
/// to confirm they've written it down.
Future<bool?> showRecoveryKeyDialog(BuildContext context, String mnemonic) {
  final words = mnemonic.split(' ');
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecoveryKeyDialog(words: words),
  );
}

class _RecoveryKeyDialog extends StatefulWidget {
  final List<String> words;
  const _RecoveryKeyDialog({required this.words});

  @override
  State<_RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<_RecoveryKeyDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('备份恢复密钥'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '以下是你的 24 个恢复密钥单词，请将其保存在安全位置（如密码管理器）。\n\n'
              '如果你忘记密码，这是恢复数据的唯一方式。',
              style:
                  TextStyle(fontSize: 14, color: context.colors.labelSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.colors.fillSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: List.generate(widget.words.length, (i) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.colors.backgroundPrimary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}. ${widget.words[i]}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('稍后再说'),
        ),
        FilledButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.words.join(' ')));
            Navigator.pop(context, true);
          },
          child: const Text('复制'),
        ),
      ],
    );
  }
}

/// Dialog for entering a recovery mnemonic to restore access.
Future<String?> showRecoveryInput(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
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
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    final words = text.split(RegExp(r'\s+'));
    if (words.length != 24) {
      setState(() => _error = '请输入 24 个英文单词（当前 ${words.length} 个）');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('恢复数据'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '输入之前备份的 24 个恢复密钥单词，以恢复对加密数据的访问。',
              style:
                  TextStyle(fontSize: 14, color: context.colors.labelSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'abandon ability able ...\n（24 个英文单词，空格分隔）',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('恢复'),
        ),
      ],
    );
  }
}
