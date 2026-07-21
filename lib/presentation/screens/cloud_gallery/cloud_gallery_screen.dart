import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';
import 'package:enpix/services/storage/s3_config_service.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/services/thumbnail/thumbnail_loader.dart';
import 'package:enpix/presentation/shared/widgets/enpix_empty_state.dart';
import 'package:enpix/presentation/shared/widgets/enpix_error_state.dart';
import 'package:enpix/presentation/shared/widgets/enpix_progress.dart';
import 'package:enpix/presentation/shared/widgets/enpix_skeleton.dart';

/// Cloud photo browser — encrypted thumbnails from S3, grouped by day.
///
/// Design decisions:
/// - Skeleton loading for placeholder UX
/// - Device selector as horizontal scroll pills
/// - Encryption badge on each thumbnail
/// - Pull-to-refresh
/// - Scroll pagination (30 day batches)
class CloudGalleryScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const CloudGalleryScreen({super.key, this.onNavigateToSettings});

  @override
  ConsumerState<CloudGalleryScreen> createState() => _CloudGalleryScreenState();
}

class _CloudGalleryScreenState extends ConsumerState<CloudGalleryScreen> {
  static const _selectedDeviceKey = 'cloud_selected_device_id';
  static const _allDevicesId = '__all__';

  bool _loading = false;
  bool _error = false;
  bool _needPassphrase = false;
  String _errorMsg = '';
  List<_CloudDaySection> _allSections = [];
  List<_CloudDaySection> _sections = [];
  String? _prefix;
  int _visibleDays = 30;
  final ScrollController _scrollCtrl = ScrollController();

  Map<String, DeviceInfo> _devices = {};
  String _selectedDeviceId = _allDevicesId;
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    final current = _sections.length;
    final total = _allSections.length;
    if (current >= total) return;
    final next = (current + 30).clamp(0, total);
    if (next == current) return;
    setState(() {
      _visibleDays = next;
      _updateVisibleSections();
    });
  }

  void _updateVisibleSections() {
    _sections = _allSections.take(_visibleDays).toList();
  }

  Future<void> _init() async {
    const storage = FlutterSecureStorage();
    final saved = await storage.read(key: _selectedDeviceKey);
    if (saved != null) _selectedDeviceId = saved;

    _currentDeviceId = await ref.read(deviceServiceProvider).getDeviceId();
    if (saved == null) _selectedDeviceId = _currentDeviceId!;

    await _loadCloudThumbs();
  }

  Future<void> _loadCloudThumbs() async {
    setState(() {
      _loading = true;
      _error = false;
      _needPassphrase = false;
      _visibleDays = 30;
      _allSections = [];
      _sections = [];
    });

    try {
      final credService = ref.read(credentialServiceProvider);
      final s3 = ref.read(s3ServiceProvider);

      final configResult =
          await ref.read(s3ConfigServiceProvider).ensureConfigured();
      if (configResult != S3ConfigResult.configured) {
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = configResult == S3ConfigResult.missingEndpoint
              ? '请先在设置中配置 S3 Endpoint 和 Bucket'
              : '请先在设置中配置 Access Key 和 Secret Key';
        });
        return;
      }

      final fingerprint = await credService.getKekFingerprint() ?? 'shared';
      final fpPrefix =
          fingerprint.length >= 12 ? fingerprint.substring(0, 12) : 'shared';

      final devices = await s3.listDevices();
      _devices = devices;

      List<S3Object> objects;
      if (_selectedDeviceId == _allDevicesId) {
        _prefix = '$fpPrefix/';
        final allObjects = await s3.listObjects(_prefix!);
        objects = allObjects.where((o) => o.key.contains('/thumbs/')).toList();
      } else {
        _prefix = '$_selectedDeviceId/thumbs/';
        objects = await s3.listObjects('$fpPrefix/$_prefix');
      }
      objects.sort((a, b) => b.key.compareTo(a.key));

      final Map<String, List<_CloudThumb>> groups = {};
      for (final obj in objects) {
        final fileId = _extractFileId(obj.key);
        if (fileId == null) continue;
        final deviceId = _extractDeviceId(obj.key);
        final date = _extractDateFromKey(obj.key);
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        groups.putIfAbsent(dateKey, () => []);
        groups[dateKey]!.add(
          _CloudThumb(
            fileId: fileId,
            s3Key: obj.key,
            createdAt: date,
            deviceId: deviceId,
          ),
        );
      }

      final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
      if (!mounted) return;
      setState(() {
        _allSections = sortedKeys.map((key) {
          final date = DateTime.parse(key);
          return _CloudDaySection(
            dateKey: key,
            label: _formatDateLabel(date),
            thumbs: groups[key]!,
          );
        }).toList();
        _updateVisibleSections();
        _loading = false;
      });
    } catch (e) {
      developer.log('_loadCloudThumbs error: $e', name: 'CloudGallery');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _errorMsg = e.toString();
      });
    }
  }

  String? _extractFileId(String key) {
    final parts = key.split('/');
    if (parts.isEmpty) return null;
    final fileName = parts.last;
    if (!fileName.endsWith('_thumb.enc')) return null;
    return fileName.replaceAll('_thumb.enc', '');
  }

  String _extractDeviceId(String key) {
    final parts = key.split('/');
    return parts.length >= 2 ? parts[1] : 'default';
  }

  DateTime _extractDateFromKey(String key) {
    try {
      final parts = key.split('/');
      for (final part in parts) {
        if (part.length == 8 && int.tryParse(part) != null) {
          final year = int.parse(part.substring(0, 4));
          final month = int.parse(part.substring(4, 6));
          final day = int.parse(part.substring(6, 8));
          if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            return DateTime(year, month, day);
          }
        }
      }
    } catch (_) {}
    return DateTime.now();
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '今天';
    if (d == yesterday) return '昨天';
    return '${date.year}年${date.month}月${date.day}日';
  }

  Future<Uint8List?> _loadThumb(_CloudThumb thumb) async {
    try {
      final s3 = ref.read(s3ServiceProvider);
      final crypto = ref.read(cryptoServiceProvider);
      final credService = ref.read(credentialServiceProvider);
      final cache = ref.read(thumbnailCacheProvider);
      if (!credService.hasMasterKey) return null;
      final encrypted = await s3.getObject(thumb.s3Key);
      final meta = await s3.headObject(thumb.s3Key);
      final dekB64 = meta['x-amz-meta-dek'];
      final nonceB64 = meta['x-amz-meta-nonce'];
      if (dekB64 == null || nonceB64 == null) return null;
      final wrappedDek = CryptoService.b64Decode(dekB64);
      final masterKey = credService.sessionMasterKey!;
      final dek = await crypto.unwrapKey(wrappedDek, masterKey);
      final decrypted = await crypto.decrypt(encrypted, dek);
      crypto.secureFree(dek);
      await cache.save(thumb.fileId, decrypted);
      return decrypted;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openFullImage(_CloudThumb thumb) async {
    try {
      final s3 = ref.read(s3ServiceProvider);
      final crypto = ref.read(cryptoServiceProvider);
      final credService = ref.read(credentialServiceProvider);
      if (!credService.hasMasterKey) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请先在设置中设置加密密码')));
        }
        return;
      }
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: EnpixCircularProgress()),
        );
      }

      final fingerprint = await credService.getKekFingerprint() ?? 'shared';
      final fullKey = S3Service.generateKey(
        fingerprint,
        thumb.fileId,
        thumb.createdAt,
        deviceId: thumb.deviceId,
      );
      final encrypted = await s3.getObject(fullKey);
      final meta = await s3.headObject(fullKey);
      final dekB64 = meta['x-amz-meta-dek'];
      if (dekB64 == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final wrappedDek = CryptoService.b64Decode(dekB64);
      final masterKey = credService.sessionMasterKey!;
      final dek = await crypto.unwrapKey(wrappedDek, masterKey);
      final decrypted = await crypto.decrypt(encrypted, dek);
      crypto.secureFree(dek);

      if (mounted) {
        Navigator.pop(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _FullScreenImage(data: decrypted),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: context.colors.brandRed,
          ),
        );
      }
    }
  }

  Future<void> _saveSelectedDevice(String deviceId) async {
    await const FlutterSecureStorage()
        .write(key: _selectedDeviceKey, value: deviceId);
  }

  void _onDeviceSelected(String deviceId) {
    setState(() {
      _selectedDeviceId = deviceId;
      _sections = [];
    });
    _saveSelectedDevice(deviceId);
    _loadCloudThumbs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('云端'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCloudThumbs,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_devices.isNotEmpty) _buildDeviceSelector(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector() {
    return Container(
      height: 48,
      color: context.colors.backgroundSecondary,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        children: [
          _deviceChip(_allDevicesId, '全部', Icons.devices_rounded),
          ..._devices.entries.map(
            (e) => _deviceChip(
              e.key,
              e.value.name,
              e.key == _currentDeviceId
                  ? Icons.phone_iphone_rounded
                  : Icons.phone_android_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceChip(String deviceId, String label, IconData icon) {
    final selected = _selectedDeviceId == deviceId;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        selected: selected,
        avatar: Icon(
          icon,
          size: 16,
          color: selected
              ? context.colors.brandBlue
              : context.colors.labelSecondary,
        ),
        label: Text(label),
        onSelected: (_) => _onDeviceSelected(deviceId),
        selectedColor: context.colors.brandBlue.withAlpha(25),
        labelStyle: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color:
              selected ? context.colors.brandBlue : context.colors.labelPrimary,
        ),
        showCheckmark: false,
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeletonGrid();
    if (_needPassphrase &&
        ref.read(credentialServiceProvider).isSessionActive) {
      _needPassphrase = false;
      _error = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCloudThumbs());
      return _buildSkeletonGrid();
    }
    if (_error) {
      if (_needPassphrase) {
        return EnpixEmptyState(
          icon: Icons.lock_outline_rounded,
          title: '需要设置加密密码',
          subtitle: 'Enpix 使用端到端加密保护你的照片\n请前往设置 → 数据加密中设置密码',
          action: FilledButton.icon(
            onPressed: widget.onNavigateToSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('前往设置'),
          ),
        );
      }
      return EnpixErrorState(
        title: '无法加载云端照片',
        subtitle: _errorMsg,
        onRetry: _loadCloudThumbs,
        extraAction: TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _errorMsg));
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('错误信息已复制')));
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('复制错误'),
        ),
      );
    }
    if (_sections.isEmpty) {
      return const EnpixEmptyState(
        icon: Icons.cloud_queue_rounded,
        title: '还没有云端照片',
        subtitle: '在「照片」页面备份照片后，这里会显示',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCloudThumbs,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _sections.length,
        itemBuilder: (context, sectionIndex) {
          final section = _sections[sectionIndex];
          return _CloudDaySectionWidget(
            section: section,
            loadThumb: _loadThumb,
            onTap: _openFullImage,
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
}

// ── Data models ──

class _CloudThumb {
  final String fileId, s3Key, deviceId;
  final DateTime createdAt;
  const _CloudThumb({
    required this.fileId,
    required this.s3Key,
    required this.createdAt,
    required this.deviceId,
  });
}

class _CloudDaySection {
  final String dateKey, label;
  final List<_CloudThumb> thumbs;
  const _CloudDaySection({
    required this.dateKey,
    required this.label,
    required this.thumbs,
  });
}

// ── Section widget ──

class _CloudDaySectionWidget extends StatelessWidget {
  final _CloudDaySection section;
  final Future<Uint8List?> Function(_CloudThumb) loadThumb;
  final void Function(_CloudThumb) onTap;
  const _CloudDaySectionWidget({
    required this.section,
    required this.loadThumb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                section.label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.colors.labelPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: context.colors.fillSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_rounded,
                      size: 12,
                      color: context.colors.labelSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '${section.thumbs.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.labelSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: section.thumbs.length,
          itemBuilder: (context, index) => _CloudThumbWidget(
            thumb: section.thumbs[index],
            loadThumb: loadThumb,
            onTap: () => onTap(section.thumbs[index]),
          ),
        ),
      ],
    );
  }
}

// ── Thumbnail widget with encryption badge ──

class _CloudThumbWidget extends ConsumerStatefulWidget {
  final _CloudThumb thumb;
  final Future<Uint8List?> Function(_CloudThumb) loadThumb;
  final VoidCallback onTap;
  const _CloudThumbWidget({
    required this.thumb,
    required this.loadThumb,
    required this.onTap,
  });
  @override
  ConsumerState<_CloudThumbWidget> createState() => _CloudThumbWidgetState();
}

class _CloudThumbWidgetState extends ConsumerState<_CloudThumbWidget> {
  Uint8List? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ref.read(cloudThumbnailLoaderProvider).load(
          widget.thumb.s3Key,
          () => widget.loadThumb(widget.thumb),
        );
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // When the fetch failed, tap retries instead of opening the viewer.
    final failed = !_loading && _data == null;
    return GestureDetector(
      onTap: _loading ? null : (failed ? _load : widget.onTap),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xxs),
            child: _loading
                ? const EnpixSkeleton(width: 200, height: 200)
                : _data != null
                    ? Image.memory(_data!, fit: BoxFit.cover)
                    : Container(
                        color: context.colors.fillSecondary,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: context.colors.brandGray,
                          size: 32,
                        ),
                      ),
          ),
          // Encryption badge
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: context.colors.brandPurple.withAlpha(180),
                borderRadius: BorderRadius.circular(AppRadius.xxs),
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full screen image viewer ──

class _FullScreenImage extends StatelessWidget {
  final Uint8List data;
  const _FullScreenImage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.memory(data, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
