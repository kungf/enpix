import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Local file-based cache for decrypted thumbnail JPEGs.
///
/// Thumbnails are stored as plaintext JPEG files (already decrypted).
/// Cache location: {appTempDir}/thumbnails/{assetId}.jpg
class ThumbnailCache {
  final Logger _log = Logger('ThumbnailCache');
  Directory? _cacheDir;

  Future<Directory> _ensureDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getTemporaryDirectory();
    _cacheDir = Directory(p.join(base.path, 'thumbnails'));
    if (!_cacheDir!.existsSync()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  String _fileName(String assetId) => '$assetId.jpg';

  /// Save a decrypted thumbnail JPEG to local cache.
  Future<void> save(String assetId, Uint8List jpegData) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, _fileName(assetId)));
    await file.writeAsBytes(jpegData, flush: true);
    _log.fine('Cached thumbnail: ${file.path} (${jpegData.length} bytes)');
  }

  /// Load a cached thumbnail. Returns null if not cached.
  Future<Uint8List?> load(String assetId) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, _fileName(assetId)));
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  /// Check if a thumbnail is cached locally.
  Future<bool> has(String assetId) async {
    final dir = await _ensureDir();
    return File(p.join(dir.path, _fileName(assetId))).existsSync();
  }

  /// Delete a single cached thumbnail.
  Future<void> delete(String assetId) async {
    final dir = await _ensureDir();
    final file = File(p.join(dir.path, _fileName(assetId)));
    if (file.existsSync()) await file.delete();
  }

  /// Clear all cached thumbnails.
  Future<void> clear() async {
    final dir = await _ensureDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      _cacheDir = null;
      _log.info('Thumbnail cache cleared');
    }
  }

  /// Total cache size in bytes.
  Future<int> sizeInBytes() async {
    final dir = await _ensureDir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
