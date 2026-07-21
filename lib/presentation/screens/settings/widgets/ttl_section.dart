import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/services/ttl/ttl_config.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';

/// TTL local cleanup configuration — time-based and size-based deletion rules.
class TtlSection extends ConsumerStatefulWidget {
  const TtlSection({super.key});
  @override
  ConsumerState<TtlSection> createState() => _TtlSectionState();
}

class _TtlSectionState extends ConsumerState<TtlSection> {
  bool _timeEnabled = false;
  double _timeDays = 30;
  bool _sizeEnabled = false;
  double _sizeGb = 100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ttl = ref.read(ttlEngineProvider);
    await ttl.ensureLoaded();
    final cfg = ttl.config;
    if (mounted) {
      setState(() {
        _timeEnabled = cfg.timeEnabled;
        _timeDays = cfg.timeDays.toDouble();
        _sizeEnabled = cfg.sizeEnabled;
        _sizeGb = cfg.sizeGb.toDouble();
      });
    }
  }

  Future<void> _save() async {
    await ref.read(ttlEngineProvider).updateConfig(
          TtlConfig(
            timeEnabled: _timeEnabled,
            timeDays: _timeDays.toInt(),
            sizeEnabled: _sizeEnabled,
            sizeGb: _sizeGb.toInt(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return EnpixSection(
      header: '本地清理 (TTL)',
      footer: '已上传到 S3 的本地文件，满足条件后自动删除',
      children: [
        SwitchListTile(
          title: const Text('按时间清理'),
          subtitle: Text(
            _timeEnabled ? '删除 ${_timeDays.toInt()} 天前且已上传的本地文件' : '已禁用',
          ),
          value: _timeEnabled,
          onChanged: (v) {
            setState(() => _timeEnabled = v);
            _save();
          },
        ),
        if (_timeEnabled) _buildTimeSlider(),
        const Divider(indent: AppSpacing.lg),
        SwitchListTile(
          title: const Text('按空间清理'),
          subtitle: Text(
            _sizeEnabled ? '本地空间超过 ${_sizeGb.toInt()} GB 时清理旧文件' : '已禁用',
          ),
          value: _sizeEnabled,
          onChanged: (v) {
            setState(() => _sizeEnabled = v);
            _save();
          },
        ),
        if (_sizeEnabled) _buildSizeSlider(),
      ],
    );
  }

  Widget _buildTimeSlider() => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Text(
              '${_timeDays.toInt()} 天前',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.labelSecondary,
              ),
            ),
            Expanded(
              child: Slider(
                value: _timeDays,
                min: 1,
                max: 365,
                divisions: 50,
                onChanged: (v) => setState(() => _timeDays = v),
                onChangeEnd: (_) => _save(),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${_timeDays.toInt()}天',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.labelSecondary,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSizeSlider() => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Text(
              '上限: ',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.labelSecondary,
              ),
            ),
            Expanded(
              child: Slider(
                value: _sizeGb,
                min: 5,
                max: 500,
                divisions: 99,
                onChanged: (v) => setState(() => _sizeGb = v),
                onChangeEnd: (_) => _save(),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${_sizeGb.toInt()}GB',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.labelSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}
