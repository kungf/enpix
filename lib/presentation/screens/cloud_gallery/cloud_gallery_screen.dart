import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/presentation/screens/cloud_gallery/cloud_gallery_controller.dart';
import 'package:enpix/presentation/screens/cloud_gallery/widgets/cloud_day_section.dart';
import 'package:enpix/presentation/screens/cloud_gallery/widgets/cloud_image_viewer.dart';
import 'package:enpix/presentation/screens/cloud_gallery/widgets/cloud_selection_bar.dart';
import 'package:enpix/presentation/shared/widgets/enpix_empty_state.dart';
import 'package:enpix/presentation/shared/widgets/enpix_error_state.dart';
import 'package:enpix/presentation/shared/widgets/enpix_progress.dart';
import 'package:enpix/presentation/shared/widgets/enpix_skeleton.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/cloud/cloud_providers.dart';
import 'package:enpix/services/providers.dart';

/// Cloud photo browser — encrypted thumbnails from S3, grouped by day.
///
/// Supports multi-select, permanent delete (original + thumbnail), and
/// saving decrypted photos back to the system photo library.
class CloudGalleryScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const CloudGalleryScreen({super.key, this.onNavigateToSettings});

  @override
  ConsumerState<CloudGalleryScreen> createState() => _CloudGalleryScreenState();
}

class _CloudGalleryScreenState extends ConsumerState<CloudGalleryScreen> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(cloudGalleryControllerProvider.notifier).load());
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(cloudGalleryControllerProvider.notifier).showMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudGalleryControllerProvider);
    final controller = ref.read(cloudGalleryControllerProvider.notifier);

    // Re-list when the KEK session becomes usable again — tiles decrypted
    // while locked would otherwise stay broken until a manual refresh.
    ref.listen<int>(sessionTickProvider, (previous, next) {
      if (previous == next) return;
      if (ref.read(credentialServiceProvider).isSessionActive) {
        unawaited(controller.onSessionUnlocked());
      }
    });

    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: _buildAppBar(state, controller),
      body: _buildBody(state, controller),
      bottomNavigationBar: state.isSelectionMode
          ? CloudSelectionBar(
              count: state.selectedCount,
              isWorking: state.isWorking,
              workingLabel: state.workingLabel,
              onDownload: _downloadSelected,
              onDelete: _confirmDelete,
              onCancel: controller.clearSelection,
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(
    CloudGalleryState state,
    CloudGalleryController controller,
  ) {
    if (state.isSelectionMode) {
      final visibleCount = state.days.fold<int>(
        0,
        (sum, day) => sum + day.items.length,
      );
      final allSelected = state.selectedCount >= visibleCount;
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '取消选择',
          onPressed: controller.clearSelection,
        ),
        title: Text('已选 ${state.selectedCount} 项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all_rounded),
            tooltip: '全选',
            onPressed: allSelected ? null : controller.selectAllVisible,
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('云端'),
      actions: [
        IconButton(
          icon: const Icon(Icons.checklist_rounded),
          tooltip: '选择',
          onPressed: state.days.isEmpty ? null : controller.selectAllVisible,
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '刷新',
          onPressed: state.isLoading ? null : controller.load,
        ),
      ],
    );
  }

  Widget _buildBody(
    CloudGalleryState state,
    CloudGalleryController controller,
  ) {
    if (state.isLoading || state.status == CloudGalleryStatus.idle) {
      return _buildSkeletonGrid();
    }
    if (state.hasError) {
      return EnpixErrorState(
        title: '无法加载云端照片',
        subtitle: state.errorMessage,
        onRetry: controller.load,
        extraAction: widget.onNavigateToSettings == null
            ? null
            : TextButton.icon(
                onPressed: widget.onNavigateToSettings,
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('前往设置'),
              ),
      );
    }
    if (state.days.isEmpty) {
      return const EnpixEmptyState(
        icon: Icons.cloud_queue_rounded,
        title: '还没有云端照片',
        subtitle: '在「照片」页面备份照片后，这里会显示',
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: state.days.length,
        itemBuilder: (context, index) {
          final day = state.days[index];
          return CloudDaySection(
            day: day,
            isSelectionMode: state.isSelectionMode,
            selectedKeys: state.selectedKeys,
            onTap: (media) => state.isSelectionMode
                ? controller.toggleSelection(media.thumbnailKey)
                : unawaited(_openViewer(media)),
            onLongPress: (media) =>
                controller.toggleSelection(media.thumbnailKey),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 100),
      children: [
        for (var i = 0; i < 3; i++) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                EnpixSkeleton(width: 100, height: 22),
                SizedBox(width: AppSpacing.sm),
                EnpixSkeleton(width: 30, height: 20),
              ],
            ),
          ),
          const EnpixSkeletonGrid(itemCount: 9),
        ],
      ],
    );
  }

  Future<void> _openViewer(CloudMedia media) async {
    final messenger = ScaffoldMessenger.of(context);
    final red = context.colors.brandRed;

    if (!ref.read(credentialServiceProvider).hasMasterKey) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请先在设置中设置加密密码')),
      );
      return;
    }

    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: EnpixCircularProgress()),
        ),
      ),
    );

    Future<void> closeDialog() async {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final content =
          await ref.read(cloudMediaRepositoryProvider).fetchOriginal(media);
      await closeDialog();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CloudImageViewer(data: content.bytes),
        ),
      );
    } on Exception catch (e) {
      await closeDialog();
      messenger.showSnackBar(
        SnackBar(content: Text('打开失败: $e'), backgroundColor: red),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final count = ref.read(cloudGalleryControllerProvider).selectedCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除云端照片'),
        content: Text('将删除选中的 $count 张照片及其缩略图，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.brandRed,
            ),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final red = context.colors.brandRed;
    try {
      final report = await ref
          .read(cloudGalleryControllerProvider.notifier)
          .deleteSelected();
      if (report == null) return;
      final text = report.hasFailures
          ? '已删除 ${report.deleted} 张，${report.failures.length} 张失败'
          : '已删除 ${report.deleted} 张';
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: red),
      );
    }
  }

  Future<void> _downloadSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final red = context.colors.brandRed;
    try {
      final report = await ref
          .read(cloudGalleryControllerProvider.notifier)
          .downloadSelected();
      if (report == null) return;
      final base = report.saved == 0 ? '没有照片保存成功' : '已保存 ${report.saved} 张到相册';
      final text =
          report.hasFailures ? '$base，${report.failures.length} 张失败' : base;
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: report.saved == 0 ? red : null,
        ),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: red),
      );
    }
  }
}
