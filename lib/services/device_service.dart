import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Manages this device's unique ID and human-readable name.
///
/// Device ID (UUID v4) is generated once on first launch and persisted in Keychain.
/// Device name comes from iOS Settings > General > About > Name.
class DeviceService {
  final Logger _log = Logger('DeviceService');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _idKey = 'device_id';
  static const _nameKey = 'device_name';
  static const _pathIdKey = 'device_path_id';

  String? _cachedId;
  String? _cachedName;
  String? _cachedModel;
  String? _cachedPathId;

  /// Get a human-friendly default S3 prefix from device name + model.
  Future<String> getDefaultPrefix() async {
    final name = await getDeviceName();
    final model = await _getDeviceModel();
    return '$name-$model';
  }

  /// Get this device's S3 path identifier: sanitized "{name}-{model}".
  ///
  /// Generated once on first launch from the current device name + model,
  /// then persisted in Keychain. Survives device renames, restarts, and
  /// app reinstalls — photos always stay under one consistent path.
  Future<String> getDevicePathId() async {
    if (_cachedPathId != null) return _cachedPathId!;

    final stored = await _storage.read(key: _pathIdKey);
    if (stored != null) {
      _cachedPathId = stored;
      return stored;
    }

    // First launch: generate from current name + model, then lock it in.
    final name = await getDeviceName();
    final model = await _getDeviceModel();
    final pathId = _sanitizeForS3('$name-$model');
    await _storage.write(key: _pathIdKey, value: pathId);
    _cachedPathId = pathId;
    _log.info('Device path ID generated: $pathId');
    return pathId;
  }

  /// Remove characters unsafe or inconvenient in S3 object keys.
  static String sanitizeForS3(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), '-');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '');
    s = s.replaceAll(RegExp(r'-{2,}'), '-');
    s = s.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return s.isEmpty ? 'unknown-device' : s;
  }

  String _sanitizeForS3(String raw) => DeviceService.sanitizeForS3(raw);

  /// Get this device's model identifier in compact lowercase form.
  /// "iPhone 8" → "iphone8", "iPhone X" → "iphonex".
  Future<String> _getDeviceModel() async {
    if (_cachedModel != null) return _cachedModel!;

    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;
    final raw = iosInfo.modelName;
    final sanitized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    _cachedModel = sanitized;
    _log.info('Device model: $raw → $sanitized');
    return sanitized;
  }

  /// Get or create this device's unique ID.
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    var id = await _storage.read(key: _idKey);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _idKey, value: id);
      _log.info('Generated new device ID: $id');
    }
    _cachedId = id;
    return id;
  }

  /// Get this device's human-readable name, always from the OS.
  /// Caches in-memory for the session; Keychain is used only as a
  /// reference to detect renames (not as the primary source).
  Future<String> getDeviceName() async {
    if (_cachedName != null) return _cachedName!;

    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;
    final name = iosInfo.name; // e.g. "wyang 的 iPhone 8"

    // Detect rename and update Keychain.
    final stored = await _storage.read(key: _nameKey);
    if (stored != name) {
      await _storage.write(key: _nameKey, value: name);
    }

    _cachedName = name;
    _log.info('Device name: $name');
    return name;
  }

  /// Refresh device name from OS (e.g. user renamed their phone).
  Future<String> refreshDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;
    final name = iosInfo.name;
    await _storage.write(key: _nameKey, value: name);
    _cachedName = name;
    return name;
  }
}
