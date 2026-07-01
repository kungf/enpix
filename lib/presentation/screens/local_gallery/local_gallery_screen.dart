import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/providers.dart';
import '../../../domain/entities/storage_config.dart';

/// Local photo browser — shows device photos grouped by day, like the Photos app.
class LocalGalleryScreen extends ConsumerStatefulWidget {
  const LocalGalleryScreen({super.key});

  @override
  ConsumerState<LocalGalleryScreen> createState() => _LocalGalleryScreenState();
}

class _LocalGalleryScreenState extends ConsumerState<LocalGalleryScreen> {
  bool _hasPermission = false;
  bool _loadingPermission = true;
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 60;

  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _error = false;
  String _errorMsg = '';
  final ScrollController _scrollCtrl = ScrollController();

  // ── Grouped data ──
  late List<_DaySection> _sections = [];

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

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
      final albums = await PhotoManager.getAssetPathList(type: RequestType.common, hasAll: true);
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
      final assets = await _album!.getAssetListPaged(page: _page, size: _pageSize);
      if (assets.isEmpty || assets.length < _pageSize) _hasMore = false;
      _assets.addAll(assets);
      _page++;
      _rebuildSections();
    } on Exception catch (e) {
      _error = true;
      _errorMsg = e.toString();
    }
    setState(() => _loading = false);
  }

  void _rebuildSections() {
    final Map<String, List<AssetEntity>> groups = {};
    int globalIndex = 0;

    for (final asset in _assets) {
      final date = asset.createDateTime;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(asset);
    }

    // Sort by date descending (newest first)
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    _sections = [];
    for (final key in sortedKeys) {
      final assets = groups[key]!;
      final startIndex = _assets.indexOf(assets.first);
      _sections.add(_DaySection(
        dateKey: key,
        label: _formatDateLabel(key),
        assets: assets,
        globalStartIndex: startIndex,
      ));
    }
  }

  String _formatDateLabel(String key) {
    final parts = key.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
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
    setState(() { _selected.clear(); _selectionMode = false; });
  }

  int _findGlobalIndex(AssetEntity asset) => _assets.indexOf(asset);

  void _openViewer(AssetEntity asset) {
    final idx = _findGlobalIndex(asset);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoViewer(assets: _assets, initialIndex: idx),
    ));
  }

  void _scrollToTop() {
    _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // ── Upload tracker ──
  final Set<String> _uploadedIds = {};

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUploadedIds() async {
    final ids = await ref.read(uploadTrackerProvider).uploadedAssetIds;
    if (mounted) setState(() => _uploadedIds.addAll(ids));
  }

  /// Configure S3 service from saved credentials. Returns false if config is incomplete.
  Future<bool> _configureS3() async {
    final credService = ref.read(credentialServiceProvider);
    final s3Creds = await credService.loadS3Credentials();
    if (!mounted) return false;
    if (s3Creds == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中配置 S3 存储')));
      return false;
    }

    final endpointUrl = await credService.getS3Endpoint() ?? '';
    final bucketName = await credService.getS3Bucket() ?? '';
    final region = await credService.getS3Region() ?? 'default';

    if (endpointUrl.isEmpty || bucketName.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('S3 配置不完整，请检查设置')));
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

  Future<void> _startForceBackup() async {
    final credService = ref.read(credentialServiceProvider);
    final manager = ref.read(backupManagerProvider.notifier);

    if (ref.read(backupManagerProvider).isRunning) {
      _showBackupProgress();
      return;
    }

    if (!credService.isSessionActive) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中解锁密钥')));
      return;
    }

    if (!await _configureS3()) return;
    await manager.startForceFull();

    final ids = await ref.read(uploadTrackerProvider).uploadedAssetIds;
    if (mounted) setState(() => _uploadedIds.addAll(ids));
  }

  Future<void> _startBackup() async {
    final credService = ref.read(credentialServiceProvider);
    final manager = ref.read(backupManagerProvider.notifier);

    if (ref.read(backupManagerProvider).isRunning) {
      _showBackupProgress();
      return;
    }

    if (!credService.isSessionActive) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中解锁密钥')));
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
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final task = ref.watch(backupManagerProvider);
          final manager = ref.read(backupManagerProvider.notifier);
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Icon(task.isRunning ? Icons.cloud_upload_rounded : Icons.check_circle_rounded,
                    color: task.isRunning ? Colors.green : Colors.grey),
                const SizedBox(width: 12),
                Text(task.isRunning ? '正在备份...' : '备份完成', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(task.progressText, style: const TextStyle(color: Colors.grey)),
              ]),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: task.progress),
              if (task.currentFileName != null) ...[
                const SizedBox(height: 12),
                Text(task.currentFileName!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                _stat(Icons.check_rounded, Colors.green, '${task.completedCount} 成功'),
                const SizedBox(width: 16),
                _stat(Icons.skip_next_rounded, Colors.orange, '${task.skippedCount} 跳过'),
                const SizedBox(width: 16),
                _stat(Icons.error_outline_rounded, Colors.red, '${task.failedCount} 失败'),
                const Spacer(),
                if (task.isRunning)
                  TextButton.icon(
                    onPressed: () { manager.stop(); Navigator.pop(context); },
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('停止'),
                  )
                else
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _stat(IconData icon, Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: color)),
    ]);
  }

  Widget _buildFab() {
    final task = ref.watch(backupManagerProvider);

    if (task.isRunning) {
      return FloatingActionButton.extended(
        onPressed: _showBackupProgress,
        backgroundColor: Colors.green,
        icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
        label: Text(task.progressText, style: const TextStyle(color: Colors.white)),
      );
    }

    if (task.isDone) {
      return FloatingActionButton.extended(
        onPressed: _showBackupProgress,
        backgroundColor: task.failedCount > 0 ? Colors.orange : Colors.green,
        icon: Icon(
          task.failedCount > 0 ? Icons.warning_rounded : Icons.check_rounded,
          color: Colors.white,
        ),
        label: Text(
          task.failedCount > 0 ? '${task.failedCount} 失败' : '完成',
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onLongPress: _startForceBackup,
      child: FloatingActionButton.extended(
        onPressed: _startBackup,
        icon: const Icon(Icons.cloud_upload_rounded),
        label: const Text('备份'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地'),
        centerTitle: false,
        actions: _selectionMode
            ? [Text('已选 ${_selected.length}'), IconButton(icon: const Icon(Icons.close_rounded), onPressed: _exitSelection)]
            : null,
      ),
      body: _buildBody(),
      floatingActionButton: _hasPermission && (_assets.isNotEmpty || AppConstants.isIntegrationTest)
          ? _buildFab()
          : null,
    );
  }

  Widget _buildBody() {
    if (_loadingPermission) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('无法加载照片', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(_errorMsg, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _requestPermission, child: const Text('重试')),
        ],
      )));
    }
    if (!_hasPermission) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('需要照片访问权限', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('请在设置中允许 Enpix 访问照片', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _requestPermission, child: const Text('授权')),
        ],
      )));
    }
    if (_assets.isEmpty && !_loading) return const Center(child: Text('没有照片'));

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification && n.metrics.pixels >= n.metrics.maxScrollExtent - 500) _loadMore();
        return false;
      },
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _sections.length + (_loading ? 1 : 0),
        itemBuilder: (context, sectionIndex) {
          if (sectionIndex >= _sections.length) {
            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final section = _sections[sectionIndex];
          return _DaySectionWidget(
            section: section,
            selectionMode: _selectionMode,
            isSelected: (id) => _selected.contains(id),
            onTap: (asset) {
              if (_selectionMode) {
                _toggleSelection(asset.id);
              } else {
                _openViewer(asset);
              }
            },
            onLongPress: (asset) => _toggleSelection(asset.id),
          );
        },
      ),
    );
  }
}

// ── Data model ──

class _DaySection {
  final String dateKey;
  final String label;
  final List<AssetEntity> assets;
  final int globalStartIndex;

  const _DaySection({required this.dateKey, required this.label, required this.assets, required this.globalStartIndex});
}

// ── Section widget ──

class _DaySectionWidget extends StatelessWidget {
  final _DaySection section;
  final bool selectionMode;
  final bool Function(String id) isSelected;
  final void Function(AssetEntity) onTap;
  final void Function(AssetEntity) onLongPress;

  const _DaySectionWidget({required this.section, required this.selectionMode, required this.isSelected, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
          child: Text(section.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        ),
        // Photo grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: section.assets.length,
          itemBuilder: (context, index) {
            final asset = section.assets[index];
            return _AssetThumb(
              asset: asset,
              selected: isSelected(asset.id),
              onTap: () => onTap(asset),
              onLongPress: () => onLongPress(asset),
            );
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
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _AssetThumb({required this.asset, this.selected = false, this.onTap, this.onLongPress});

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
    final data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(256, 256), format: ThumbnailFormat.jpeg);
    if (mounted) setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: _thumb != null ? Image.memory(_thumb!, fit: BoxFit.cover) : Container(color: Colors.grey.shade200),
        ),
        if (widget.asset.type == AssetType.video)
          Positioned(bottom: 4, left: 4, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
              Text('${widget.asset.duration}s', style: const TextStyle(color: Colors.white, fontSize: 10)),
            ]),
          )),
        if (widget.selected)
          Container(
            decoration: BoxDecoration(color: Colors.blue.withAlpha(60), border: Border.all(color: Colors.blue, width: 2), borderRadius: BorderRadius.circular(2)),
            child: const Align(alignment: Alignment.topRight,
              child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.check_circle_rounded, color: Colors.blue, size: 22)),
            ),
          ),
      ]),
    );
  }
}

// ── Full screen viewer ──

class _FullResImage extends StatefulWidget {
  final AssetEntity asset;
  const _FullResImage({required this.asset});

  @override
  State<_FullResImage> createState() => _FullResImageState();
}

class _FullResImageState extends State<_FullResImage> {
  Uint8List? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await widget.asset.originFile;
      if (file != null && file.existsSync()) {
        _data = await file.readAsBytes();
      } else {
        _data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(2048, 2048), format: ThumbnailFormat.jpeg);
      }
    } catch (_) {
      _data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(1024, 1024), format: ThumbnailFormat.jpeg);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white54));
    if (_data != null) return Image.memory(_data!, fit: BoxFit.contain);
    return const Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38);
  }
}

class _PhotoViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;

  const _PhotoViewer({required this.assets, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late PageController _pageCtrl;
  late int _currentIndex;
  bool _showBar = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        GestureDetector(
          onTap: () => setState(() => _showBar = !_showBar),
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.assets.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, index) => InteractiveViewer(
              minScale: 0.5, maxScale: 5.0,
              child: Center(child: _FullResImage(asset: widget.assets[index])),
            ),
          ),
        ),
        if (_showBar)
          Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false, child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)),
              const Spacer(),
              Text('${_currentIndex + 1} / ${widget.assets.length}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const Spacer(),
            ]),
          ))),
      ]),
    );
  }
}
