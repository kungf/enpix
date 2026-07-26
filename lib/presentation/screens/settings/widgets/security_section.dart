import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/services/storage/s3_config_service.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';
import 'package:enpix/presentation/shared/widgets/enpix_list_tile.dart';
import 'package:enpix/presentation/screens/settings/dialogs/setup_password_dialog.dart';
import 'package:enpix/presentation/screens/settings/dialogs/unlock_and_reset_dialogs.dart';
import 'package:enpix/presentation/screens/settings/dialogs/recovery_key_dialog.dart';
import 'package:enpix/presentation/screens/settings/dialogs/recovery_input_dialog.dart';
import 'package:enpix/presentation/screens/settings/dialogs/backup_reminder_dialog.dart';

/// Encryption passphrase section — controls the passphrase that protects
/// end-to-end encrypted cloud photos.
///
/// Three states:
/// - **未设置**: no passphrase in Keychain → offer 设置.
/// - **未解锁**: passphrase exists but session is not active (e.g. after an
///   app restart where auto-unlock failed) → offer 解锁 and 找回密码.
///   Crucially we must NOT offer 设置 here — setupPassphrase would generate
///   a NEW Master Key and orphan every previously encrypted photo.
/// - **已解锁**: session active → offer 修改 and 备份恢复密钥.
class SecuritySection extends ConsumerStatefulWidget {
  const SecuritySection({super.key});

  @override
  ConsumerState<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<SecuritySection> {
  bool _hasPassphrase = false;

  @override
  void initState() {
    super.initState();
    _refreshHasPassphrase();
  }

  Future<void> _refreshHasPassphrase() async {
    final has = await ref.read(credentialServiceProvider).hasPassphrase();
    if (mounted && has != _hasPassphrase) {
      setState(() => _hasPassphrase = has);
    }
  }

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
          subtitle: isActive
              ? '已解锁'
              : !_hasPassphrase
                  ? '未设置'
                  : '已设置 · 未解锁',
          trailing: isActive
              ? TextButton(
                  onPressed: _changePassphrase,
                  child: const Text('修改', style: TextStyle(fontSize: 15)),
                )
              : !_hasPassphrase
                  ? FilledButton.tonal(
                      onPressed: _setupPassphrase,
                      child: const Text('设置'),
                    )
                  : TextButton(
                      onPressed: _unlock,
                      child: const Text('解锁', style: TextStyle(fontSize: 15)),
                    ),
        ),
        if (_hasPassphrase && !isActive)
          EnpixListTile(
            icon: Icons.key_rounded,
            iconColor: context.colors.brandOrange,
            title: '找回密码',
            subtitle: '忘记密码？用恢复密钥恢复数据并重设密码',
            trailing: TextButton(
              onPressed: _recoverWithKey,
              child: const Text('恢复', style: TextStyle(fontSize: 15)),
            ),
          ),
        if (_hasPassphrase && !isActive)
          EnpixListTile(
            icon: Icons.delete_forever_rounded,
            iconColor: context.colors.brandRed,
            title: '重置加密数据',
            subtitle: '删除所有密钥和密码。云端已加密照片将无法解密。',
            trailing: TextButton(
              onPressed: _resetAll,
              child: Text(
                '重置',
                style: TextStyle(fontSize: 15, color: context.colors.brandRed),
              ),
            ),
          ),
        if (isActive)
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
    );
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? context.colors.brandRed : context.colors.brandGreen,
      ),
    );
  }

  Future<void> _setupPassphrase() async {
    final cred = ref.read(credentialServiceProvider);
    final pw = await showSetupPasswordDialog(context);
    if (pw == null || pw.isEmpty) return;
    // Keep the try-catch tight around the crypto operation so that UI
    // updates and the follow-up backup reminder are not reported as
    // "setup failed" errors.
    try {
      // setupPassphrase activates the full session (KEK + Master Key) and
      // persists the passphrase for auto-unlock itself.
      await cred.setupPassphrase(pw);
    } catch (e) {
      _showSnack('设置失败: $e', isError: true);
      return;
    }
    if (mounted) setState(() => _hasPassphrase = true);
    ref.read(sessionTickProvider.notifier).state++;
    // Double-check against Keychain as a safety net.
    await _refreshHasPassphrase();
    _showSnack('加密密码已设置', isError: false);
    // Prompt the user to back up the recovery key — the only way to
    // recover encrypted data if they forget their password.
    if (mounted) {
      final shouldBackup = await showBackupReminderDialog(context);
      if (shouldBackup == true && mounted) {
        await _backupRecoveryKey();
      }
    }
  }

  /// Unlock an existing passphrase — the entry point for the "已设置 · 未解锁"
  /// state, e.g. after an app restart where auto-unlock failed.
  Future<void> _unlock() async {
    final cred = ref.read(credentialServiceProvider);
    final pw = await showUnlockDialog(context);
    if (pw == null || pw.isEmpty) return;
    try {
      await cred.unlockWithPassphrase(pw);
      ref.read(sessionTickProvider.notifier).state++;
    } on WrongPassphraseException {
      _showSnack('密码错误', isError: true);
    } on Exception catch (e) {
      _showSnack('解锁失败: $e', isError: true);
    }
  }

  /// Recover access with the 24-word recovery key, then set a new password.
  /// The Master Key is preserved end-to-end, so all cloud photos stay
  /// decryptable.
  Future<void> _recoverWithKey() async {
    final messenger = ScaffoldMessenger.of(context);
    final brandRed = context.colors.brandRed;
    final brandGreen = context.colors.brandGreen;
    final cred = ref.read(credentialServiceProvider);
    final recovery = ref.read(recoveryServiceProvider);

    final mnemonic = await showRecoveryInputDialog(context);
    if (mnemonic == null || mnemonic.trim().isEmpty) return;

    // Recovery downloads the wrapped Master Key from S3 — must be configured.
    final s3Result = await ref.read(s3ConfigServiceProvider).ensureConfigured();
    if (s3Result != S3ConfigResult.configured) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('请先在设置中配置 S3 存储'),
            backgroundColor: brandRed,
          ),
        );
      }
      return;
    }

    try {
      final prefix = await cred.getPathPrefix();
      final masterKey = await recovery.recoverFromMnemonic(
        mnemonic: mnemonic,
        pathPrefix: prefix,
      );
      cred.restoreWithRecoveryKey(masterKey);
    } on Exception catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('恢复失败: $e'), backgroundColor: brandRed),
        );
      }
      return;
    }

    if (!mounted) return;
    final newPw = await showSetupPasswordDialog(context);
    if (newPw == null || newPw.isEmpty) {
      // Session holds the recovered Master Key but no new password was set.
      // Recovery can be retried later — nothing was written.
      return;
    }

    try {
      await cred.resetPassphrase(newPw);
      if (mounted) setState(() => _hasPassphrase = true);
      ref.read(sessionTickProvider.notifier).state++;
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('密码已重置，数据已恢复'),
            backgroundColor: brandGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('重置失败: $e'), backgroundColor: brandRed),
        );
      }
    }
  }

  Future<void> _changePassphrase() async {
    final cred = ref.read(credentialServiceProvider);
    final oldPw = await showUnlockDialog(context);
    if (oldPw == null || oldPw.isEmpty) return;

    if (!mounted) return;
    final newPw = await showSetupPasswordDialog(context);
    if (newPw == null || newPw.isEmpty) return;

    // Keep the try-catch tight around the crypto operation so that the
    // follow-up backup reminder is not reported as a "change failed" error.
    try {
      // changePassphrase verifies the old password internally and keeps the
      // session active with the new KEK.
      await cred.changePassphrase(oldPw, newPw);
    } on WrongPassphraseException {
      _showSnack('原密码错误', isError: true);
      return;
    } catch (e) {
      _showSnack('修改失败: $e', isError: true);
      return;
    }
    ref.read(sessionTickProvider.notifier).state++;
    _showSnack('密码已更新', isError: false);
    // Remind the user to back up the recovery key if they haven't already.
    if (mounted) {
      final shouldBackup = await showBackupReminderDialog(context);
      if (shouldBackup == true && mounted) {
        await _backupRecoveryKey();
      }
    }
  }

  Future<void> _backupRecoveryKey() async {
    final cred = ref.read(credentialServiceProvider);
    final recovery = ref.read(recoveryServiceProvider);

    if (cred.sessionMasterKey == null) {
      _showSnack('请先解锁', isError: true);
      return;
    }

    // Recovery blob is uploaded to S3 — ensure configuration is loaded.
    final s3Result = await ref.read(s3ConfigServiceProvider).ensureConfigured();
    if (s3Result != S3ConfigResult.configured) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要配置 S3 存储'),
            content: const Text(
              '恢复密钥需要上传到云端存储。请先在设置中配置 S3 存储信息，然后重新备份。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    try {
      final prefix = await cred.getPathPrefix();
      final mnemonic = await recovery.setupRecovery(
        masterKey: cred.sessionMasterKey!,
        pathPrefix: prefix,
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
      _showSnack('备份失败: $e', isError: true);
    }
  }

  Future<void> _resetAll() async {
    final cred = ref.read(credentialServiceProvider);
    final confirmed = await showResetDialog(context);
    if (confirmed != true) return;

    try {
      await cred.resetAll();
      await _refreshHasPassphrase();
      _showSnack('加密数据已重置，请重新设置密码', isError: false);
    } catch (e) {
      _showSnack('重置失败: $e', isError: true);
    }
  }
}
