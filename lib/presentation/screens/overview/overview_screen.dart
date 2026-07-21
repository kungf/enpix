import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/services/storage/device_list_provider.dart';
import 'package:enpix/services/storage/remote_usage_provider.dart';
import 'package:enpix/services/storage/s3_config_service.dart';

/// Dashboard overview - storage stats, backup activity, device health.
///
/// Design decisions:
/// - Real data from S3 LIST aggregation, upload tracker, and device registry
/// - iOS 18 grouped card style
/// - Pull-to-refresh invalidates providers for fresh data
/// - Informational at a glance, actionable via settings
class OverviewScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const OverviewScreen({super.key, this.onNavigateToSettings});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

/// Upload counts per day for the last 7 days, for the activity chart.
final _uploadActivityProvider = FutureProvider.autoDispose<List<int>>((ref) {
  return ref.watch(uploadTrackerProvider).countsPerDay(7);
});

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ttlEngineProvider).ensureLoaded();
    });
  }

  Future<void> _onRefresh() async {
    ref.invalidate(remoteUsageProvider);
    ref.invalidate(deviceListProvider);
    ref.invalidate(_uploadActivityProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('概览'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: [
            _StorageCard(onNavigateToSettings: widget.onNavigateToSettings),
            const SizedBox(height: AppSpacing.sm),
            const _BackupActivityCard(),
            const SizedBox(height: AppSpacing.sm),
            const _DeviceStatusCard(),
            const SizedBox(height: AppSpacing.sm),
            const _SystemStatusCard(),
            const SizedBox(height: AppSpacing.xxxxl),
          ],
        ),
      ),
    );
  }
}

// ── Storage Card ──

class _StorageCard extends ConsumerWidget {
  final VoidCallback? onNavigateToSettings;

  const _StorageCard({this.onNavigateToSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(s3ConfiguredProvider);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_rounded,
                size: 18,
                color: context.colors.brandBlue,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '存储用量',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.labelPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          configured.when(
            loading: () => const SizedBox(
              height: 28,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => _storageHint(context, '无法读取配置'),
            data: (isConfigured) => isConfigured
                ? _StorageUsage(onNavigateToSettings: onNavigateToSettings)
                : _storageHint(
                    context,
                    '未配置 S3',
                    action: onNavigateToSettings == null
                        ? null
                        : _SettingsAction(onNavigateToSettings!),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _storageHint(BuildContext context, String text, {Widget? action}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.colors.labelSecondary,
            ),
          ),
        ),
        if (action != null) action,
      ],
    );
  }
}

class _SettingsAction extends StatelessWidget {
  final VoidCallback onPressed;

  const _SettingsAction(this.onPressed);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: const Text('去配置'),
    );
  }
}

class _StorageUsage extends ConsumerWidget {
  final VoidCallback? onNavigateToSettings;

  const _StorageUsage({this.onNavigateToSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(remoteUsageProvider);
    return usage.when(
      loading: () => const SizedBox(
        height: 28,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text(
        '读取失败',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: context.colors.brandRed,
        ),
      ),
      data: (bytes) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            _formatBytes(bytes),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: context.colors.labelPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '已用',
            style: TextStyle(
              fontSize: 14,
              color: context.colors.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Backup Activity Card ──

class _BackupActivityCard extends ConsumerWidget {
  const _BackupActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(backupManagerProvider);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 18,
                color: context.colors.brandGreen,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '备份活动',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.labelPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Stats row
          Row(
            children: [
              _StatBadge(
                icon: Icons.check_circle_rounded,
                iconColor: context.colors.brandGreen,
                value: '${task.completedCount}',
                label: '已完成',
              ),
              const SizedBox(width: AppSpacing.xl),
              _StatBadge(
                icon: Icons.error_outline_rounded,
                iconColor: task.failedCount > 0
                    ? context.colors.brandRed
                    : context.colors.labelTertiary,
                value: '${task.failedCount}',
                label: '失败',
              ),
              const SizedBox(width: AppSpacing.xl),
              _StatBadge(
                icon: Icons.skip_next_rounded,
                iconColor: context.colors.labelSecondary,
                value: '${task.skippedCount}',
                label: '跳过',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ActivityBarChart(),
        ],
      ),
    );
  }
}

class _ActivityBarChart extends ConsumerWidget {
  const _ActivityBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(_uploadActivityProvider);
    return activity.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox(height: 60),
      data: (bars) {
        final total = bars.fold<int>(0, (a, b) => a + b);
        if (total == 0) {
          return SizedBox(
            height: 60,
            child: Center(
              child: Text(
                '最近 7 天暂无备份活动',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.labelTertiary,
                ),
              ),
            ),
          );
        }
        return _BarChart(bars: bars);
      },
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<int> bars;

  const _BarChart({required this.bars});

  @override
  Widget build(BuildContext context) {
    final maxVal = bars.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近 7 天',
          style: TextStyle(fontSize: 13, color: context.colors.labelSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 60,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (maxVal + 1).toDouble(),
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      const days = ['一', '二', '三', '四', '五', '六', '日'];
                      final idx = value.toInt();
                      if (idx < 0 || idx >= days.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          days[idx],
                          style: TextStyle(
                            fontSize: 10,
                            color: context.colors.labelTertiary,
                          ),
                        ),
                      );
                    },
                    reservedSize: 20,
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(bars.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: bars[i].toDouble(),
                      color: bars[i] > 0
                          ? context.colors.brandBlue
                          : context.colors.fillPrimary,
                      width: 8,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Device Status Card ──

class _DeviceStatusCard extends ConsumerWidget {
  const _DeviceStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.devices_rounded,
                size: 18,
                color: context.colors.brandPurple,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '设备',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.labelPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          devices.when(
            loading: () => const _DeviceRow(
              icon: Icons.phone_iphone_rounded,
              name: '加载中…',
              status: '',
              isCurrent: false,
            ),
            error: (_, __) => const _DeviceRow(
              icon: Icons.error_outline_rounded,
              name: '读取失败',
              status: '',
              isCurrent: false,
            ),
            data: (registry) {
              if (registry.devices.isEmpty) {
                return const _DeviceRow(
                  icon: Icons.phone_iphone_rounded,
                  name: '暂无设备',
                  status: '完成首次备份后将出现',
                  isCurrent: false,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < registry.devices.length; i++) ...[
                    if (i > 0) const Divider(indent: 0),
                    _DeviceRow(
                      icon: _deviceIcon(
                        registry.devices[i].deviceId,
                        registry.currentDeviceId,
                      ),
                      name: registry.devices[i].name,
                      status: registry.devices[i].deviceId ==
                              registry.currentDeviceId
                          ? '本机'
                          : '云端查看',
                      isCurrent: registry.devices[i].deviceId ==
                          registry.currentDeviceId,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _deviceIcon(String deviceId, String currentDeviceId) {
    if (deviceId == currentDeviceId) {
      return defaultTargetPlatform == TargetPlatform.iOS
          ? Icons.phone_iphone_rounded
          : Icons.phone_android_rounded;
    }
    return Icons.devices_rounded;
  }
}

class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String status;
  final bool isCurrent;

  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.status,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.colors.brandGray),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.labelPrimary,
                  ),
                ),
                if (status.isNotEmpty)
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.labelSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: context.colors.brandGreen.withAlpha(20),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                '当前',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.brandGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── System Status Card ──

class _SystemStatusCard extends ConsumerWidget {
  const _SystemStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credService = ref.read(credentialServiceProvider);
    final isSessionActive = credService.isSessionActive;

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_rounded,
                size: 18,
                color: context.colors.brandGray,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '系统状态',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.labelPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _StatusRow(
            icon: Icons.lock_rounded,
            label: '数据加密',
            status: isSessionActive ? '已就绪' : '未就绪',
            statusColor: isSessionActive
                ? context.colors.brandGreen
                : context.colors.brandOrange,
          ),
          const Divider(indent: 0),
          _StatusRow(
            icon: Icons.cloud_rounded,
            label: '连接状态',
            status: isSessionActive ? '已配置' : '待配置',
            statusColor: isSessionActive
                ? context.colors.labelSecondary
                : context.colors.brandOrange,
          ),
          const Divider(indent: 0),
          _StatusRow(
            icon: Icons.cleaning_services_rounded,
            label: '本地清理',
            status: '按需运行',
            statusColor: context.colors.labelSecondary,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final Color statusColor;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.brandGray),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: context.colors.labelPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(20),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Components ──

class _DashboardCard extends StatelessWidget {
  final Widget child;

  const _DashboardCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatBadge({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.colors.labelPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
