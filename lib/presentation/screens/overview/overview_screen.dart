import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/services/providers.dart';

/// Dashboard overview — storage stats, backup activity, device health.
///
/// Design decisions:
/// - fl_chart visualizations for storage and activity
/// - iOS 18 grouped card style
/// - Pull-to-refresh for real-time data
/// - Informational at a glance, actionable via settings
class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ttlEngineProvider).ensureLoaded();
    });
  }

  Future<void> _onRefresh() async {
    setState(() {});
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
            _StorageCard(),
            const SizedBox(height: AppSpacing.sm),
            _BackupActivityCard(),
            const SizedBox(height: AppSpacing.sm),
            _DeviceStatusCard(),
            const SizedBox(height: AppSpacing.sm),
            _SystemStatusCard(),
            const SizedBox(height: AppSpacing.xxxxl),
          ],
        ),
      ),
    );
  }
}

// ── Storage Card ──

class _StorageCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(backupManagerProvider);
    final totalBytes = task.totalBytes;
    final usedGb = totalBytes / (1024 * 1024 * 1024);
    final displayUsed = usedGb > 0 ? usedGb.toStringAsFixed(1) : '0';
    final percentage = (usedGb / 50.0).clamp(0.0, 1.0);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_rounded, size: 18, color: context.colors.brandBlue),
              SizedBox(width: AppSpacing.sm),
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
          Row(
            children: [
              // Donut chart
              SizedBox(
                width: 100,
                height: 100,
                child: PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        value: percentage * 100,
                        color: context.colors.brandBlue,
                        radius: 22,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: (1 - percentage) * 100,
                        color: context.colors.fillPrimary,
                        radius: 22,
                        showTitle: false,
                      ),
                    ],
                    sectionsSpace: 0,
                    centerSpaceRadius: 32,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$displayUsed GB',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.colors.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '已用 / 总计 50 GB',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.colors.labelSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    EnpixMiniProgress(value: percentage),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Backup Activity Card ──

class _BackupActivityCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(backupManagerProvider);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 18, color: context.colors.brandGreen),
              SizedBox(width: AppSpacing.sm),
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
          if (task.totalCount > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            _MiniBarChart(),
          ],
        ],
      ),
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  // Placeholder activity data for the last 7 days
  final List<int> bars = const [3, 1, 0, 5, 2, 4, 1];

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
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(show: false),
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.devices_rounded, size: 18, color: context.colors.brandPurple),
              SizedBox(width: AppSpacing.sm),
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
          _DeviceRow(
            icon: Icons.phone_iphone_rounded,
            name: '本机',
            status: '已注册',
            isCurrent: true,
          ),
          const Divider(indent: 0),
          _DeviceRow(
            icon: Icons.phone_android_rounded,
            name: '其他设备',
            status: '云端查看',
            isCurrent: false,
          ),
        ],
      ),
    );
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
              Icon(Icons.info_rounded, size: 18, color: context.colors.brandGray),
              SizedBox(width: AppSpacing.sm),
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
            statusColor:
                isSessionActive ? context.colors.brandGreen : context.colors.brandOrange,
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

class EnpixMiniProgress extends StatelessWidget {
  final double value;

  const EnpixMiniProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: context.colors.fillPrimary,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.colors.brandBlue, context.colors.brandTeal],
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
