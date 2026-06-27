import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

/// Tracks uploaded files by asset ID.
/// Stored in iOS Keychain — survives system cleanup and app reinstall.
class UploadTracker {
  final Logger _log = Logger('UploadTracker');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'upload_records';

  Map<String, _UploadRecord> _records = {};
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
      _records = map.map((k, v) => MapEntry(k, _UploadRecord.fromJson(v as Map<String, dynamic>)));
    }
    _loaded = true;
    _log.info('Loaded ${_records.length} upload records from Keychain');
  }

  Future<void> _save() async {
    final json = _records.map((k, v) => MapEntry(k, v.toJson()));
    await _storage.write(key: _key, value: jsonEncode(json));
  }

  /// Fast check by asset ID.
  Future<bool> isUploaded(String assetId) async {
    await _ensureLoaded();
    return _records.containsKey(assetId);
  }

  /// Get S3 key for an uploaded asset.
  Future<String?> getS3Key(String assetId) async {
    await _ensureLoaded();
    return _records[assetId]?.s3Key;
  }

  /// Mark asset as uploaded.
  Future<void> markUploaded({
    required String assetId,
    required String s3Key,
    required String fileName,
    String? contentHash,
  }) async {
    await _ensureLoaded();
    _records[assetId] = _UploadRecord(
      s3Key: s3Key,
      fileName: fileName,
      contentHash: contentHash,
      uploadedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _save();
  }

  Future<int> get uploadedCount async { await _ensureLoaded(); return _records.length; }
  Future<Set<String>> get uploadedAssetIds async { await _ensureLoaded(); return _records.keys.toSet(); }
  Future<void> remove(String assetId) async { await _ensureLoaded(); _records.remove(assetId); await _save(); }
}

class _UploadRecord {
  final String s3Key;
  final String fileName;
  final String? contentHash; // BLAKE2b hash stored after encryption
  final int uploadedAt;

  const _UploadRecord({required this.s3Key, required this.fileName, this.contentHash, required this.uploadedAt});

  Map<String, dynamic> toJson() => {'s3Key': s3Key, 'fileName': fileName, 'contentHash': contentHash, 'uploadedAt': uploadedAt};
  factory _UploadRecord.fromJson(Map<String, dynamic> json) => _UploadRecord(
        s3Key: json['s3Key'] as String,
        fileName: json['fileName'] as String? ?? '',
        contentHash: json['contentHash'] as String?,
        uploadedAt: json['uploadedAt'] as int,
      );
}
