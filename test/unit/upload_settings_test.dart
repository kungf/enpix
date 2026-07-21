import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/services/settings/upload_settings.dart';

void main() {
  group('UploadSettings', () {
    test('defaults', () {
      const s = UploadSettings();
      expect(s.thresholdEnabled, true);
      expect(s.thresholdValue, 0);
      expect(s.unitHours, false);
      expect(s.wifiOnly, true);
    });

    test('round-trips through JSON', () {
      const s = UploadSettings(
        thresholdEnabled: false,
        thresholdValue: 7,
        unitHours: true,
        wifiOnly: false,
      );
      final restored = UploadSettings.fromJson(s.toJson());
      expect(restored, s);
    });

    test('fromJson tolerates missing keys', () {
      expect(UploadSettings.fromJson(const {}), const UploadSettings());
    });

    test('copyWith overrides only specified fields', () {
      const s = UploadSettings();
      final updated = s.copyWith(thresholdValue: 30, unitHours: true);
      expect(updated.thresholdValue, 30);
      expect(updated.unitHours, true);
      expect(updated.thresholdEnabled, s.thresholdEnabled);
      expect(updated.wifiOnly, s.wifiOnly);
    });

    test('equality and hashCode', () {
      const a = UploadSettings(thresholdValue: 5, unitHours: true);
      const b = UploadSettings(thresholdValue: 5, unitHours: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
