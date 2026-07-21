import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

/// One upload record: when it was uploaded (ms since epoch) and its byte size.
///
/// Records migrated from the legacy List format (`["assetId", ...]`) have
/// `timestamp = 0` (unknown) - they are preserved for deduplication but
/// excluded from the activity chart and never pruned by age.
class _UploadRecord {
  final int timestamp;
  final int size;
  const _UploadRecord(this.timestamp, this.size);

  Map<String, dynamic> toJson() => {'t': timestamp, 's': size};

  factory _UploadRecord.fromJson(Map<String, dynamic> json) => _UploadRecord(
        (json['t'] as num?)?.toInt() ?? 0,
        (json['s'] as num?)?.toInt() ?? 0,
      );
}

/// Tracks uploaded files by asset ID with upload timestamp + byte size.
///
/// Storage format (Keychain `upload_records`):
/// ```
/// { "assetId": {"t": 1700000000000, "s": 2048576}, ... }
/// ```
/// Migrates from the prior List format `["assetId", ...]` and the original
/// Map format `{assetId: timestamp}` on load.
///
/// Capacity: prunes records older than 180 days and caps total records at
/// [_maxRecords] (oldest dropped first) to bound Keychain size.
class UploadTracker {
  final Logger _log = Logger('UploadTracker');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'upload_records';
  static const _maxRecords = 10000;
  static const _pruneAge = Duration(days: 180);

  Map<String, _UploadRecord> _records = {};
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
      if (decoded is Map) {
        // Current format: {"assetId": {"t": ms, "s": bytes}}
        // Also handles legacy {"assetId": timestamp} (int) by treating the
        // value as the timestamp.
        _records = {
          for (final entry in decoded.entries)
            entry.key as String: _recordFromDynamic(entry.value),
        };
      } else if (decoded is List) {
        // Prior format: ["assetId1", "assetId2"] -> timestamp unknown (0).
        _records = {
          for (final id in decoded.cast<String>())
            id: const _UploadRecord(0, 0),
        };
        _dirty = true; // Re-save in current format.
        _log.info('Migrated ${_records.length} records from List format');
      }
    }
    final before = _records.length;
    _prune();
    if (_records.length != before) _dirty = true;
    _loaded = true;
    _log.info('Loaded ${_records.length} upload records from Keychain'
        ' (pruned ${before - _records.length})');
  }

  static _UploadRecord _recordFromDynamic(dynamic value) {
    if (value is Map) {
      return _UploadRecord.fromJson(Map<String, dynamic>.from(value));
    }
    if (value is num) {
      // Legacy {"assetId": timestamp} format.
      return _UploadRecord(value.toInt(), 0);
    }
    return const _UploadRecord(0, 0);
  }

  /// Drop records older than [_pruneAge] (excluding timestamp=0 unknowns) and
  /// cap total at [_maxRecords] by dropping the oldest remaining.
  void _prune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _pruneAge.inMilliseconds;
    _records.removeWhere((_, r) => r.timestamp > 0 && r.timestamp < cutoff);
    if (_records.length > _maxRecords) {
      final sorted = _records.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
      final excess = _records.length - _maxRecords;
      for (var i = 0; i < excess; i++) {
        _records.remove(sorted[i].key);
      }
    }
  }

  /// Persist to Keychain. Call after batch operations.
  Future<void> save() async {
    if (!_dirty) return;
    final encoded = jsonEncode({
      for (final entry in _records.entries) entry.key: entry.value.toJson(),
    });
    await _storage.write(key: _key, value: encoded);
    _dirty = false;
    _log.info('Saved ${_records.length} upload records');
  }

  /// Fast check by asset ID.
  Future<bool> isUploaded(String assetId) async {
    await _ensureLoaded();
    return _records.containsKey(assetId);
  }

  /// Mark asset as uploaded with optional byte size. Does NOT persist
  /// immediately - call [save] after a batch.
  Future<void> markUploaded(String assetId, {int? sizeBytes}) async {
    await _ensureLoaded();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final existing = _records[assetId];
    final size = sizeBytes ?? existing?.size ?? 0;
    _records[assetId] = _UploadRecord(ts, size);
    _dirty = true;
  }

  Future<int> get uploadedCount async {
    await _ensureLoaded();
    return _records.length;
  }

  Future<Set<String>> get uploadedAssetIds async {
    await _ensureLoaded();
    return _records.keys.toSet();
  }

  /// Total bytes across all tracked uploads (0 for migrated records without size).
  Future<int> get totalBytes async {
    await _ensureLoaded();
    var sum = 0;
    for (final r in _records.values) {
      sum += r.size;
    }
    return sum;
  }

  /// Upload counts per day for the last [days] days.
  ///
  /// Returns a list of length [days] where index 0 is the oldest day
  /// (`today - days + 1`) and the last index is today. Records with an
  /// unknown timestamp (migrated, `t = 0`) are excluded from the chart.
  Future<List<int>> countsPerDay(int days) async {
    await _ensureLoaded();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(days, 0);
    for (final r in _records.values) {
      if (r.timestamp <= 0) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
      final day = DateTime(date.year, date.month, date.day);
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < days) {
        counts[days - 1 - diff]++;
      }
    }
    return counts;
  }

  Future<void> remove(String assetId) async {
    await _ensureLoaded();
    _records.remove(assetId);
    await save();
  }

  /// Clear all upload records - triggers full re-upload on next backup.
  Future<void> clear() async {
    _records = {};
    _dirty = true;
    await save();
    _log.info('Upload records cleared');
  }
}
