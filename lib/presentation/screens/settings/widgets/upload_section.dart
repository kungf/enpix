import 'package:flutter/material.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/core/theme/app_spacing.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_section.dart';

/// Upload configuration section — delay threshold, WiFi-only toggle.
class UploadSection extends StatefulWidget {
  const UploadSection({super.key});
  @override
  State<UploadSection> createState() => _UploadSectionState();
}

class _UploadSectionState extends State<UploadSection> {
  bool _enabled = true;
  double _delayDays = 0;
  bool _unitHours = false;
  bool _wifiOnly = true;

  @override
  Widget build(BuildContext context) {
    return EnpixSection(
      header: '上传配置',
      footer: '仅上传拍摄时间超过阈值的照片，0 为不限',
      children: [
        SwitchListTile(
          title: const Text('上传阈值'),
          subtitle: Text(_enabled
              ? (_delayDays == 0 ? '不限' : '仅上传 ${_delayDays.toInt()} ${_unitHours ? '小时' : '天'}前拍摄的照片')
              : '已禁用'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        if (_enabled) _buildDelaySlider(),
        const Divider(indent: AppSpacing.lg),
        SwitchListTile(
          title: const Text('仅 WiFi 上传'),
          value: _wifiOnly,
          onChanged: (v) => setState(() => _wifiOnly = v),
        ),
      ],
    );
  }

  Widget _buildDelaySlider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Text('拍摄于 ${_delayDays.toInt()} ${_unitHours ? '小时' : '天'}前',
                  style: const TextStyle(fontSize: 13, color: AppColors.labelSecondary)),
              const Spacer(),
              _UnitSegment(
                isHours: _unitHours,
                onChanged: (hours) => setState(() {
                  _unitHours = hours;
                  if (hours && _delayDays > 72) _delayDays = 72;
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Slider(value: _delayDays, min: 0, max: _unitHours ? 72 : 365, divisions: _unitHours ? 72 : 73,
            onChanged: (v) => setState(() => _delayDays = v)),
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
        color: AppColors.fillPrimary,
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
          color: selected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.labelPrimary,
          ),
        ),
      ),
    );
  }
}
