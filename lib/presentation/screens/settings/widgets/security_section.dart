import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';
import 'package:enpix/presentation/shared/widgets/enpix_list_tile.dart';
import 'package:enpix/presentation/screens/settings/dialogs/setup_password_dialog.dart';
import 'package:enpix/presentation/screens/settings/dialogs/unlock_and_reset_dialogs.dart';
import 'package:enpix/presentation/screens/settings/dialogs/recovery_key_dialog.dart';

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
    ref.watch(sessionTickProvider);
    final cred = ref.watch(credentialServiceProvider);
    final isActive = cred.isSessionActive;

    return EnpixSection(
      header: '数据加密',
      children: [
        EnpixListTile(
          icon: Icons.lock_rounded,
          iconColor:
              isActive ? context.colors.brandGreen : context.colors.brandGray,
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
        if (isActive) ...[
          EnpixListTile(
            icon: Icons.key_rounded,
            iconColor: context.colors.brandPurple,
            title: '备份恢复密钥',
            subtitle: '忘记密码时恢复数据的唯一方式',
            trailing: TextButton(
              onPressed: _backupRecoveryKey,
              child: const Text('备份', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
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
      ref.read(sessionTickProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('加密密码已设置'),
            backgroundColor: context.colors.brandGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('设置失败: $e'),
            backgroundColor: context.colors.brandRed,
          ),
        );
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
          SnackBar(
            content: const Text('密码错误'),
            backgroundColor: context.colors.brandRed,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final newPw = await showSetupPasswordDialog(context);
    if (newPw == null || newPw.isEmpty) return;

    try {
      await cred.changePassphrase(oldPw, newPw);
      ref.read(sessionTickProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('密码已更新'),
            backgroundColor: context.colors.brandGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('修改失败: $e'),
            backgroundColor: context.colors.brandRed,
          ),
        );
      }
    }
  }

  Future<void> _backupRecoveryKey() async {
    final cred = ref.read(credentialServiceProvider);
    final recovery = ref.read(recoveryServiceProvider);

    if (cred.sessionMasterKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请先解锁'),
            backgroundColor: context.colors.brandRed,
          ),
        );
      }
      return;
    }

    try {
      final fingerprint = await cred.getKekFingerprint() ?? 'shared';
      final mnemonic = await recovery.setupRecovery(
        masterKey: cred.sessionMasterKey!,
        kekFingerprint: fingerprint,
      );

      if (mounted) {
        final confirmed = await showRecoveryKeyDialog(context, mnemonic);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(confirmed == true ? '恢复密钥已备份' : '请稍后备份恢复密钥'),
              backgroundColor: confirmed == true
                  ? context.colors.brandGreen
                  : context.colors.brandOrange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('备份失败: $e'),
            backgroundColor: context.colors.brandRed,
          ),
        );
      }
    }
  }
}
