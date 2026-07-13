import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/services/providers.dart';
import 'package:see_photo/services/crypto/credential_service.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_section.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_list_tile.dart';
import 'package:see_photo/presentation/screens/settings/dialogs/setup_password_dialog.dart';
import 'package:see_photo/presentation/screens/settings/dialogs/unlock_and_reset_dialogs.dart';

/// Encryption passphrase section — controls the passphrase that protects
/// end-to-end encrypted cloud photos.
class SecuritySection extends ConsumerStatefulWidget {
  const SecuritySection({super.key});

  @override
  ConsumerState<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<SecuritySection> {
  @override
  Widget build(BuildContext context) {
    final cred = ref.watch(credentialServiceProvider);
    final isActive = cred.isSessionActive;

    return EnpixSection(
      header: '数据加密',
      children: [
        EnpixListTile(
          icon: Icons.lock_rounded,
          iconColor: isActive ? AppColors.brandGreen : AppColors.brandGray,
          title: '加密密码',
          subtitle: isActive ? '已设置' : '未设置',
          trailing: isActive
              ? TextButton(
                  onPressed: _changePassphrase,
                  child: const Text('修改', style: TextStyle(fontSize: 15)),
                )
              : FilledButton.tonal(
                  onPressed: _setupPassphrase,
                  child: const Text('设置'),
                ),
        ),
      ],
    );
  }

  Future<void> _setupPassphrase() async {
    final cred = ref.read(credentialServiceProvider);
    final pw = await showSetupPasswordDialog(context);
    if (pw == null || pw.isEmpty) return;
    try {
      final kek = await cred.setupPassphrase(pw);
      cred.startSession(kek);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加密密码已设置'), backgroundColor: AppColors.brandGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e'), backgroundColor: AppColors.brandRed));
      }
    }
  }

  Future<void> _changePassphrase() async {
    final cred = ref.read(credentialServiceProvider);
    final oldPw = await showUnlockDialog(context);
    if (oldPw == null || oldPw.isEmpty) return;
    try {
      await cred.verifyPassphrase(oldPw);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码错误'), backgroundColor: AppColors.brandRed));
      }
      return;
    }

    final newPw = await showSetupPasswordDialog(context);
    if (newPw == null || newPw.isEmpty) return;

    try {
      await cred.changePassphrase(oldPw, newPw);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码已更新'), backgroundColor: AppColors.brandGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('修改失败: $e'), backgroundColor: AppColors.brandRed));
      }
    }
  }
}
