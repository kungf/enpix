import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

/// Tracks uploaded files by asset ID.
/// Stores asset IDs in iOS Keychain as a JSON array.
/// Memory-efficient: uses Set<String> instead of Map.
class UploadTracker {
  final Logger _log = Logger('UploadTracker');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'upload_records';

  Set<String> _uploaded = {};
  bool _loaded = false;
  bool _dirty = false;
  Future<void>? _loadFuture;

  Future<void> _ensureLoaded() async {
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
    final json = await _storage.read(key: _key);
    if (json != null) {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        // New format: ["assetId1", "assetId2"]
        _uploaded = decoded.cast<String>().toSet();
      } else if (decoded is Map) {
        // Migration from old format: {"assetId": timestamp}
        _uploaded = decoded.keys.toSet();
        _dirty = true; // Re-save in new format
        _log.info('Migrated ${_uploaded.length} records from old format');
      }
    }
    _loaded = true;
    _log.info('Loaded ${_uploaded.length} upload records from Keychain');
  }

  /// Persist to Keychain. Call after batch operations.
  Future<void> save() async {
    if (!_dirty) return;
    await _storage.write(key: _key, value: jsonEncode(_uploaded.toList()));
    _dirty = false;
    _log.info('Saved ${_uploaded.length} upload records');
  }

  /// Fast check by asset ID.
  Future<bool> isUploaded(String assetId) async {
    await _ensureLoaded();
    return _uploaded.contains(assetId);
  }

  /// Mark asset as uploaded. Does NOT persist immediately — call save() after batch.
  Future<void> markUploaded(String assetId) async {
    await _ensureLoaded();
    _uploaded.add(assetId);
    _dirty = true;
  }

  Future<int> get uploadedCount async { await _ensureLoaded(); return _uploaded.length; }
  Future<Set<String>> get uploadedAssetIds async { await _ensureLoaded(); return Set.of(_uploaded); }
  Future<void> remove(String assetId) async {
    await _ensureLoaded();
    _uploaded.remove(assetId);
    await save();
  }

  /// Clear all upload records — triggers full re-upload on next backup.
  Future<void> clear() async {
    _uploaded = {};
    _dirty = true;
    await save();
    _log.info('Upload records cleared');
  }
}
