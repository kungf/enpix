import 'package:flutter/material.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/core/theme/app_spacing.dart';
import 'package:see_photo/services/upload/backup_task.dart';
import 'package:see_photo/services/upload/backup_manager.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_progress.dart';

/// Backup progress header — icon, title, progress text.
class ProgressHeader extends StatelessWidget {
  final BackupTask task;
  const ProgressHeader({super.key, required this.task});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 40, height: 40,
      decoration: BoxDecoration(
        color: (task.isRunning ? AppColors.brandBlue : AppColors.brandGreen).withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Icon(task.isRunning ? Icons.cloud_upload_rounded : Icons.check_circle_rounded,
          color: task.isRunning ? AppColors.brandBlue : AppColors.brandGreen, size: 24)),
    const SizedBox(width: AppSpacing.md),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(task.isRunning ? '正在备份...' : '备份完成',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.labelPrimary)),
      Text(task.progressText, style: const TextStyle(fontSize: 13, color: AppColors.labelSecondary)),
    ])),
  ]);
}

/// Bandwidth and throughput info box.
class BandwidthInfo extends StatelessWidget {
  final BackupTask task;
  const BandwidthInfo({super.key, required this.task});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.fillSecondary, borderRadius: BorderRadius.circular(AppRadius.sm)),
    child: Row(children: [
      const Icon(Icons.speed_rounded, size: 16, color: AppColors.labelSecondary),
      const SizedBox(width: AppSpacing.sm),
      Text(task.bandwidthText, style: const TextStyle(fontSize: 13, color: AppColors.labelSecondary)),
      const SizedBox(width: AppSpacing.lg),
      const Icon(Icons.upload_file_rounded, size: 16, color: AppColors.labelSecondary),
      const SizedBox(width: AppSpacing.sm),
      Text(task.throughputText, style: const TextStyle(fontSize: 13, color: AppColors.labelSecondary)),
    ]),
  );
}

/// Progress action row — error badge + stop button.
class ProgressActions extends StatelessWidget {
  final BackupTask task;
  final BackupManager manager;
  const ProgressActions({super.key, required this.task, required this.manager});

  @override
  Widget build(BuildContext context) => Row(children: [
    if (task.failedCount > 0)
      Container(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: AppColors.brandRed.withAlpha(25), borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.brandRed),
          const SizedBox(width: AppSpacing.xs),
          Text('${task.failedCount} 失败', style: const TextStyle(fontSize: 13, color: AppColors.brandRed)),
        ])),
    const Spacer(),
    TextButton.icon(
      onPressed: () { manager.stop(); Navigator.pop(context); },
      icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('停止')),
  ]);
}

/// Expandable error list with report button.
class ErrorList extends StatefulWidget {
  final List<String> errors;
  final Future<void> Function()? onReport;
  const ErrorList({super.key, required this.errors, this.onReport});
  @override
  State<ErrorList> createState() => _ErrorListState();
}

class _ErrorListState extends State<ErrorList> {
  bool _expanded = false;
  bool _reporting = false;

  @override
  Widget build(BuildContext context) => Column(children: [
    InkWell(onTap: () => setState(() => _expanded = !_expanded), child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.brandRed),
        const SizedBox(width: AppSpacing.sm),
        Text('查看失败详情 (${widget.errors.length})',
            style: const TextStyle(fontSize: 13, color: AppColors.brandRed)),
        const Spacer(),
        Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18, color: AppColors.labelSecondary),
      ]),
    )),
    if (_expanded) ...[
      Container(constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(color: AppColors.brandRed.withAlpha(15), borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: ListView.separated(shrinkWrap: true, padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: widget.errors.length, separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (_, i) => Text(widget.errors[i],
              style: const TextStyle(fontSize: 12, color: AppColors.brandRed)))),
      const SizedBox(height: AppSpacing.sm),
      Align(alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _reporting ? null : () async {
            setState(() => _reporting = true);
            try { await widget.onReport?.call(); } finally { if (mounted) setState(() => _reporting = false); }
          },
          icon: _reporting ? const EnpixCircularProgress(size: 14) : const Icon(Icons.bug_report_outlined, size: 16),
          label: Text(_reporting ? '上传中...' : 'Report'))),
    ],
  ]);
}
