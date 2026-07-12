import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/services/providers.dart';
import 'package:see_photo/services/crypto/credential_service.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_section.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_list_tile.dart';
import 'package:see_photo/presentation/screens/settings/dialogs/setup_password_dialog.dart';
import 'package:see_photo/presentation/screens/settings/dialogs/unlock_and_reset_dialogs.dart';

/// Security section — encryption key management.
class SecuritySection extends ConsumerWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credService = ref.read(credentialServiceProvider);

    return EnpixSection(
      header: '安全',
      children: [
        const EnpixListTile(
          icon: Icons.key_rounded, iconColor: AppColors.brandPurple,
          title: '加密算法', subtitle: 'XChaCha20-Poly1305 + Argon2id + BLAKE2b',
        ),
        _PassphraseTile(credService: credService),
        const EnpixListTile(
          icon: Icons.vpn_key_rounded, iconColor: AppColors.brandGray,
          title: 'S3 凭证', subtitle: '保存时自动用密码加密',
        ),
      ],
    );
  }
}

class _PassphraseTile extends ConsumerWidget {
  final CredentialService credService;
  const _PassphraseTile({required this.credService});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = credService.isSessionActive;
    return EnpixListTile(
      icon: Icons.lock_rounded,
      iconColor: active ? AppColors.brandGreen : AppColors.brandGray,
      title: active ? '加密密钥' : '设置加密密码',
      subtitle: active ? '已解锁' : '已锁定',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (active)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.brandRed),
            onPressed: () => _reset(context, ref),
            tooltip: '重置',
          )
        else
          FilledButton.tonal(onPressed: () => _unlockOrSetup(context, ref), child: const Text('解锁')),
      ]),
    );
  }

  Future<void> _unlockOrSetup(BuildContext context, WidgetRef ref) async {
    final cred = ref.read(credentialServiceProvider);
    final hasPw = await cred.hasPassphrase();
    if (hasPw) {
      final pw = await showUnlockDialog(context);
      if (pw == null || pw.isEmpty) return;
      try {
        await cred.unlockWithPassphrase(pw);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已解锁'), backgroundColor: AppColors.brandGreen));
      } on Exception {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码错误')));
      }
    } else {
      final pw = await showSetupPasswordDialog(context);
      if (pw == null || pw.isEmpty) return;
      final kek = await cred.setupPassphrase(pw);
      cred.startSession(kek);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已设置'), backgroundColor: AppColors.brandGreen));
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await showResetDialog(context);
    if (ok == true) {
      await ref.read(credentialServiceProvider).resetAll();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置')));
    }
  }
}
