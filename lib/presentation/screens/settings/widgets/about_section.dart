import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';
import 'package:enpix/presentation/shared/widgets/enpix_list_tile.dart';

/// About section — app version and tech info.
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _showTechInfo = false;

  @override
  Widget build(BuildContext context) {
    return EnpixSection(
      header: '关于',
      children: [
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => _infoTile(
            '版本',
            snap.data?.version ?? '-',
            Icons.info_outline_rounded,
            context.colors.brandBlue,
          ),
        ),
        const Divider(indent: 52),
        InkWell(
          onTap: () => setState(() => _showTechInfo = !_showTechInfo),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  _showTechInfo
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: context.colors.labelSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '技术信息',
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.labelSecondary,
                  ),
                ),
              ],
            ),
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

  Widget _infoTile(String label, String value, IconData icon, Color color) =>
      EnpixListTile(
        icon: icon,
        iconColor: color,
        title: label,
        subtitle: value,
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: context.colors.labelSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: context.colors.labelPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      );
}
