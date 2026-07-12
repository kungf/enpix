import 'package:flutter/material.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/core/theme/app_spacing.dart';

/// Dialog to unlock KEK session with passphrase.
Future<String?> showUnlockDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _UnlockDialog(),
  );
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();
  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _ctrl = TextEditingController();
  var _obscure = true;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('解锁密钥'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('输入密码以解锁 KEK 会话'),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _ctrl, obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '密码',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscure = !_obscure)),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('解锁')),
      ],
    );
  }
}

/// Confirmation dialog for destructive reset action.
Future<bool?> showResetDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('重置？'),
      content: const Text('删除所有加密数据，不可撤销。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(_, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
          child: const Text('重置'),
        ),
      ],
    ),
  );
}
