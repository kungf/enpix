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

  String? _cachedId;
  String? _cachedName;

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

  /// Get this device's human-readable name.
  /// Refreshes from OS on each cold start, caches for the session.
  Future<String> getDeviceName() async {
    if (_cachedName != null) return _cachedName!;

    final stored = await _storage.read(key: _nameKey);
    if (stored != null) {
      _cachedName = stored;
      return stored;
    }

    // Read from OS
    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;
    final name = iosInfo.name; // e.g. "wyang 的 iPhone 8"

    await _storage.write(key: _nameKey, value: name);
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
