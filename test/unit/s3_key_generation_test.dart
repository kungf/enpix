import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/services/storage/s3_service.dart';

void main() {
  const fileId = 'abc123def456';
  final createdAt = DateTime(2026, 7, 27);
  const deviceId = 'wyang-iphone8';

  group('S3Service.generateKey', () {
    test('uses enpix/{prefix}/{deviceId}/files/... format', () {
      final key = S3Service.generateKey(
        'family',
        fileId,
        createdAt,
        deviceId: deviceId,
      );
      expect(
        key,
        'enpix/family/$deviceId/files/20260727/$fileId.enc',
      );
    });

    test('omits prefix segment when prefix is empty', () {
      final key = S3Service.generateKey(
        '',
        fileId,
        createdAt,
        deviceId: deviceId,
      );
      expect(
        key,
        'enpix/$deviceId/files/20260727/$fileId.enc',
      );
    });

    test('uses "unknown-device" when deviceId not provided', () {
      final key = S3Service.generateKey('enpix', fileId, createdAt);
      expect(key, contains('/unknown-device/files/'));
    });
  });

  group('S3Service.generateThumbKey', () {
    test('uses enpix/{prefix}/{deviceId}/thumbs/... format', () {
      final key = S3Service.generateThumbKey(
        'family',
        fileId,
        createdAt,
        deviceId: deviceId,
      );
      expect(
        key,
        'enpix/family/$deviceId/thumbs/20260727/${fileId}_thumb.enc',
      );
    });

    test('omits prefix when empty', () {
      final key = S3Service.generateThumbKey(
        '',
        fileId,
        createdAt,
        deviceId: deviceId,
      );
      expect(
        key,
        'enpix/$deviceId/thumbs/20260727/${fileId}_thumb.enc',
      );
    });
  });

  group('S3Service.generateDebugKey', () {
    test('uses enpix/{prefix}/{deviceId}/debug/... format', () {
      final key = S3Service.generateDebugKey(
        'family',
        'test.log',
        deviceId: deviceId,
      );
      expect(
        key,
        'enpix/family/$deviceId/debug/test.log',
      );
    });

    test('omits prefix when empty', () {
      final key = S3Service.generateDebugKey(
        '',
        'test.log',
        deviceId: deviceId,
      );
      expect(
        key,
        'enpix/$deviceId/debug/test.log',
      );
    });
  });

  group('prefix trailing slash handling', () {
    test('prefix without trailing slash gets "/" separator', () {
      final key = S3Service.generateKey('pics', fileId, createdAt,
          deviceId: 'd1');
      expect(key, startsWith('enpix/pics/d1/'));
    });

    test('prefix with trailing slash does not double it', () {
      final key = S3Service.generateKey('pics/', fileId, createdAt,
          deviceId: 'd1');
      expect(key, startsWith('enpix/pics/d1/'));
      expect(key, isNot(contains('//')));
    });

    test('empty prefix has no double slash', () {
      final key = S3Service.generateKey('', fileId, createdAt,
          deviceId: 'd1');
      expect(key, startsWith('enpix/d1/'));
      expect(key, isNot(contains('//')));
    });

    test('prefix with multiple trailing slashes handled correctly', () {
      final key = S3Service.generateKey('data//', fileId, createdAt,
          deviceId: 'd1');
      expect(key, startsWith('enpix/data//d1/'));
      expect(key, isNot(contains('///')));
    });
  });
}
