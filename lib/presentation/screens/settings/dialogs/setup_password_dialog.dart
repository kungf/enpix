import 'package:flutter/material.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';

enum _Strength { none, weak, fair, good, strong }

/// Dialog to set up a new encryption passphrase with strength meter.
Future<String?> showSetupPasswordDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _SetupPasswordDialog(),
  );
}

class _SetupPasswordDialog extends StatefulWidget {
  const _SetupPasswordDialog();
  @override
  State<_SetupPasswordDialog> createState() => _SetupPasswordDialogState();
}

class _SetupPasswordDialogState extends State<_SetupPasswordDialog> {
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  var _strength = _Strength.none;
  var _obscurePw = true;
  var _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    final pw = _pwCtrl.text;
    if (pw.isEmpty) return null;
    if (pw.length < 8) return '密码至少需要 8 位';
    if (pw != _confirmCtrl.text && _confirmCtrl.text.isNotEmpty) {
      return '两次输入的密码不一致';
    }
    return null;
  }

  _Strength _calcStrength(String pw) {
    if (pw.isEmpty) return _Strength.none;
    if (pw.length < 6) return _Strength.weak;
    final n = (pw.contains(RegExp(r'[A-Z]')) ? 1 : 0) +
        (pw.contains(RegExp(r'[a-z]')) ? 1 : 0) +
        (pw.contains(RegExp(r'[0-9]')) ? 1 : 0) +
        (pw.contains(RegExp(r'[^A-Za-z0-9]')) ? 1 : 0);
    if (pw.length >= 12 && n >= 4) return _Strength.strong;
    if (pw.length >= 10 && n >= 3) return _Strength.good;
    if (pw.length >= 8 && n >= 2) return _Strength.fair;
    return _Strength.weak;
  }

  Widget _buildStrengthBar() {
    final (label, color, w) = switch (_strength) {
      _Strength.none => ('', Colors.transparent, 0.0),
      _Strength.weak => ('弱', context.colors.brandRed, 0.25),
      _Strength.fair => ('一般', context.colors.brandOrange, 0.5),
      _Strength.good => ('好', context.colors.brandGreen, 0.75),
      _Strength.strong => ('强', context.colors.brandGreen, 1.0),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: w,
            minHeight: 4,
            backgroundColor: context.colors.fillPrimary,
            color: color,
          ),
        ),
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置加密密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.colors.brandOrange.withAlpha(20),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: context.colors.brandOrange.withAlpha(60),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_rounded,
                    size: 20,
                    color: context.colors.brandOrange,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '端到端加密',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.colors.brandOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '你的照片会在上传前加密，服务器无法查看内容。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '⚠️ 请牢记此密码。忘记密码将无法解密照片，且无法恢复。',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.colors.brandRed,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _pwCtrl,
              obscureText: _obscurePw,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '建议大小写字母+数字+符号',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePw
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePw = !_obscurePw),
                ),
              ),
              onChanged: (_) => setState(() {
                _strength = _calcStrength(_pwCtrl.text);
                _errorText = _validate();
              }),
            ),
            _buildStrengthBar(),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: '确认密码',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirm = !_obscureConfirm,
                  ),
                ),
              ),
              onChanged: (_) => setState(() => _errorText = _validate()),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    color: context.colors.brandRed,
                    fontSize: 12,
                  ),
                ),
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
          onPressed: () {
            final pw = _pwCtrl.text;
            final err = _validate();
            if (err != null) {
              setState(() => _errorText = err);
              return;
            }
            if (pw.isEmpty) {
              setState(() => _errorText = '请输入密码');
              return;
            }
            Navigator.pop(context, pw);
          },
          child: const Text('设置'),
        ),
      ],
    );
  }
}
