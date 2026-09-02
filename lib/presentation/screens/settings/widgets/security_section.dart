import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
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

/// Fixed S3 paths under the system prefix.
const _keystorePath = 'enpix/.sys/keystore';
const _warningPath = 'enpix/.sys/WARNING';

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
  static final _log = Logger('SecuritySection');
  bool _hasPassphrase = false;
  bool _autoUnlock = false;

  @override
  void initState() {
    super.initState();
    _refreshHasPassphrase();
    _refreshAutoUnlock();
  }

  Future<void> _refreshHasPassphrase() async {
    final has = await ref.read(credentialServiceProvider).hasPassphrase();
    if (mounted && has != _hasPassphrase) {
      setState(() => _hasPassphrase = has);
    }
  }

  Future<void> _refreshAutoUnlock() async {
    final enabled =
        await ref.read(credentialServiceProvider).isAutoUnlockEnabled();
    if (mounted && enabled != _autoUnlock) {
      setState(() => _autoUnlock = enabled);
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
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _restoreFromCloud,
                          child: const Text(
                            '从云端恢复',
                            style: TextStyle(fontSize: 15),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _setupPassphrase,
                          child: const Text('设置'),
                        ),
                      ],
                    )
                  : TextButton(
                      onPressed: _unlock,
                      child: const Text('解锁', style: TextStyle(fontSize: 15)),
                    ),
        ),
        if (_hasPassphrase)
          EnpixListTile(
            icon: Icons.fingerprint_rounded,
            iconColor: context.colors.brandPurple,
            title: '自动解锁',
            subtitle:
                _autoUnlock ? '已开启 · 重启后免密码恢复会话，受生物识别保护' : '已关闭 · 重启后需手动输入密码解锁',
            trailing: Switch(
              value: _autoUnlock,
              onChanged: _setAutoUnlock,
            ),
          ),
        if (_hasPassphrase)
          EnpixListTile(
            icon: Icons.key_rounded,
            iconColor: context.colors.brandOrange,
            title: '重置密码',
            subtitle: '用恢复密钥重设密码',
            trailing: TextButton(
              onPressed: _recoverWithKey,
              child: const Text('重置', style: TextStyle(fontSize: 15)),
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

  /// Toggle auto-unlock. Enabling confirms the security trade-off first;
  /// disabling is immediate.
  Future<void> _setAutoUnlock(bool value) async {
    if (value && !await _confirmEnableAutoUnlock()) return;

    final cred = ref.read(credentialServiceProvider);
    try {
      if (value) {
        await cred.enableAutoUnlock();
      } else {
        await cred.disableAutoUnlock();
      }
    } on StateError {
      _showSnack('开启自动解锁前需要先解锁', isError: true);
      return;
    } on Exception catch (e) {
      _showSnack('操作失败: $e', isError: true);
      return;
    }
    if (mounted) setState(() => _autoUnlock = value);
  }

  /// Explicit risk disclosure before weakening the unlock posture.
  Future<bool> _confirmEnableAutoUnlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启自动解锁？'),
        content: const Text(
          '开启后，重启应用时无需输入密码即可恢复加密会话。'
          '能解锁你手机的人也将能够查看你的云端照片。\n\n'
          '建议确保设备已录入面容 ID 或指纹——验证通过后才会自动解锁。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开启'),
          ),
        ],
      ),
    );
    return ok == true;
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
    // Sync keystore to S3 so the user can recover on a new device.
    _syncKeystore();
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
      // Ensure keystore is synced to S3 (migration + keep current).
      _syncKeystore();
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
      final masterKey = await recovery.recoverFromMnemonic(
        mnemonic: mnemonic,
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
      // Re-sync keystore with the new KEK.
      _syncKeystore();
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
    // Re-sync keystore with the new KEK.
    _syncKeystore();
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
      final mnemonic = await recovery.setupRecovery(
        masterKey: cred.sessionMasterKey!,
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

  /// Upload keystore to S3 so the user can recover with their password on a
  /// new device. Best-effort — failures are logged but do not block the user.
  void _syncKeystore() {
    final cred = ref.read(credentialServiceProvider);
    final s3 = ref.read(s3ServiceProvider);
    // Fire-and-forget — keystore sync must not block the UI.
    Future.microtask(() async {
      try {
        final payload = await cred.buildKeystorePayload();
        await s3.putObject(_keystorePath, payload);
        // Also upload WARNING file.
        await s3.putObject(
          _warningPath,
          Uint8List.fromList(
            utf8.encode(
              '⚠️ 请勿删除此目录下的文件\n'
              '这些是数据恢复凭证。删除后将无法通过密码或恢复密钥找回加密数据。',
            ),
          ),
        );
        _log.info('Keystore synced to S3');
      } on Exception catch (e) {
        _log.warning('Keystore sync failed (non-fatal): $e');
      }
    });
  }

  /// Restore the Master Key from the keystore on S3 using the password.
  /// This is the entry point for existing users setting up a new device.
  Future<void> _restoreFromCloud() async {
    final cred = ref.read(credentialServiceProvider);
    final s3 = ref.read(s3ServiceProvider);

    final s3Result = await ref.read(s3ConfigServiceProvider).ensureConfigured();
    if (s3Result != S3ConfigResult.configured) {
      _showSnack('请先配置 S3 存储', isError: true);
      return;
    }

    if (!mounted) return;
    final pw = await showUnlockDialog(
      context,
      title: '输入密码以从云端恢复',
    );
    if (pw == null || pw.isEmpty) return;

    try {
      final payload = await s3.getObject(_keystorePath);
      await cred.restoreFromKeystore(pw, payload);
      if (mounted) setState(() => _hasPassphrase = true);
      ref.read(sessionTickProvider.notifier).state++;
      _showSnack('已从云端恢复', isError: false);
    } on WrongPassphraseException {
      _showSnack('密码错误', isError: true);
    } on Exception catch (e) {
      _showSnack('恢复失败: $e', isError: true);
    }
  }
}
