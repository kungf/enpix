import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import 'upload_settings.dart';

/// Persists [UploadSettings] to Keychain and exposes them reactively.
///
/// Imitates the TtlEngine pattern: a StateNotifier that loads from
/// FlutterSecureStorage on construction and writes through on every update.
class UploadSettingsNotifier extends StateNotifier<UploadSettings> {
  final Logger _log = Logger('UploadSettingsNotifier');
  final FlutterSecureStorage _storage;
  static const _key = 'upload_settings';

  UploadSettingsNotifier(this._storage) : super(const UploadSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await _storage.read(key: _key);
      if (json != null) {
        state =
            UploadSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
        _log.info('Loaded upload settings: $state');
      }
    } catch (e, st) {
      _log.warning('Failed to load upload settings, using defaults: $e', e, st);
    }
  }

  /// Replace settings and persist immediately.
  Future<void> update(UploadSettings settings) async {
    state = settings;
    await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
    _log.info('Saved upload settings: $settings');
  }

  Future<void> setThresholdEnabled(bool enabled) =>
      update(state.copyWith(thresholdEnabled: enabled));

  Future<void> setThresholdValue(double value) =>
      update(state.copyWith(thresholdValue: value));

  Future<void> setUnitHours(bool hours) =>
      update(state.copyWith(unitHours: hours));

  Future<void> setWifiOnly(bool wifiOnly) =>
      update(state.copyWith(wifiOnly: wifiOnly));
}

final uploadSettingsProvider =
    StateNotifierProvider<UploadSettingsNotifier, UploadSettings>((ref) {
  return UploadSettingsNotifier(const FlutterSecureStorage());
});
