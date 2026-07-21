import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'widgets/security_section.dart';
import 'widgets/upload_section.dart';
import 'widgets/ttl_section.dart';
import 'widgets/storage_section.dart';
import 'widgets/about_section.dart';

/// Settings screen — iOS 18 grouped style, composed from modular sections.
///
/// Design decisions:
/// - Thin composer: each section is its own widget file
/// - Pull-to-refresh to reload state (e.g. after passphrase change)
/// - Consistent iOS grouped card layout
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: const [
          UploadSection(),
          TtlSection(),
          SecuritySection(),
          StorageSection(),
          AboutSection(),
          SizedBox(height: AppSpacing.xxxxl),
        ],
      ),
    );
  }
}
