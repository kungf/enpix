import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import '../upload/upload_tracker.dart';
import 'ttl_config.dart';

/// Automatic local cleanup engine.
///
/// Deletes device photos that have been backed up to S3 and exceed the
/// configured TTL (time-to-live). Two strategies:
///
/// - **Time-based**: delete backed-up photos older than N days.
/// - **Size-based**: when total size of backed-up local photos exceeds N GB,
///   delete the oldest backed-up photos (1 GiB per run).
///
/// Upload tracker records are preserved so the cloud gallery can still
/// display deleted photos.
class TtlEngine {
  final UploadTracker _tracker;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Logger _log = Logger('TtlEngine');
  static const _configKey = 'ttl_config';
  static const _lastRunKey = 'ttl_last_run';
  static const _minRunInterval = Duration(hours: 6);

  TtlConfig _config = const TtlConfig();
  bool _loaded = false;
  Future<void>? _loadFuture;

  TtlEngine(this._tracker);

  /// Current TTL configuration.
  TtlConfig get config => _config;

  // ── Config persistence ──

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    if (_loadFuture != null) {
      await _loadFuture;
      return;
    }
    _loadFuture = _doLoad();
    await _loadFuture;
    _loadFuture = null;
  }

  Future<void> _doLoad() async {
    final json = await _storage.read(key: _configKey);
    if (json != null) {
      _config = TtlConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }
    _loaded = true;
    _log.info('Loaded TTL config: $_config');
  }

  Future<void> updateConfig(TtlConfig config) async {
    _config = config;
    await _storage.write(key: _configKey, value: jsonEncode(config.toJson()));
    _log.info('Saved TTL config: $_config');
  }

  // ── Run control ──

  /// Run the TTL engine. Skips if disabled or ran recently.
  /// Returns the number of deleted photos.
  Future<int> run() async {
    await ensureLoaded();
    if (!_config.isEnabled) {
      _log.fine('TTL disabled, skipping');
      return 0;
    }

    if (await _ranRecently()) {
      _log.fine('TTL ran recently, skipping');
      return 0;
    }

    _log.info('Starting TTL cleanup: $_config');
    int deleted = 0;

    if (_config.timeEnabled) {
      deleted += await _runTimeBased();
    }
    if (_config.sizeEnabled) {
      deleted += await _runSizeBased();
    }

    await _markRan();
    _log.info('TTL cleanup done: $deleted photos deleted');
    return deleted;
  }

  Future<bool> _ranRecently() async {
    try {
      final ts = await _storage.read(key: _lastRunKey);
      if (ts == null) return false;
      final lastRun = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      return DateTime.now().difference(lastRun) < _minRunInterval;
    } catch (e) {
      _log.warning('Failed to read last run time, allowing run: $e');
      return false;
    }
  }

  Future<void> _markRan() async {
    await _storage.write(
      key: _lastRunKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  // ── Time-based cleanup ──

  Future<int> _runTimeBased() async {
    final cutoff = DateTime.now().subtract(Duration(days: _config.timeDays));
    _log.info('Time-based: deleting backed-up photos older than '
        '${_config.timeDays} days (before $cutoff)');

    final uploadedIds = await _tracker.uploadedAssetIds;
    if (uploadedIds.isEmpty) return 0;

    final assets = await _getAssetsByIds(uploadedIds);
    final toDelete = <AssetEntity>[];
    for (final asset in assets) {
      if (asset.createDateTime.isBefore(cutoff)) {
        toDelete.add(asset);
      }
    }

    if (toDelete.isEmpty) {
      _log.info('No photos older than ${_config.timeDays} days');
      return 0;
    }

    _log.info('Found ${toDelete.length} photos to delete');
    return await _deleteAssets(toDelete);
  }

  // ── Size-based cleanup ──

  Future<int> _runSizeBased() async {
    _log.info('Size-based: checking backed-up photo size '
        '(limit: ${_config.sizeGb} GB)');

    final uploadedIds = await _tracker.uploadedAssetIds;
    if (uploadedIds.isEmpty) return 0;

    final assets = await _getAssetsByIds(uploadedIds);
    if (assets.isEmpty) return 0;

    // Calculate total size of backed-up photos still on device.
    int totalBytes = 0;
    final assetsWithSize = <(AssetEntity, int)>[];
    for (final asset in assets) {
      final file = await asset.originFile;
      if (file == null) continue;
      final size = await file.length();
      totalBytes += size;
      assetsWithSize.add((asset, size));
    }

    final limitBytes = _config.sizeGb * 1024 * 1024 * 1024;
    if (totalBytes <= limitBytes) {
      _log.info('Backed-up photos ${_formatBytes(totalBytes)} is under limit');
      return 0;
    }

    _log.info('Backed-up photos ${_formatBytes(totalBytes)} exceeds limit, '
        'cleaning up 1 GiB');

    // Sort by creation date (oldest first), delete until 1 GiB freed.
    assetsWithSize.sort(
      (a, b) => a.$1.createDateTime.compareTo(b.$1.createDateTime),
    );

    const targetFree = 1024 * 1024 * 1024; // 1 GiB
    int freed = 0;
    final toDelete = <AssetEntity>[];
    for (final (asset, size) in assetsWithSize) {
      if (freed >= targetFree) break;
      freed += size;
      toDelete.add(asset);
    }

    if (toDelete.isEmpty) return 0;

    _log.info('Deleting ${toDelete.length} photos to free '
        '${_formatBytes(freed)}');
    return await _deleteAssets(toDelete);
  }

  // ── Helpers ──

  /// Look up AssetEntities by their IDs from the photo library.
  /// Scans all albums to find assets regardless of which album they're in.
  Future<List<AssetEntity>> _getAssetsByIds(Set<String> ids) async {
    final result = <AssetEntity>[];
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
    );
    if (albums.isEmpty) return result;

    const pageSize = 200;
    for (final album in albums) {
      int page = 0;
      while (true) {
        final assets = await album.getAssetListPaged(
          page: page,
          size: pageSize,
        );
        if (assets.isEmpty) break;
        for (final asset in assets) {
          if (ids.contains(asset.id)) {
            result.add(asset);
          }
        }
        if (result.length >= ids.length) break;
        page++;
      }
      if (result.length >= ids.length) break;
    }

    _log.fine('Found ${result.length}/${ids.length} assets in photo library');
    return result;
  }

  /// Delete assets from the device. Does NOT remove upload tracker records.
  Future<int> _deleteAssets(List<AssetEntity> assets) async {
    final ids = assets.map((a) => a.id).toList();
    try {
      final result = await PhotoManager.editor.deleteWithIds(ids);
      final deleted = result.length;
      _log.info('Deleted $deleted/${assets.length} photos from device');
      if (deleted < assets.length) {
        _log.warning(
          'Some photos could not be deleted '
          '(${assets.length - deleted} failed)',
        );
      }
      return deleted;
    } catch (e) {
      _log.severe('Failed to delete assets: $e');
      return 0;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
