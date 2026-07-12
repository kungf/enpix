import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/core/theme/app_spacing.dart';
import 'package:see_photo/services/providers.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_section.dart';

/// About section — app version, crypto info, KEK fingerprint.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cred = ref.read(credentialServiceProvider);
    return EnpixSection(
      header: '关于',
      children: [
        FutureBuilder<String?>(
          future: cred.getKekFingerprint(),
          builder: (_, s) => _infoRow('KEK 指纹', s.data?.substring(0, 12) ?? '—', mono: true),
        ),
        _infoRow('版本', '0.1.0'),
        _infoRow('加密', 'XChaCha20-Poly1305'),
        _infoRow('密钥派生', 'Argon2id (64 MiB)'),
        _infoRow('哈希', 'BLAKE2b-256'),
      ],
    );
  }

  Widget _infoRow(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.labelSecondary))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 15, color: AppColors.labelPrimary, fontFamily: mono ? 'monospace' : null))),
    ]),
  );
}
