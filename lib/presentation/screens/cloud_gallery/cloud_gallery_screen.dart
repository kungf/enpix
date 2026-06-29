import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/crypto/credential_service.dart';
import '../../../services/crypto/crypto_service.dart';
import '../../../services/storage/s3_service.dart';
import '../../../services/cache/thumbnail_cache.dart';
import '../../../services/providers.dart';
import '../../../domain/entities/storage_config.dart';

/// Cloud photo browser — shows encrypted thumbnails from S3, grouped by day.
class CloudGalleryScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const CloudGalleryScreen({super.key, this.onNavigateToSettings});

  @override
  ConsumerState<CloudGalleryScreen> createState() => _CloudGalleryScreenState();
}

class _CloudGalleryScreenState extends ConsumerState<CloudGalleryScreen> {
  bool _loading = false;
  bool _error = false;
  bool _needPassphrase = false;
  String _errorMsg = '';
  List<_CloudDaySection> _sections = [];
  String? _prefix;

  @override
  void initState() {
    super.initState();
    _loadCloudThumbs();
  }

  Future<void> _loadCloudThumbs() async {
    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      final credService = ref.read(credentialServiceProvider);
      final s3 = ref.read(s3ServiceProvider);
      final cache = ref.read(thumbnailCacheProvider);

      if (!s3.isConfigured) {
        if (!credService.isSessionActive) {
          setState(() {
            _loading = false;
            _error = true;
            _needPassphrase = true;
          });
          return;
        }

        final s3Creds = await credService.loadS3Credentials();
        if (s3Creds == null) {
          setState(() {
            _loading = false;
            _error = true;
            _errorMsg = '请先在设置中配置 S3 存储';
          });
          return;
        }

        final endpointUrl = await credService.getS3Endpoint() ?? '';
        final bucketName = await credService.getS3Bucket() ?? '';
        final region = await credService.getS3Region() ?? 'us-east-1';
        final fingerprint = await credService.getKekFingerprint();

        if (endpointUrl.isEmpty || bucketName.isEmpty) {
          setState(() {
            _loading = false;
            _error = true;
            _errorMsg = 'S3 配置不完整，请检查设置';
          });
          return;
        }

        s3.configure(
          StorageConfig(
            endpointUrl: endpointUrl,
            bucketName: bucketName,
            region: region,
            accessKey: s3Creds.accessKey,
            secretKey: s3Creds.secretKey,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          kekFingerprint: fingerprint,
        );
      }

      // List all thumbnails from S3
      _prefix = s3.makeThumbKey('').replaceAll(RegExp(r'[^/]*$'), '');
      final objects = await s3.listObjects(_prefix!);

      // Sort by key descending (newest first, UUIDv7 is time-ordered)
      objects.sort((a, b) => b.key.compareTo(a.key));

      // Build sections
      final Map<String, List<_CloudThumb>> groups = {};

      for (final obj in objects) {
        final fileId = _extractFileId(obj.key);
        if (fileId == null) continue;

        final cached = await cache.load(fileId);
        final date = _parseUuidv7Date(fileId);
        final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        groups.putIfAbsent(dateKey, () => []);
        groups[dateKey]!.add(_CloudThumb(
          fileId: fileId,
          s3Key: obj.key,
          cachedData: cached,
          createdAt: date,
        ));
      }

      final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

      setState(() {
        _sections = sortedKeys.map((key) {
          final date = DateTime.parse(key);
          return _CloudDaySection(
            dateKey: key,
            label: _formatDateLabel(date),
            thumbs: groups[key]!,
          );
        }).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = true;
        _errorMsg = e.toString();
      });
    }
  }

  /// Extract fileId from S3 key: {prefix}/thumbs/{fileId}_thumb.enc
  String? _extractFileId(String key) {
    final parts = key.split('/');
    if (parts.isEmpty) return null;
    final fileName = parts.last;
    if (!fileName.endsWith('_thumb.enc')) return null;
    return fileName.replaceAll('_thumb.enc', '');
  }

  /// Parse date from UUIDv7 timestamp prefix.
  DateTime _parseUuidv7Date(String uuid) {
    try {
      final hex = uuid.replaceAll('-', '').substring(0, 12);
      final millis = int.parse(hex, radix: 16);
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return DateTime.now();
    }
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

  /// Load a thumbnail — from cache or download + decrypt from S3.
  Future<Uint8List?> _loadThumb(_CloudThumb thumb) async {
    if (thumb.cachedData != null) return thumb.cachedData;

    try {
      final s3 = ref.read(s3ServiceProvider);
      final crypto = ref.read(cryptoServiceProvider);
      final credService = ref.read(credentialServiceProvider);
      final cache = ref.read(thumbnailCacheProvider);

      if (!credService.isSessionActive) return null;

      final encrypted = await s3.getObject(thumb.s3Key);
      final meta = await s3.headObject(thumb.s3Key);
      final dekB64 = meta['x-amz-meta-dek'];
      final nonceB64 = meta['x-amz-meta-nonce'];

      if (dekB64 == null || nonceB64 == null) return null;

      final wrappedDek = CryptoService.b64Decode(dekB64);
      final kek = credService.sessionKek!;
      final dek = await crypto.unwrapKey(wrappedDek, kek);
      final decrypted = await crypto.decrypt(encrypted, dek);
      crypto.secureFree(dek);

      await cache.save(thumb.fileId, decrypted);
      return decrypted;
    } catch (e) {
      return null;
    }
  }

  /// Download and view a full-resolution image.
  Future<void> _openFullImage(_CloudThumb thumb) async {
    try {
      final s3 = ref.read(s3ServiceProvider);
      final crypto = ref.read(cryptoServiceProvider);
      final credService = ref.read(credentialServiceProvider);

      if (!credService.isSessionActive) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先在设置中创建加密密码')),
          );
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
      }

      final fingerprint = await credService.getKekFingerprint() ?? 'shared';
      final fullKey = S3Service.generateKey(fingerprint, thumb.fileId, thumb.createdAt);

      final encrypted = await s3.getObject(fullKey);
      final meta = await s3.headObject(fullKey);
      final dekB64 = meta['x-amz-meta-dek'];

      if (dekB64 == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final wrappedDek = CryptoService.b64Decode(dekB64);
      final kek = credService.sessionKek!;
      final dek = await crypto.unwrapKey(wrappedDek, kek);
      final decrypted = await crypto.decrypt(encrypted, dek);
      crypto.secureFree(dek);

      if (mounted) {
        Navigator.pop(context);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FullScreenImage(data: decrypted),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('云端'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCloudThumbs,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _needPassphrase ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
                size: 48,
                color: _needPassphrase ? Colors.orange : Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _needPassphrase ? '需要设置加密密钥' : '无法加载云端照片',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _needPassphrase
                    ? 'Enpix 使用端到端加密保护你的照片\n请前往 设置 → 安全 中创建加密密码'
                    : _errorMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),
              if (_needPassphrase)
                FilledButton.icon(
                  onPressed: widget.onNavigateToSettings,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('前往设置'),
                )
              else
                FilledButton(onPressed: _loadCloudThumbs, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_sections.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_queue_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('还没有云端照片', style: TextStyle(fontSize: 16, color: Colors.grey)),
            SizedBox(height: 8),
            Text('在「本地」页面备份照片后，这里会显示', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCloudThumbs,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
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
}

// ── Data models ──

class _CloudThumb {
  final String fileId;
  final String s3Key;
  final Uint8List? cachedData;
  final DateTime createdAt;

  const _CloudThumb({
    required this.fileId,
    required this.s3Key,
    this.cachedData,
    required this.createdAt,
  });
}

class _CloudDaySection {
  final String dateKey;
  final String label;
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
          child: Text(
            section.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
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
          itemBuilder: (context, index) {
            return _CloudThumbWidget(
              thumb: section.thumbs[index],
              loadThumb: loadThumb,
              onTap: () => onTap(section.thumbs[index]),
            );
          },
        ),
      ],
    );
  }
}

// ── Thumbnail widget ──

class _CloudThumbWidget extends StatefulWidget {
  final _CloudThumb thumb;
  final Future<Uint8List?> Function(_CloudThumb) loadThumb;
  final VoidCallback onTap;

  const _CloudThumbWidget({
    required this.thumb,
    required this.loadThumb,
    required this.onTap,
  });

  @override
  State<_CloudThumbWidget> createState() => _CloudThumbWidgetState();
}

class _CloudThumbWidgetState extends State<_CloudThumbWidget> {
  Uint8List? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.loadThumb(widget.thumb);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: _loading
            ? Container(color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : _data != null
                ? Image.memory(_data!, fit: BoxFit.cover)
                : Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 32),
                  ),
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
