import 'package:flutter_test/flutter_test.dart';
import 'package:see_photo/services/ttl/ttl_config.dart';

void main() {
  group('TtlConfig', () {
    test('default config is disabled', () {
      const cfg = TtlConfig();
      expect(cfg.isEnabled, false);
      expect(cfg.timeEnabled, false);
      expect(cfg.timeDays, 30);
      expect(cfg.sizeEnabled, false);
      expect(cfg.sizeGb, 100);
    });

    test('isEnabled is true when time enabled', () {
      const cfg = TtlConfig(timeEnabled: true, timeDays: 7);
      expect(cfg.isEnabled, true);
    });

    test('isEnabled is true when size enabled', () {
      const cfg = TtlConfig(sizeEnabled: true, sizeGb: 50);
      expect(cfg.isEnabled, true);
    });

    test('copyWith preserves unmodified fields', () {
      const original = TtlConfig(timeEnabled: true, timeDays: 14);
      final copy = original.copyWith(sizeEnabled: true, sizeGb: 50);
      expect(copy.timeEnabled, true);
      expect(copy.timeDays, 14);
      expect(copy.sizeEnabled, true);
      expect(copy.sizeGb, 50);
    });

    test('toJson and fromJson roundtrip', () {
      const original = TtlConfig(
        timeEnabled: true,
        timeDays: 7,
        sizeEnabled: true,
        sizeGb: 200,
      );
      final json = original.toJson();
      final restored = TtlConfig.fromJson(json);
      expect(restored.timeEnabled, original.timeEnabled);
      expect(restored.timeDays, original.timeDays);
      expect(restored.sizeEnabled, original.sizeEnabled);
      expect(restored.sizeGb, original.sizeGb);
    });

    test('fromJson handles missing fields with defaults', () {
      final cfg = TtlConfig.fromJson({});
      expect(cfg.timeEnabled, false);
      expect(cfg.timeDays, 30);
      expect(cfg.sizeEnabled, false);
      expect(cfg.sizeGb, 100);
    });

    test('toString shows config summary', () {
      const cfg = TtlConfig(timeEnabled: true, timeDays: 7);
      expect(cfg.toString(), contains('7d'));
      expect(cfg.toString(), contains('off'));
    });
  });
}
