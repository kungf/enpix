import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:see_photo/core/constants/app_constants.dart';
import 'package:see_photo/core/theme/app_colors.dart';
import 'package:see_photo/core/theme/app_spacing.dart';
import 'package:see_photo/services/providers.dart';
import 'package:see_photo/domain/entities/storage_config.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_loading_state.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_empty_state.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_error_state.dart';
import 'package:see_photo/presentation/shared/widgets/enpix_progress.dart';
import 'package:see_photo/presentation/shared/widgets/photo_viewer.dart';
import 'package:see_photo/presentation/shared/widgets/backup_progress_widgets.dart';
import 'package:see_photo/services/upload/backup_task.dart';

/// Local photo browser — device photos grouped by day.
///
/// Design decisions:
/// - Type filter chips at top for photos/videos/all
/// - Date headers with count indicator
/// - 3-column grid with selection and upload status
/// - Long-press selection with visual feedback
/// - Immersive photo viewer with EXIF info
/// - Skeleton loading states
class LocalGalleryScreen extends ConsumerStatefulWidget {
  const LocalGalleryScreen({super.key});

  @override
  ConsumerState<LocalGalleryScreen> createState() => _LocalGalleryScreenState();
}

class _LocalGalleryScreenState extends ConsumerState<LocalGalleryScreen>
    with SingleTickerProviderStateMixin {
  // ── Permission & Data ──
  bool _hasPermission = false;
  bool _loadingPermission = true;
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 60;
  bool _error = false;
  String _errorMsg = '';
  final ScrollController _scrollCtrl = ScrollController();

  // ── Selection ──
  final Set<String> _selected = {};
  bool _selectionMode = false;

  // ── Filter ──
  String _filter = 'all';
  final Set<String> _uploadedIds = {};

  // ── Sectioned data ──
  late List<_DaySection> _sections = [];

  @override
  void initState() {
    super.initState();
    _requestPermission();
    // Reset backup state when task completes — avoids side-effect in build().
    ref.listenManual(backupManagerProvider, (prev, next) {
      if (prev?.isDone != true && next.isDone) {
        // Delay reset so the completion animation plays.
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) ref.read(backupManagerProvider.notifier).reset();
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Permission ──

  Future<void> _requestPermission() async {
    setState(() => _loadingPermission = true);
    try {
      if (AppConstants.isIntegrationTest) {
        _hasPermission = true;
        await _loadUploadedIds();
        setState(() => _loadingPermission = false);
        return;
      }

      final state = await PhotoManager.requestPermissionExtend();
      _hasPermission = state.isAuth || state.hasAccess;
      if (_hasPermission) {
        await _loadAlbum();
        await _loadUploadedIds();
      }
    } on Exception catch (e) {
      _error = true;
      _errorMsg = e.toString();
    }
    setState(() => _loadingPermission = false);
  }

  Future<void> _loadAlbum() async {
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
      );
      if (albums.isEmpty) return;
      _album = albums.first;
      await _loadMore();
    } on Exception catch (e) {
      _error = true;
      _errorMsg = e.toString();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _album == null) return;
    setState(() => _loading = true);
    try {
      final assets = await _album!.getAssetListPaged(
        page: _page,
        size: _pageSize,
      );
      if (assets.isEmpty || assets.length < _pageSize) _hasMore = false;
      _assets.addAll(assets);
      _page++;
      _rebuildSections();
    } on Exception catch (e) {
      _error = true;
      _errorMsg = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Upload tracker ──

  Future<void> _loadUploadedIds() async {
    final ids = await ref.read(uploadTrackerProvider).uploadedAssetIds;
    if (mounted) setState(() => _uploadedIds.addAll(ids));
  }

  // ── S3 config helper ──

  Future<bool> _configureS3() async {
    final credService = ref.read(credentialServiceProvider);
    final s3Creds = await credService.loadS3Credentials();
    if (!mounted) return false;
    if (s3Creds == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 S3 存储')),
      );
      return false;
    }

    final endpointUrl = await credService.getS3Endpoint() ?? '';
    final bucketName = await credService.getS3Bucket() ?? '';
    final region = await credService.getS3Region() ?? 'default';

    if (endpointUrl.isEmpty || bucketName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('S3 配置不完整，请检查设置')),
        );
      }
      return false;
    }

    final deviceId = await ref.read(deviceServiceProvider).getDeviceId();
    ref.read(s3ServiceProvider).configure(
          StorageConfig(
            endpointUrl: endpointUrl,
            bucketName: bucketName,
            region: region,
            accessKey: s3Creds.accessKey,
            secretKey: s3Creds.secretKey,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          kekFingerprint: await credService.getKekFingerprint(),
          deviceId: deviceId,
        );
    return true;
  }

  // ── Backup actions ──

  Future<void> _startBackup() async {
    final credService = ref.read(credentialServiceProvider);
    final manager = ref.read(backupManagerProvider.notifier);
    if (ref.read(backupManagerProvider).isRunning) {
      _showBackupProgress();
      return;
    }
    if (!credService.isSessionActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中解锁密钥')),
        );
      }
      return;
    }
    if (!await _configureS3()) return;
    await manager.startFull();
    final ids = await ref.read(uploadTrackerProvider).uploadedAssetIds;
    if (mounted) setState(() => _uploadedIds.addAll(ids));
  }

  void _showBackupProgress() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final task = ref.watch(backupManagerProvider);
          final manager = ref.read(backupManagerProvider.notifier);
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.separatorOpaque,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProgressHeader(task: task),
                        const SizedBox(height: AppSpacing.xl),
                        EnpixLinearProgress(value: task.progress),
                        if (task.currentFileName != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(task.currentFileName!,
                              style: const TextStyle(
                                  color: AppColors.labelSecondary,
                                  fontSize: 13)),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        if (task.isRunning || task.totalBytes > 0)
                          BandwidthInfo(task: task),
                        const SizedBox(height: AppSpacing.xl),
                        ProgressActions(task: task, manager: manager),
                        if (task.errors.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(),
                          const SizedBox(height: AppSpacing.lg),
                          ErrorList(
                              errors: task.errors,
                              onReport: () async {
                                try {
                                  await manager.reportErrors(task.errors);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('错误报告已上传'),
                                          backgroundColor:
                                              AppColors.brandGreen),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('上传失败: $e')));
                                }
                              }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      ref.read(backupManagerProvider.notifier).reset();
    });
  }

  // ── Section builder ──

  void _rebuildSections() {
    final Map<String, List<AssetEntity>> groups = {};
    for (final asset in _assets) {
      if (_filter == 'photos' && asset.type != AssetType.image) continue;
      if (_filter == 'videos' && asset.type != AssetType.video) continue;
      final date = asset.createDateTime;
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(asset);
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    _sections = [];
    for (final key in sortedKeys) {
      final assets = groups[key]!;
      _sections.add(_DaySection(
        dateKey: key,
        label: _formatDateLabel(key),
        assets: assets,
      ));
    }
  }

  String _formatDateLabel(String key) {
    final parts = key.split('-');
    final date =
        DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '今天';
    if (d == yesterday) return '昨天';
    return '${date.year}年${date.month}月${date.day}日';
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
        _selectionMode = true;
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  void _openViewer(AssetEntity asset) {
    final idx = _assets.indexOf(asset);
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            PhotoViewer(assets: _assets, initialIndex: idx),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: AppDuration.normal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('照片'),
        actions: _selectionMode
            ? [
                _SelectionCount(count: _selected.length),
                IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _exitSelection),
              ]
            : null,
      ),
      body: _buildBody(),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildBody() {
    if (_loadingPermission)
      return const EnpixLoadingState(message: '正在加载照片...');
    if (_error)
      return EnpixErrorState(
          title: '无法加载照片', subtitle: _errorMsg, onRetry: _requestPermission);
    if (!_hasPermission) {
      return EnpixEmptyState(
        icon: Icons.photo_library_outlined,
        title: '需要照片访问权限',
        subtitle: '请在设置中允许 Enpix 访问照片',
        action: FilledButton(
            onPressed: _requestPermission, child: const Text('授权')),
      );
    }
    if (_assets.isEmpty && !_loading) {
      return const EnpixEmptyState(
          icon: Icons.photo_library_outlined,
          title: '还没有照片',
          subtitle: '拍摄照片后会显示在这里');
    }

    return Column(
      children: [
        _TypeFilter(
            current: _filter,
            onChanged: (v) {
              setState(() => _filter = v);
              _rebuildSections();
            }),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 500)
                _loadMore();
              return false;
            },
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: _sections.length + (_loading ? 1 : 0),
              itemBuilder: (context, sectionIndex) {
                if (sectionIndex >= _sections.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: EnpixCircularProgress()),
                  );
                }
                final section = _sections[sectionIndex];
                return _DaySectionWidget(
                  section: section,
                  selectionMode: _selectionMode,
                  isSelected: (id) => _selected.contains(id),
                  uploadedIds: _uploadedIds,
                  onTap: (asset) {
                    _selectionMode
                        ? _toggleSelection(asset.id)
                        : _openViewer(asset);
                  },
                  onLongPress: (asset) => _toggleSelection(asset.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildFab() {
    if (!_hasPermission) return null;
    final task = ref.watch(backupManagerProvider);
    if (task.isRunning || task.isDone) {
      return _AnimatedBackupFab(task: task, onTap: _showBackupProgress);
    }
    if (_assets.isEmpty) return null;
    return FloatingActionButton(
      onPressed: _startBackup,
      backgroundColor: AppColors.brandBlue,
      child:
          const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 24),
    );
  }
}

// ── Data model ──

class _DaySection {
  final String dateKey;
  final String label;
  final List<AssetEntity> assets;
  const _DaySection(
      {required this.dateKey, required this.label, required this.assets});
}

// ── Type filter chips ──

class _TypeFilter extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _TypeFilter({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', '全部', Icons.grid_view_rounded),
      ('photos', '照片', Icons.photo_rounded),
      ('videos', '视频', Icons.videocam_rounded),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        children: filters.map((f) {
          final (key, label, icon) = f;
          final s = current == key;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              selected: s,
              avatar: Icon(icon,
                  size: 16,
                  color: s ? AppColors.brandBlue : AppColors.labelSecondary),
              label: Text(label),
              onSelected: (_) => onChanged(key),
              selectedColor: AppColors.brandBlue.withAlpha(25),
              labelStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: s ? FontWeight.w600 : FontWeight.w500,
                  color: s ? AppColors.brandBlue : AppColors.labelPrimary),
              showCheckmark: false,
              side: BorderSide.none,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Section widget ──

class _DaySectionWidget extends StatelessWidget {
  final _DaySection section;
  final bool selectionMode;
  final bool Function(String id) isSelected;
  final Set<String> uploadedIds;
  final void Function(AssetEntity) onTap;
  final void Function(AssetEntity) onLongPress;

  const _DaySectionWidget(
      {required this.section,
      required this.selectionMode,
      required this.isSelected,
      required this.uploadedIds,
      required this.onTap,
      required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              Text(section.label,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.labelPrimary,
                      letterSpacing: -0.5)),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                    color: AppColors.fillSecondary,
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Text('${section.assets.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.labelSecondary)),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: section.assets.length,
          itemBuilder: (context, index) {
            final asset = section.assets[index];
            return _AssetThumb(
                asset: asset,
                selected: isSelected(asset.id),
                isUploaded: uploadedIds.contains(asset.id),
                onTap: () => onTap(asset),
                onLongPress: () => onLongPress(asset));
          },
        ),
      ],
    );
  }
}

// ── Thumbnail widget ──

class _AssetThumb extends StatefulWidget {
  final AssetEntity asset;
  final bool selected;
  final bool isUploaded;
  final VoidCallback? onTap, onLongPress;
  const _AssetThumb(
      {required this.asset,
      this.selected = false,
      this.isUploaded = false,
      this.onTap,
      this.onLongPress});
  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(256, 256),
        format: ThumbnailFormat.jpeg);
    if (mounted) setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xxs),
              child: _thumb != null
                  ? Image.memory(_thumb!, fit: BoxFit.cover)
                  : Container(color: AppColors.fillSecondary)),
          if (widget.asset.type == AssetType.video)
            Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(3)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.play_arrow_rounded,
                        size: 14, color: Colors.white),
                    Text('${widget.asset.duration}s',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10)),
                  ]),
                )),
          if (widget.isUploaded && !widget.selected)
            Positioned(
                top: 4,
                right: 4,
                child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: AppColors.brandGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.cloud_done_rounded,
                        size: 10, color: Colors.white))),
          if (widget.selected)
            Container(
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withAlpha(60),
                border: Border.all(color: AppColors.brandBlue, width: 2),
                borderRadius: BorderRadius.circular(AppRadius.xxs),
              ),
              child: const Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check_circle_rounded,
                        color: AppColors.brandBlue, size: 22),
                  )),
            ),
        ],
      ),
    );
  }
}

// ── Animated FAB ──

/// Floating action button with animated upload arrow + progress arc + completion bounce.
///
/// States:
/// - **idle**: blue FAB + cloud upload icon (handled by caller)
/// - **running**: **green** FAB + cloud icon + arrow sliding upward (continuous flow) + progress arc
/// - **completed**: green FAB + checkmark with elastic bounce-in
class _AnimatedBackupFab extends StatefulWidget {
  final BackupTask task;
  final VoidCallback onTap;
  const _AnimatedBackupFab({required this.task, required this.onTap});

  @override
  State<_AnimatedBackupFab> createState() => _AnimatedBackupFabState();
}

class _AnimatedBackupFabState extends State<_AnimatedBackupFab>
    with TickerProviderStateMixin {
  late AnimationController _arrowCtrl;
  late AnimationController _doneCtrl;
  late Animation<double> _doneScale;
  late Animation<double> _arrowOffset;
  late Animation<double> _arrowOpacity;
  bool _wasDone = false;
  bool _showCheckmark = false;

  @override
  void initState() {
    super.initState();

    // Arrow: slides from bottom of cloud to top, fading out, then resets.
    _arrowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _arrowOffset = Tween(begin: 10.0, end: -10.0).animate(
      CurvedAnimation(parent: _arrowCtrl, curve: Curves.easeOut),
    );
    _arrowOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _arrowCtrl,
          curve: const Interval(0.3, 0.9, curve: Curves.easeOut)),
    );

    // Done: elastic bounce-in
    _doneCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _doneScale = CurvedAnimation(parent: _doneCtrl, curve: Curves.easeOutBack);

    if (widget.task.isRunning) _arrowCtrl.repeat();
    _wasDone = widget.task.isDone;
    if (_wasDone && widget.task.status == BackupStatus.completed) {
      _showCheckmark = true;
      _doneCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(_AnimatedBackupFab old) {
    super.didUpdateWidget(old);

    final justCompleted = !_wasDone &&
        widget.task.isDone &&
        widget.task.status == BackupStatus.completed;
    final justStarted = !_wasDone &&
        widget.task.isRunning &&
        (!old.task.isRunning || old.task.isDone);

    if (justCompleted) {
      _arrowCtrl.stop();
      _arrowCtrl.reset();
      _showCheckmark = true;
      _doneCtrl.forward(from: 0.0);
    } else if (justStarted) {
      _showCheckmark = false;
      _arrowCtrl.repeat();
    }

    _wasDone = widget.task.isDone;
  }

  @override
  void dispose() {
    _arrowCtrl.dispose();
    _doneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGreen = widget.task.isRunning || _showCheckmark;
    return FloatingActionButton(
      onPressed: widget.onTap,
      backgroundColor: isGreen ? AppColors.brandGreen : AppColors.brandBlue,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Progress arc ring ──
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: widget.task.progress,
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withAlpha(35),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),

          // ── Running: cloud + animated upward arrow ──
          if (widget.task.isRunning)
            SizedBox(
              width: 22,
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: Icon(Icons.cloud_rounded,
                        color: Colors.white, size: 22),
                  ),
                  // Arrow A — slides from bottom to top
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _arrowCtrl,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _arrowOffset.value),
                          child: Opacity(
                            opacity: _arrowOpacity.value,
                            child: const Icon(Icons.arrow_upward_rounded,
                                color: Colors.white, size: 12),
                          ),
                        );
                      },
                    ),
                  ),
                  // Arrow B — half-cycle offset for continuous feel
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _arrowCtrl,
                      builder: (context, child) {
                        // Phase-shifted: starts disappearing as A begins
                        final t = (_arrowCtrl.value + 0.5) % 1.0;
                        final offset = 10.0 - 20.0 * t;
                        final opacity = t < 0.3
                            ? 1.0
                            : (t < 0.9 ? 1.0 - (t - 0.3) / 0.6 : 0.0);
                        return Transform.translate(
                          offset: Offset(0, offset),
                          child: Opacity(
                            opacity: opacity,
                            child: const Icon(Icons.arrow_upward_rounded,
                                color: Colors.white, size: 12),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // ── Completed: checkmark bounce ──
          if (_showCheckmark)
            AnimatedBuilder(
              animation: _doneScale,
              builder: (context, child) {
                return Transform.scale(
                  scale: _doneScale.value,
                  child: const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 22),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SelectionCount extends StatelessWidget {
  final int count;
  const _SelectionCount({required this.count});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
              color: AppColors.brandBlue.withAlpha(25),
              borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Text('已选 $count',
              style: const TextStyle(
                  color: AppColors.brandBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ),
      );
}
