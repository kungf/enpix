import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

/// Tracks uploaded files by asset ID.
/// Stores only assetId → uploadedAt mapping in iOS Keychain.
/// Other metadata (s3Key, fileName, etc.) can be computed on the fly.
class UploadTracker {
  final Logger _log = Logger('UploadTracker');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'upload_records';

  /// assetId → uploadedAt (milliseconds since epoch)
  Map<String, int> _records = {};
  bool _loaded = false;
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
      final map = jsonDecode(json) as Map<String, dynamic>;
      _records = map.map((k, v) => MapEntry(k, v as int));
    }
    _loaded = true;
    _log.info('Loaded ${_records.length} upload records from Keychain');
  }

  Future<void> _save() async {
    await _storage.write(key: _key, value: jsonEncode(_records));
  }

  /// Fast check by asset ID.
  Future<bool> isUploaded(String assetId) async {
    await _ensureLoaded();
    return _records.containsKey(assetId);
  }

  /// Mark asset as uploaded.
  Future<void> markUploaded(String assetId) async {
    await _ensureLoaded();
    _records[assetId] = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<int> get uploadedCount async { await _ensureLoaded(); return _records.length; }
  Future<Set<String>> get uploadedAssetIds async { await _ensureLoaded(); return _records.keys.toSet(); }
  Future<void> remove(String assetId) async { await _ensureLoaded(); _records.remove(assetId); await _save(); }
}
