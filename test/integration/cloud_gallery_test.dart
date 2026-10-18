/// End-to-end cloud gallery test against a real S3-compatible server.
///
/// Exercises the production services rather than re-implementing them:
/// S3Service → UploadService (encrypt + upload) → CloudMediaRepository
/// (list, decrypt, hash-verify, delete).
///
/// Run:
///   S3_ENDPOINT=http://localhost:9000 S3_BUCKET=enpix-test \
///     S3_ACCESS_KEY=minioadmin S3_SECRET_KEY=minioadmin \
///     dart run test/integration/cloud_gallery_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:enpix/domain/entities/storage_config.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/cloud/cloud_media_repository.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';
import 'package:enpix/services/upload/upload_service.dart';

void main() async {
  final endpoint =
      Platform.environment['S3_ENDPOINT'] ?? 'http://localhost:9000';
  final bucket = Platform.environment['S3_BUCKET'] ?? 'enpix-test';
  final accessKey = Platform.environment['S3_ACCESS_KEY'] ?? '';
  final secretKey = Platform.environment['S3_SECRET_KEY'] ?? '';
  if (accessKey.isEmpty || secretKey.isEmpty) {
    print('SKIP: S3_ACCESS_KEY and S3_SECRET_KEY not set.');
    return;
  }

  var passed = 0;
  var failed = 0;
  void ok(String message) {
    passed++;
    print('  ✅ $message');
  }

  void fail(String message, Object error) {
    failed++;
    print('  ❌ $message: $error');
  }

  final s3 = S3Service()
    ..configure(
      StorageConfig(
        endpointUrl: endpoint,
        bucketName: bucket,
        region: 'us-east-1',
        accessKey: accessKey,
        secretKey: secretKey,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      deviceId: 'itest-device',
    );
  final crypto = CryptoService();
  final masterKey = crypto.generateMasterKey();
  final uploader = UploadService(crypto, s3);
  final repository = CloudMediaRepository(
    s3: s3,
    crypto: crypto,
    sessionMasterKey: () => masterKey,
  );

  final createdAt = DateTime(2026, 3, 7);
  final source = img.Image(width: 64, height: 48);
  img.fill(source, color: img.ColorRgb8(30, 120, 200));
  final jpeg = Uint8List.fromList(img.encodeJpg(source));

  CloudMediaContent? original;
  CloudMedia? media;
  Object? uploadError;

  print('═══ Cloud Gallery E2E (MinIO) ═══\n');
  print('T1: Upload through UploadService');
  try {
    final result = await uploader.upload(
      plaintext: jpeg,
      fileName: 'itest.jpg',
      mimeType: 'image/jpeg',
      createdAt: createdAt,
      masterKey: masterKey,
    );
    if (!result.success) throw Exception(result.error);
    ok('Encrypt + upload OK (${result.size}B)');
    ok('Key: ${result.s3Key}');
  } on Exception catch (e) {
    uploadError = e;
    fail('Upload', e);
  }

  if (uploadError == null) {
    print('\nT2: List + key correlation');
    try {
      final items = await repository.listThumbnails();
      final matches = items.where((m) => m.deviceId == 'itest-device').toList();
      if (matches.length != 1) {
        throw Exception('expected 1 item, got ${matches.length}');
      }
      media = matches.single;
      if (media.thumbnailKey.endsWith('_thumb.enc') &&
          media.originalKey.contains('/files/')) {
        ok('Thumb/original keys correlate');
      } else {
        throw Exception('bad keys: ${media.thumbnailKey}');
      }
    } on Exception catch (e) {
      fail('Listing', e);
    }
  }

  if (media != null) {
    print('\nT3: Thumbnail download + decrypt');
    try {
      final bytes = await repository.loadThumbnail(media);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('not a decodable image');
      ok('Decrypted thumbnail ${decoded.width}x${decoded.height}');
    } on Exception catch (e) {
      fail('Thumbnail', e);
    }

    print('\nT4: Original download + hash verify');
    try {
      original = await repository.fetchOriginal(media);
      if (!original.hashVerified) throw Exception('hash not verified');
      ok('BLAKE2b hash VERIFIED');
      if (original.bytes.length != jpeg.length) {
        throw Exception('length ${original.bytes.length} != ${jpeg.length}');
      }
      for (var i = 0; i < jpeg.length; i++) {
        if (original.bytes[i] != jpeg[i]) {
          throw Exception('byte mismatch at $i');
        }
      }
      ok('Plaintext byte-perfect');
      if (original.fileName == 'itest.jpg') {
        ok('Filename metadata preserved');
      } else {
        throw Exception('filename: ${original.fileName}');
      }
    } on Exception catch (e) {
      fail('Original', e);
    }

    print('\nT5: Delete original + thumbnail');
    try {
      final report = await repository.deleteAll([media]);
      if (report.deleted != 1 || report.hasFailures) {
        throw Exception(
          'deleted=${report.deleted} failures=${report.failures}',
        );
      }
      final originalExists = await s3.objectExists(media.originalKey);
      final thumbExists = await s3.objectExists(media.thumbnailKey);
      if (originalExists || thumbExists) {
        throw Exception(
          'objects still present (o=$originalExists t=$thumbExists)',
        );
      }
      ok('Both objects removed');
    } on Exception catch (e) {
      fail('Delete', e);
    }
  }

  // Best-effort cleanup so reruns start clean.
  if (media != null) {
    for (final key in [media.originalKey, media.thumbnailKey]) {
      try {
        await s3.deleteObject(key);
      } on Exception {
        // Already gone — expected after T5.
      }
    }
  }

  print('\n═══ Cloud Gallery E2E: $passed passed, $failed failed ═══');
  if (failed > 0) throw Exception('$failed cloud gallery test(s) failed');
}
