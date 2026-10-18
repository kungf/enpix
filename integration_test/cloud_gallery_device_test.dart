/// On-device E2E: a real photo from the device library is encrypted,
/// uploaded to S3, listed, downloaded, decrypted, hash-verified, and
/// deleted — all through the production services.
///
/// Run:
///   flutter test integration_test/cloud_gallery_device_test.dart \
///     -d `<device-id>` \
///     --dart-define=S3_ACCESS_KEY=minioadmin \
///     --dart-define=S3_SECRET_KEY=minioadmin
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:enpix/domain/entities/storage_config.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/cloud/cloud_media_repository.dart';
import 'package:enpix/services/crypto/crypto_service.dart';
import 'package:enpix/services/storage/s3_service.dart';
import 'package:enpix/services/upload/upload_service.dart';

const String _endpoint = String.fromEnvironment(
  'S3_ENDPOINT',
  defaultValue: 'http://localhost:9000',
);
const String _bucket = String.fromEnvironment(
  'S3_BUCKET',
  defaultValue: 'enpix-test',
);
const String _accessKey = String.fromEnvironment('S3_ACCESS_KEY');
const String _secretKey = String.fromEnvironment('S3_SECRET_KEY');
const String _region = String.fromEnvironment(
  'S3_REGION',
  defaultValue: 'us-east-1',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real photo round-trip through S3', (tester) async {
    expect(_accessKey, isNotEmpty, reason: 'pass --dart-define=S3_ACCESS_KEY');
    expect(_secretKey, isNotEmpty, reason: 'pass --dart-define=S3_SECRET_KEY');

    final permission = await PhotoManager.requestPermissionExtend();
    expect(permission.isAuth, isTrue, reason: 'photo permission required');

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );
    expect(albums, isNotEmpty);

    final assets = await albums.first.getAssetListPaged(page: 0, size: 50);
    expect(assets, isNotEmpty);

    // Prefer a JPEG so the thumbnail generator can decode it.
    final asset = assets.firstWhere(
      (a) => (a.mimeType ?? '').toLowerCase() == 'image/jpeg',
      orElse: () => assets.first,
    );
    final raw = await asset.originBytes;
    expect(raw, isNotNull, reason: 'asset bytes should be readable');
    final plaintext = raw!;
    expect(plaintext, isNotEmpty);

    final s3 = S3Service()
      ..configure(
        StorageConfig(
          endpointUrl: _endpoint,
          bucketName: _bucket,
          region: _region,
          accessKey: _accessKey,
          secretKey: _secretKey,
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

    CloudMedia? uploaded;
    try {
      final result = await uploader.upload(
        plaintext: plaintext,
        fileName: asset.title ?? 'itest.jpg',
        mimeType: asset.mimeType ?? 'image/jpeg',
        createdAt: asset.createDateTime,
        masterKey: masterKey,
      );
      expect(result.success, isTrue, reason: result.error);

      final items = await repository.listThumbnails();
      final matches =
          items.where((item) => item.fileId == result.fileHash).toList();
      expect(matches, hasLength(1), reason: 'uploaded object should be listed');

      final item = matches.single;
      uploaded = item;
      expect(item.originalKey, contains('/files/'));
      expect(item.thumbnailKey, endsWith('_thumb.enc'));

      final thumbnail = await repository.loadThumbnail(item);
      expect(thumbnail, isNotEmpty);

      final original = await repository.fetchOriginal(item);
      expect(original.hashVerified, isTrue);
      expect(original.bytes, equals(plaintext));
    } finally {
      final item = uploaded;
      if (item != null) {
        final report = await repository.deleteAll([item]);
        expect(report.deleted, 1);
        expect(report.failures, isEmpty);
        expect(await s3.objectExists(item.originalKey), isFalse);
        expect(await s3.objectExists(item.thumbnailKey), isFalse);
      }
    }
  });
}
