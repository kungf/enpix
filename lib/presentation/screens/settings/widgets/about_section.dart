import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/app_colors.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';
import 'package:enpix/presentation/shared/widgets/enpix_list_tile.dart';

/// About section — app version and KEK fingerprint.
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _showTechInfo = false;
  Future<String?>? _cachedFingerprint;

  @override
  void initState() {
    super.initState();
    _cachedFingerprint = ref.read(credentialServiceProvider).getKekFingerprint();
  }

  @override
  Widget build(BuildContext context) {
    return EnpixSection(
      header: '关于',
      children: [
        _infoTile('版本', '0.1.0', Icons.info_outline_rounded, AppColors.brandBlue),
        FutureBuilder<String?>(
          future: _cachedFingerprint,
          builder: (_, s) => _infoTile('KEK 指纹', s.data?.substring(0, 12) ?? '—', Icons.fingerprint_rounded, AppColors.brandGray),
        ),
        const Divider(indent: 52),
        InkWell(
          onTap: () => setState(() => _showTechInfo = !_showTechInfo),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Row(children: [
              Icon(_showTechInfo ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20, color: AppColors.labelSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text('技术信息', style: const TextStyle(fontSize: 15, color: AppColors.labelSecondary)),
            ]),
          ),
        ),
        if (_showTechInfo) ...[
          _infoRow('加密', 'XChaCha20-Poly1305'),
          _infoRow('密钥派生', 'Argon2id (64 MiB)'),
          _infoRow('哈希', 'BLAKE2b-256'),
        ],
      ],
    );
  }

  Widget _infoTile(String label, String value, IconData icon, Color color) => EnpixListTile(
    icon: icon, iconColor: color,
    title: label, subtitle: value,
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.labelSecondary))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 15, color: AppColors.labelPrimary, fontFamily: 'monospace'))),
    ]),
  );
}
