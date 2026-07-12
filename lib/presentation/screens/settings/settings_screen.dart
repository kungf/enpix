import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/core/theme/app_spacing.dart';
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
  final ValueNotifier<int>? reloadNotifier;

  const SettingsScreen({super.key, this.reloadNotifier});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.reloadNotifier?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.reloadNotifier?.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: const [
          SecuritySection(),
          UploadSection(),
          TtlSection(),
          StorageSection(),
          AboutSection(),
          SizedBox(height: AppSpacing.xxxxl),
        ],
      ),
    );
  }
}
