import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';
import 'package:enpix/services/settings/upload_settings.dart';
import 'package:enpix/services/settings/upload_settings_provider.dart';

/// Upload configuration section - delay threshold, WiFi-only toggle.
///
/// State is persisted via [uploadSettingsProvider] (Keychain JSON) and written
/// through immediately on every change.
class UploadSection extends ConsumerWidget {
  const UploadSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(uploadSettingsProvider);
    final notifier = ref.read(uploadSettingsProvider.notifier);

    return EnpixSection(
      header: '上传配置',
      footer: '仅上传拍摄时间超过阈值的照片，0 为不限',
      children: [
        SwitchListTile(
          title: const Text('上传阈值'),
          subtitle: Text(
            settings.thresholdEnabled
                ? (settings.thresholdValue == 0
                    ? '不限'
                    : '仅上传 ${settings.thresholdValue.toInt()} ${settings.unitHours ? '小时' : '天'}前拍摄的照片')
                : '已禁用',
          ),
          value: settings.thresholdEnabled,
          onChanged: notifier.setThresholdEnabled,
        ),
        if (settings.thresholdEnabled)
          _buildDelaySlider(context, settings, notifier),
        const Divider(indent: AppSpacing.lg),
        SwitchListTile(
          title: const Text('仅 WiFi 上传'),
          value: settings.wifiOnly,
          onChanged: notifier.setWifiOnly,
        ),
      ],
    );
  }

  Widget _buildDelaySlider(
    BuildContext context,
    UploadSettings settings,
    UploadSettingsNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '拍摄于 ${settings.thresholdValue.toInt()} ${settings.unitHours ? '小时' : '天'}前',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.labelSecondary,
                ),
              ),
              const Spacer(),
              _UnitSegment(
                isHours: settings.unitHours,
                onChanged: (hours) {
                  notifier.setUnitHours(hours);
                  if (hours && settings.thresholdValue > 72) {
                    notifier.setThresholdValue(72);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Slider(
            value: settings.thresholdValue,
            min: 0,
            max: settings.unitHours ? 72 : 365,
            divisions: settings.unitHours ? 72 : 73,
            onChanged: notifier.setThresholdValue,
          ),
        ],
      ),
    );
  }
}

/// iOS 18-style inline segmented toggle for hours/days unit selection.
class _UnitSegment extends StatelessWidget {
  final bool isHours;
  final ValueChanged<bool> onChanged;

  const _UnitSegment({required this.isHours, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: context.colors.fillPrimary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UnitSegmentButton(
            label: '小时',
            selected: isHours,
            onTap: () => onChanged(true),
          ),
          _UnitSegmentButton(
            label: '天',
            selected: !isHours,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _UnitSegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _UnitSegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        padding: EdgeInsets.zero,
        alignment: Alignment.center,
        height: 28,
        decoration: BoxDecoration(
          color: selected ? context.colors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.colors.labelPrimary,
          ),
        ),
      ),
    );
  }
}
