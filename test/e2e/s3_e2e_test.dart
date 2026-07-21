@TestOn('vm')
library;

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:enpix/services/storage/s3_service.dart';
import 'package:enpix/domain/entities/storage_config.dart';
import 'e2e_config.dart';

/// End-to-end tests for S3 storage operations against a real endpoint.
///
/// These tests hit a real S3/MinIO server configured in test/e2e/.env.e2e.
/// They are excluded from normal `flutter test` runs.
/// Run: flutter test test/e2e/s3_e2e_test.dart
///
/// Note: the bucket must already exist on the S3 server.
void main() {
  late E2EConfig config;
  late S3Service s3;

  setUpAll(() async {
    config = await E2EConfig.load();
    s3 = S3Service();
    s3.configure(
      StorageConfig(
        endpointUrl: config.s3Endpoint,
        bucketName: config.s3Bucket,
        region: config.s3Region,
        accessKey: config.s3AccessKey,
        secretKey: config.s3SecretKey,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      kekFingerprint: 'e2e-test-fp',
      deviceId: 'e2e-test-device',
    );
  });

  test(
    'testConnection — full SigV4 round-trip',
    () async {
      // HEAD bucket + LIST + PUT + GET + DELETE with SigV4 signing.
      // This validates the entire signature pipeline against a real S3 endpoint.
      // NOTE: the bucket must exist on the server. If this test fails with 404,
      // create the bucket first (e.g. via MinIO console or mc CLI).
      final result = await s3.testConnection();
      print('[E2E] connection test: $result');
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  group('listObjects', () {
    test('with fingerprint prefix', () async {
      final objects = await s3.listObjects('e2e-test-fp/');
      print('[E2E] listed ${objects.length} objects under e2e-test-fp/');
    });

    test('with device prefix containing /', () async {
      final objects = await s3.listObjects('e2e-test-fp/e2e-test-device/');
      print(
        '[E2E] listed ${objects.length} objects under e2e-test-fp/e2e-test-device/',
      );
    });

    test('returns empty for non-existent prefix', () async {
      final n =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      final objects = await s3.listObjects('e2e-test-fp/nonexistent_$n/');
      expect(objects, isEmpty);
    });
  });

  group('put + get + delete', () {
    test(
      'round-trip — verifies PUT, GET, objectExists, DELETE signatures',
      () async {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        const key = 'e2e-test-fp/e2e-test-device/files/20250712/e2e_rt.enc';

        // PUT
        await s3.putObject(key, data);
        print('[E2E] PUT OK');

        // GET
        final got = await s3.getObject(key);
        expect(got, equals(data));
        print('[E2E] GET OK');

        // HEAD (objectExists)
        final exists = await s3.objectExists(key);
        expect(exists, isTrue);
        print('[E2E] HEAD OK');

        // DELETE
        await s3.deleteObject(key);
        final gone = await s3.objectExists(key);
        expect(gone, isFalse);
        print('[E2E] DELETE OK');
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  group('cloud-gallery exact pattern', () {
    test('prefix with UUID-style deviceId and "thumbs/"', () async {
      const fingerprint = 'e2e-test-fp';
      const deviceId = '00b74fb5-b574-4f6f-83e5-d2da08d67c2a';
      const prefix = '$fingerprint/$deviceId/thumbs/';
      print('[E2E] listing prefix: $prefix');
      final objects = await s3.listObjects(prefix);
      print('[E2E] listed ${objects.length} objects');
    });

    test('prefix with / (path separator)', () async {
      final objects = await s3.listObjects('e2e-test-fp/devices/');
      print('[E2E] listed ${objects.length} devices');
    });

    test('long prefix with multiple / separators', () async {
      final objects =
          await s3.listObjects('e2e-test-fp/e2e-test-device/files/20250712/');
      print('[E2E] listed ${objects.length} objects');
    });
  });

  /// Real-data tests against the wytest bucket's actual content.
  /// These tests reproduce the exact error seen on device:
  ///   "LIST failed: prefix=yJrrWkKmkKuE/00b74fb5-.../thumbs/ — XmlParserException"
  group('real-data regression', () {
    test('devices/ (this worked in a previous version)', () async {
      final objects = await s3.listObjects('yJrrWkKmkKuE/devices/');
      print('[E2E] devices → ${objects.length} objects');
      for (final o in objects) {
        print('  ${o.key}');
      }
    });

    test('exact failing prefix — catch and print raw response', () async {
      const prefix =
          'yJrrWkKmkKuE/00b74fb5-b574-4f6f-83e5-d2da08d67c2a/thumbs/';
      print('[E2E] reproducing device error: $prefix');
      try {
        final objects = await s3.listObjects(prefix);
        print('[E2E] listed ${objects.length} objects');
      } catch (e) {
        print('[E2E] CAUGHT: $e');
        // Print the actual error type
        print('[E2E] error type: ${e.runtimeType}');
        rethrow;
      }
    });
  });
}
